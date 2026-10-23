import 'dart:async';
import 'dart:collection';

import '../contracts/bridge_events.dart';
import '../contracts/context_configuration.dart';
import '../contracts/form_action.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_state.dart';
import '../contracts/form_state_bridge.dart';
import '../contracts/form_value.dart';
import '../contracts/intelligence.dart';
import '../contracts/trace.dart';
import '../contracts/validation_metadata.dart';
import 'action_runtime.dart';
import 'context_compiler.dart';
import 'input_router.dart';
import 'multilingual.dart';
import 'native_form.dart';
import 'runtime_events.dart';

/// Headless interaction runtime. Its only form-state boundary is the injected
/// FormStateBridge. It does not own the bridge or its existing renderer/store.
final class FormAssistantRuntime {
  final FormIR form;
  final FormStateBridge bridge;
  final IntelligenceAdapter intelligence;
  final String locale;
  final List<FieldVisibilityRule> visibilityRules;
  final int maxStaleRetries;
  late final ActionRuntime _actions;
  late final ContextCompiler _compiler;
  final ContextBudget contextBudget;
  final List<String> _recentFields = [];
  final List<InteractionHistoryEntry> _history = [];
  late final StreamSubscription<FormStateBridgeEvent> _subscription;
  final StreamController<RuntimeEvent> _events =
      StreamController.broadcast(sync: true);
  final Queue<RuntimeEvent> _eventQueue = Queue();
  final Map<OperationId, _OperationTrace> _operations = {};
  RuntimeState _state = RuntimeState(phase: RuntimePhase.idle);
  Future<void> _tail = Future<void>.value();
  final Completer<void> _disposedSignal = Completer();
  bool _disposed = false;
  bool _bridgeDisposed = false;
  bool _emitting = false;
  Future<void>? _disposal;
  CancellationToken? _activeCancellation;

  FormAssistantRuntime(
      {required this.form,
      required this.bridge,
      required this.intelligence,
      String locale = 'en',
      List<FieldVisibilityRule> visibilityRules = const [],
      this.maxStaleRetries = 2,
      ContextBudget? contextBudget,
      Map<FieldId, List<FieldId>> dependenciesByField = const {}})
      : locale = normalizeSemanticLocale(locale),
        visibilityRules = List.unmodifiable(visibilityRules),
        contextBudget = contextBudget ?? ContextBudget() {
    if (this.locale.isEmpty) {
      throw ArgumentError('Invalid locale');
    }
    _compiler = ContextCompiler(
        form: form,
        budget: this.contextBudget,
        dependencies: dependenciesByField);
    if (form.id != bridge.snapshot.formId || maxStaleRetries < 0) {
      throw ArgumentError('Invalid form identity/retry limit');
    }
    _actions = ActionRuntime(
        form: form,
        bridge: bridge,
        emit: _emit,
        isDisposed: () =>
            _disposed ||
            _bridgeDisposed ||
            (_activeCancellation?.isCancelled ?? false),
        registerOperation: (trace, actions, batch) {
          _operations[trace.operationId] =
              _OperationTrace(trace, actions, batch);
        },
        visibilityRules: this.visibilityRules);
    _subscription = bridge.events.listen(_onBridgeEvent,
        onError: (Object error, StackTrace stack) {
      _emit(RuntimeError(code: 'runtime.bridge_event_error', cause: error));
    });
  }
  RuntimeState get state => _state;
  Stream<RuntimeEvent> get events => _events.stream;
  void _emit(RuntimeEvent event) {
    if (_disposed || _events.isClosed) return;
    _eventQueue.add(event);
    if (_emitting) return;
    _emitting = true;
    try {
      while (_eventQueue.isNotEmpty) {
        _events.add(_eventQueue.removeFirst());
      }
    } finally {
      _emitting = false;
    }
  }

  void _stateChanged(RuntimeState state) {
    if (_disposed) return;
    _state = state;
    _emit(RuntimeStateChanged(state: state, trace: state.trace));
  }

  void _onBridgeEvent(FormStateBridgeEvent event) {
    final operationId = switch (event) {
      StateChanged(:final operationId) => operationId,
      ActiveFieldChanged(:final operationId) => operationId,
      ActionCompleted(:final operationId) => operationId,
      BatchCompleted(:final operationId) => operationId,
      BridgeError(:final operationId) => operationId,
      _ => null,
    };
    if (event is StateChanged) {
      for (final change in event.changes) {
        _recentFields.remove(change.fieldId);
        _recentFields.insert(0, change.fieldId);
      }
      if (_recentFields.length > contextBudget.maxRecentFields) {
        _recentFields.removeRange(
            contextBudget.maxRecentFields, _recentFields.length);
      }
    }
    final record = _operations[operationId];
    TraceContext? trace = record?.trace;
    if (event is ActionCompleted && record != null) {
      if (record.completed < record.actions.length) {
        trace = record.trace.withProposal(record.trace.proposalId!,
            actionId: record.actions[record.completed++].id);
      }
      if (!record.batch) _operations.remove(operationId);
    }
    if (event is BatchCompleted) _operations.remove(operationId);
    if (event is BridgeDisposed) {
      _bridgeDisposed = true;
      _activeCancellation?.cancel();
      if (!_disposedSignal.isCompleted) _disposedSignal.complete();
    }
    _emit(RuntimeBridgeEvent(event: event, trace: trace));
  }

  Future<T> _enqueue<T>(Future<T> Function() work) {
    final result = _tail.then<T>((_) => work());
    _tail =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  TraceContext _inputTrace(UserInput input, TraceContext trace) {
    if ([trace.interactionId, trace.requestId, trace.operationId]
            .any((id) => id.isEmpty) ||
        (input.segmentId != null &&
            trace.segmentId != null &&
            input.segmentId != trace.segmentId)) {
      throw ArgumentError('Invalid trace identity');
    }
    return TraceContext(
        interactionId: trace.interactionId,
        requestId: trace.requestId,
        operationId: trace.operationId,
        segmentId: trace.segmentId ?? input.segmentId);
  }

  Future<RuntimeInteractionResult> submit(UserInput input,
      {required TraceContext trace,
      String? locale,
      Iterable<FieldId> contextFieldIds = const [],
      Iterable<FieldId> dependencyFieldIds = const [],
      BatchApplyMode mode = BatchApplyMode.bestEffort,
      IntelligenceOptions options = const IntelligenceOptions()}) {
    final inputTrace = _inputTrace(input, trace);
    final requestLocale = _requestLocale(locale);
    final selected = List<FieldId>.unmodifiable(contextFieldIds);
    final dependencies = List<FieldId>.unmodifiable(dependencyFieldIds);
    return _enqueue(() => _withCancellation(
        options,
        (effective) => _run(
            input, inputTrace, bridge.snapshot, selected, dependencies, mode,
            locale: requestLocale, options: effective)));
  }

  /// Executes an already-produced proposal while retaining its original basis.
  /// [basedOn] must be captured from this same bridge lifecycle before proposing.
  Future<RuntimeInteractionResult> executeProposal(ActionProposal proposal,
      {required UserInput input,
      required TraceContext trace,
      required FormStateSnapshot basedOn,
      String? locale,
      Iterable<FieldId> contextFieldIds = const [],
      Iterable<FieldId> dependencyFieldIds = const [],
      BatchApplyMode mode = BatchApplyMode.bestEffort,
      IntelligenceOptions options = const IntelligenceOptions()}) {
    final inputTrace = _inputTrace(input, trace);
    final requestLocale = _requestLocale(locale);
    final selected = List<FieldId>.unmodifiable(contextFieldIds);
    final dependencies = List<FieldId>.unmodifiable(dependencyFieldIds);
    return _enqueue(() => _withCancellation(
        options,
        (effective) => _run(
            input, inputTrace, basedOn, selected, dependencies, mode,
            locale: requestLocale, initial: proposal, options: effective)));
  }

  String _requestLocale(String? locale) {
    final resolved = normalizeSemanticLocale(locale ?? this.locale);
    if (resolved.isEmpty) {
      throw ArgumentError('Invalid locale');
    }
    return resolved;
  }

  Future<RuntimeInteractionResult> _withCancellation(
      IntelligenceOptions options,
      Future<RuntimeInteractionResult> Function(IntelligenceOptions)
          work) async {
    final token = CancellationToken();
    _activeCancellation = token;
    final detach = options.cancellation?.listen(token.cancel);
    try {
      return await work(
          IntelligenceOptions(timeout: options.timeout, cancellation: token));
    } finally {
      token.cancel();
      detach?.call();
      _activeCancellation = null;
    }
  }

  bool _relevantChanged(
      ActionProposal proposal,
      FormStateSnapshot before,
      FormStateSnapshot after,
      SemanticContext context,
      List<FieldId> dependencies) {
    if (before.formId != after.formId ||
        before.lifecycle != after.lifecycle ||
        before.activeFieldId != after.activeFieldId) {
      return true;
    }
    // Compare the exact selected semantic surface, independently of revision.
    // Unrelated changes may revalidate; selected answers/focus/lifecycle may not.
    final freshContext = SemanticContext(
      formId: context.formId,
      revision: after.revision,
      locale: context.locale,
      activeFieldId: after.activeFieldId,
      recentFieldIds: context.recentFieldIds,
      fields: [
        for (final field in context.fields)
          FormFieldContext(
              field: field.field,
              currentValue: after.values[field.id],
              writable:
                  field.writable && after.lifecycle == FormLifecycle.active,
              optionsTruncated: field.optionsTruncated)
      ],
    );
    if (freshContext.fingerprint != context.fingerprint) return true;
    final touched = <FieldId>{
      ...dependencies,
      ...context.fields.map((f) => f.field.id)
    };
    for (final proposed in proposal.actions) {
      final action = proposed.action;
      if (action is FormMutationAction) touched.add(action.fieldId);
      if (action is RequestClarificationAction) touched.addAll(action.fieldIds);
      if (action is NavigateAction && action.target is FieldNavigationTarget) {
        touched.add((action.target as FieldNavigationTarget).fieldId);
      }
    }
    return touched.any((id) => before.values[id] != after.values[id]);
  }

  bool _validProposal(
      ActionProposal proposal, TraceContext trace, FormStateSnapshot basis) {
    final provenance = proposal.provenance.trace;
    return proposal.baseRevision == basis.revision &&
        basis.formId == form.id &&
        provenance.interactionId == trace.interactionId &&
        provenance.requestId == trace.requestId &&
        provenance.operationId == trace.operationId &&
        provenance.segmentId == trace.segmentId &&
        (provenance.proposalId == null || provenance.proposalId == proposal.id);
  }

  RuntimeInteractionResult _failure(String code, TraceContext trace,
      {Object? cause, ActionProposal? proposal}) {
    _stateChanged(
        RuntimeState(phase: RuntimePhase.error, trace: trace, errorCode: code));
    _emit(RuntimeError(code: code, cause: cause, trace: trace));
    final result = RuntimeInteractionResult(
        proposal: proposal,
        trace: trace,
        actions: [],
        snapshot: bridge.snapshot,
        status: BatchStatus.rejected,
        errorCode: code);
    _emit(InteractionCompleted(result));
    return result;
  }

  Future<RuntimeInteractionResult> _run(
      UserInput input,
      TraceContext root,
      FormStateSnapshot basis,
      List<FieldId> selected,
      List<FieldId> dependencies,
      BatchApplyMode mode,
      {required String locale,
      ActionProposal? initial,
      required IntelligenceOptions options}) async {
    var trace = root;
    var original = basis;
    ActionProposal? proposal = initial;
    var retries = 0;
    SemanticContext? compiled;
    while (true) {
      if (_disposed || _bridgeDisposed) {
        return _failure('runtime.disposed', trace);
      }
      if (options.cancellation?.isCancelled ?? false) {
        return _failure('runtime.cancelled', trace);
      }
      try {
        if (compiled == null) {
          final result = _compiler.compile(
              snapshot: original,
              writable: bridge.capabilities.writable,
              input: input,
              candidates: selected,
              explicitDependencies: dependencies,
              recent: List.of(_recentFields),
              history: List.of(_history),
              locale: locale);
          compiled = result.context;
          _emit(ContextCompiled(diagnostics: result.diagnostics, trace: trace));
        }
      } catch (error) {
        return _failure(
            error is ContextBudgetExceeded
                ? 'runtime.context_budget_exceeded'
                : 'runtime.context_invalid',
            trace,
            cause: error);
      }
      final context = compiled;
      if (proposal == null) {
        final active = form.fields.where((f) => f.id == original.activeFieldId);
        final activeField = active.isEmpty ? null : active.single;
        var decision = const InputRouter()
            .route(input, activeField: activeField, locale: locale);
        if (decision.route == InputRoute.needsIntelligence) {
          final switched =
              evaluateCodeSwitch(input.text, activeField: activeField);
          final otherLanguage =
              switched.locales.any((item) => item.split('-').first != 'en');
          if (otherLanguage &&
              switched.result.route != InputRoute.needsIntelligence) {
            decision = switched.result;
          }
        }
        _emit(InputRouted(result: decision, trace: trace));
        if (decision.route != InputRoute.needsIntelligence) {
          final id = '${trace.requestId}/deterministic';
          final actions = decision.route == InputRoute.needsClarification
              ? <FormAction>[
                  RequestClarificationAction(
                      reason: decision.reason == 'invalid_value'
                          ? ClarificationReason.invalidValue
                          : ClarificationReason.ambiguous,
                      fieldIds: [
                        if (original.activeFieldId != null)
                          original.activeFieldId!
                      ],
                      detail: decision.reason)
                ]
              : decision.actions;
          proposal = ActionProposal(
              id: id,
              baseRevision: original.revision,
              actions: [
                for (var i = 0; i < actions.length; i++)
                  ProposedAction(id: '$id/action/$i', action: actions[i])
              ],
              provenance: ActionProvenance(
                  trace: trace,
                  adapterId: 'deterministic_input_router',
                  adapterVersion: '0.1.0',
                  origin: ActionOrigin.deterministic));
        }
      }
      if (proposal == null) {
        _stateChanged(
            RuntimeState(phase: RuntimePhase.interpreting, trace: trace));
        final request = IntelligenceRequest(
            input: input,
            context: context,
            allowedActionTypes: const [
              'set_value',
              'clear_value',
              'navigate',
              'request_clarification'
            ],
            trace: trace);
        _emit(InterpretationRequested(request));
        try {
          if (_disposed || _bridgeDisposed) {
            return _failure('runtime.disposed', trace);
          }
          final result = await Future.any<IntelligenceResult?>([
            runIntelligence(
                () => intelligence.interpret(request, options: options),
                options),
            _disposedSignal.future.then<IntelligenceResult?>((_) => null)
          ]);
          if (result == null || _disposed || _bridgeDisposed) {
            return _failure('runtime.disposed', trace);
          }
          _emit(IntelligenceQualityEvaluated(
              outcome: result.quality,
              reason: result.qualityReason,
              trace: trace));
          proposal = result.proposal;
          if (proposal.provenance.adapterId != intelligence.id ||
              proposal.provenance.adapterVersion != intelligence.version) {
            return _failure('runtime.provenance_invalid', trace,
                proposal: proposal);
          }
        } catch (error) {
          if (_disposed || _bridgeDisposed) {
            return _failure('runtime.disposed', trace);
          }
          return _failure(
              error is IntelligenceCancelled
                  ? 'runtime.cancelled'
                  : error is TimeoutException
                      ? 'runtime.intelligence_timeout'
                      : 'runtime.interpretation_failed',
              trace,
              cause: error);
        }
      }
      if (!_validProposal(proposal, trace, original)) {
        return _failure('runtime.proposal_invalid', trace, proposal: proposal);
      }
      final proposalTrace = trace.withProposal(proposal.id);
      _emit(ProposalReceived(proposal: proposal, trace: proposalTrace));
      if (options.cancellation?.isCancelled ?? false) {
        return _failure('runtime.cancelled', proposalTrace, proposal: proposal);
      }
      final latest = bridge.snapshot;
      if (original.revision > latest.revision) {
        return _failure('runtime.basis_invalid', proposalTrace,
            proposal: proposal);
      }
      if (_relevantChanged(proposal, original, latest, context, dependencies)) {
        _emit(ProposalDiscarded(
            proposal: proposal,
            reason: 'relevant_context_changed',
            trace: proposalTrace));
        if (retries++ >= maxStaleRetries) {
          return _failure('runtime.stale_retry_limit', proposalTrace,
              proposal: proposal);
        }
        compiled = null;
        original = latest;
        trace = root.retry(retries);
        proposal = null;
        continue;
      }
      if (proposal.baseRevision != latest.revision) {
        _emit(ProposalRevalidated(
            proposal: proposal,
            revision: latest.revision,
            trace: proposalTrace));
      }
      _stateChanged(
          RuntimeState(phase: RuntimePhase.executing, trace: proposalTrace));
      late final List<RuntimeActionResult> results;
      try {
        results = await _actions.execute(proposal.actions,
            trace: proposalTrace,
            expected: latest,
            mode: mode,
            origin: proposal.provenance.origin);
      } catch (error) {
        return _failure('runtime.execution_failed', proposalTrace,
            cause: error, proposal: proposal);
      } finally {
        _operations.remove(proposalTrace.operationId);
      }
      final stale = results.any((r) {
        final result = r.bridgeResult;
        return result is ActionRejected &&
            result.rejection.code == ActionRejectionCode.staleRevision;
      });
      if (stale && !results.any((r) => r.accepted)) {
        if (retries++ >= maxStaleRetries) {
          return _failure('runtime.stale_retry_limit', proposalTrace,
              proposal: proposal);
        }
        final current = bridge.snapshot;
        if (_relevantChanged(
            proposal, original, current, context, dependencies)) {
          _emit(ProposalDiscarded(
              proposal: proposal, reason: 'commit_race', trace: proposalTrace));
          compiled = null;
          original = current;
          trace = root.retry(retries);
          proposal = null;
        }
        // If unrelated, retain the original proposal/basis and revalidate again.
        continue;
      }
      final accepted = results.where((r) => r.accepted).length;
      final clarifications = results
          .map((r) => r.clarification)
          .whereType<RequestClarificationAction>()
          .toList();
      if (stale && accepted > 0) {
        final clarification = RequestClarificationAction(
            reason: ClarificationReason.ambiguous,
            fieldIds: results
                .where((r) => !r.accepted)
                .map((r) => r.proposedAction.action)
                .whereType<FormMutationAction>()
                .map((a) => a.fieldId),
            detail: 'The form changed while applying this request.');
        clarifications.add(clarification);
        _emit(ClarificationRequested(
            action: clarification, trace: proposalTrace));
      }
      final status = accepted < results.length
          ? (accepted > 0 ? BatchStatus.partiallyApplied : BatchStatus.rejected)
          : results.any((r) =>
                  r.bridgeResult is ActionApplied || r.clarification != null)
              ? BatchStatus.applied
              : BatchStatus.noOp;
      final result = RuntimeInteractionResult(
          proposal: proposal,
          trace: proposalTrace,
          actions: results,
          snapshot: bridge.snapshot,
          status: status,
          errorCode: stale ? 'runtime.partial_stale' : null);
      _stateChanged(RuntimeState(
          phase: clarifications.isEmpty
              ? RuntimePhase.idle
              : RuntimePhase.awaitingClarification,
          trace: proposalTrace,
          clarifications: clarifications,
          errorCode: result.errorCode));
      if (contextBudget.maxHistoryEntries > 0 &&
          root.interactionId.length <= contextBudget.maxHistoryEntryChars) {
        _history.add(InteractionHistoryEntry(
            interactionId: root.interactionId,
            text: String.fromCharCodes(
                input.text.runes.take(contextBudget.maxHistoryEntryChars)),
            fieldIds: results
                .where((r) => r.accepted)
                .expand((r) {
                  final action = r.proposedAction.action;
                  return action is FormMutationAction
                      ? [action.fieldId]
                      : <String>[];
                })
                .toSet()
                .take(contextBudget.maxFields)
                .toList()));
        if (_history.length > contextBudget.maxHistoryEntries) {
          _history.removeAt(0);
        }
      }
      _emit(InteractionCompleted(result));
      return result;
    }
  }

  /// Manual native-form edit. This does not call the intelligence adapter.
  Future<RuntimeInteractionResult> commitNative(FormAction action,
      {required TraceContext trace}) {
    final basedOn = bridge.snapshot;
    return executeProposal(
        nativeManualProposal(action: action, basedOn: basedOn, trace: trace),
        input: const UserInput(text: 'native'),
        trace: trace,
        basedOn: basedOn);
  }

  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    _activeCancellation?.cancel();
    if (!_disposedSignal.isCompleted) _disposedSignal.complete();
    _state = RuntimeState(phase: RuntimePhase.disposed);
    await _subscription.cancel();
    _operations.clear();
    _recentFields.clear();
    _history.clear();
    _eventQueue.clear();
    await _events.close();
  }
}

final class _OperationTrace {
  final TraceContext trace;
  final List<ProposedAction> actions;
  final bool batch;
  int completed = 0;
  _OperationTrace(this.trace, this.actions, this.batch);
}

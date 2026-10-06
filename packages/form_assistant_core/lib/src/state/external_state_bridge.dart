import 'dart:async';
import 'dart:collection';

import '../contracts/bridge_events.dart';
import '../contracts/form_action.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_state.dart';
import '../contracts/form_state_bridge.dart';
import '../contracts/form_value.dart';
import '../validation/form_ir_validator.dart';
import 'external_state_source.dart';

/// Canonical projection of an authoritative existing store.
/// Source-specific knowledge is confined to the integration-owned source and
/// mapping callbacks. This bridge never publishes speculative form values.
class ExternalStateBridge<TState, TMutation> implements FormStateBridge {
  @override
  final String id;
  @override
  String get version => '0.1.0';
  @override
  late final FormStateBridgeCapabilities capabilities;
  final FormIR form;
  final ExternalStateSource<TState, TMutation> source;
  final FormStateSnapshot Function(TState state, Revision revision) mapSnapshot;

  /// Receives the action and its planned canonical snapshot. For navigation,
  /// use the planned activeFieldId rather than interpreting source encodings.
  final TMutation Function(FormAction action, FormStateSnapshot planned)
      mapMutation;
  final Duration acknowledgementTimeout;
  late final Map<FieldId, FormField> _fields;
  late FormStateSnapshot _snapshot;
  late int _sourceVersion;
  late final StreamController<FormStateBridgeEvent> _events;
  late final StreamSubscription<ExternalStoreSnapshot<TState>> _subscription;
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  bool _disposed = false;
  bool _initialized = false;
  bool _mappingFailed = false;
  bool _sourceFailed = false;
  bool _emitting = false;
  final Queue<FormStateBridgeEvent> _eventQueue = Queue();
  bool _processingUpdates = false;
  int _externalGeneration = 0;
  final Queue<ExternalStoreSnapshot<TState>> _updates = Queue();
  _PendingWrite<TState>? _pending;

  ExternalStateBridge({
    required this.form,
    required this.source,
    required this.mapSnapshot,
    required this.mapMutation,
    this.id = 'external',
    this.acknowledgementTimeout = const Duration(seconds: 5),
    FormStateBridgeCapabilities? capabilities,
  }) {
    if (acknowledgementTimeout <= Duration.zero) {
      throw ArgumentError('Timeout must be positive');
    }
    this.capabilities = capabilities ??
        FormStateBridgeCapabilities(
            writable: true,
            supportsBatch: true,
            supportsAtomicBatch: source.supportsAtomicBatch,
            supportsUndo: false,
            supportsRedo: false,
            supportsExternalChanges: true,
            supportsActiveField: true,
            supportsNavigation: true);
    final caps = this.capabilities;
    if (!caps.supportsExternalChanges ||
        caps.supportsUndo ||
        caps.supportsRedo ||
        (caps.supportsAtomicBatch &&
            (!caps.supportsBatch || !source.supportsAtomicBatch)) ||
        (caps.supportsNavigation && !caps.supportsActiveField)) {
      throw ArgumentError('Capabilities must reflect actual source guarantees');
    }
    _fields = {for (final field in form.fields) field.id: field};
    if (_fields.length != form.fields.length ||
        _fields.keys.any((id) => id.isEmpty)) {
      throw ArgumentError('Invalid field IDs');
    }
    for (final field in form.fields) {
      if (field.constraints?.pattern case final String pattern) {
        RegExp(pattern);
      }
      final options = field.options;
      if (options != null &&
          (options.any((o) => o.id.isEmpty) ||
              options.map((o) => o.id).toSet().length != options.length)) {
        throw ArgumentError('Invalid option IDs');
      }
    }
    final initial = source.snapshot;
    if (initial.version < 0) {
      throw ArgumentError('Source version must be nonnegative');
    }
    _sourceVersion = initial.version;
    _snapshot = _project(initial.state, 0);
    _events = StreamController<FormStateBridgeEvent>.broadcast(
        sync: true,
        onListen: () {
          if (!_initialized && !_disposed) unawaited(_enqueue<void>(() {}));
        });
    _subscription = source.changes.listen(_observe,
        onError: (Object error, StackTrace stack) {
      if (!_disposed) {
        _sourceFailed = true;
        _error(BridgeErrorCode.externalStoreFailure,
            'Source subscription failed', error);
      }
    }, onDone: () {
      if (!_disposed) {
        _sourceFailed = true;
        _error(BridgeErrorCode.externalStoreFailure,
            'Source subscription ended', null);
      }
    });
    // Close the read/subscribe window without inventing local authoritative state.
    _observe(source.snapshot);
  }
  @override
  FormStateSnapshot get snapshot => _snapshot;
  @override
  Stream<FormStateBridgeEvent> get events => _events.stream;
  DateTime _now() => DateTime.now().toUtc();
  void _initialize() {
    if (!_initialized && !_disposed && _events.hasListener) {
      _initialized = true;
      _emit(BridgeInitialized(
          bridgeId: id, timestamp: _now(), snapshot: _snapshot));
    }
  }

  void _emit(FormStateBridgeEvent event) {
    if (_events.isClosed) return;
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
    _drainUpdates();
  }

  void _error(BridgeErrorCode code, String message, Object? cause,
      {ApplyContext? context}) {
    _initialize();
    _emit(BridgeError(
        bridgeId: id,
        timestamp: _now(),
        code: code,
        message: message,
        recoverable: true,
        cause: cause,
        interactionId: context?.interactionId,
        operationId: context?.operationId));
  }

  Future<T> _enqueue<T>(FutureOr<T> Function() work) {
    final result = _tail.then<T>((_) {
      _initialize();
      return work();
    });
    _tail =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  FormStateSnapshot _project(TState state, Revision revision) {
    final mapped = mapSnapshot(state, revision);
    if (mapped.formId != form.id ||
        mapped.revision != revision ||
        (mapped.activeFieldId != null &&
            (!_fields.containsKey(mapped.activeFieldId) ||
                !capabilities.supportsActiveField))) {
      throw StateError('Snapshot mapper violated canonical identity/revision');
    }
    for (final entry in mapped.values.entries) {
      final field = _fields[entry.key];
      if (field == null ||
          validateFieldAction(
                  field, SetValueAction(fieldId: entry.key, value: entry.value))
              .any((issue) =>
                  issue.code == 'value.type_mismatch' ||
                  issue.code == 'value.option_unknown')) {
        throw StateError(
            'Snapshot mapper returned an unknown canonical field/type/option');
      }
    }
    return mapped;
  }

  List<FieldChange> _diff(FormStateSnapshot before, FormStateSnapshot after) {
    final keys = {...before.values.keys, ...after.values.keys}.toList()..sort();
    return [
      for (final fieldId in keys)
        if (before.values[fieldId] != after.values[fieldId])
          FieldChange(
              fieldId: fieldId,
              previousValue: before.values[fieldId],
              value: after.values[fieldId],
              type: !after.values.containsKey(fieldId)
                  ? FieldChangeType.cleared
                  : !before.values.containsKey(fieldId)
                      ? FieldChangeType.set
                      : FieldChangeType.changed)
    ];
  }

  void _observe(ExternalStoreSnapshot<TState> update) {
    if (_disposed) return;
    _updates.add(update);
    _drainUpdates();
  }

  void _drainUpdates() {
    if (_disposed || _processingUpdates || _emitting) return;
    _processingUpdates = true;
    try {
      while (_updates.isNotEmpty && !_disposed) {
        _accept(_updates.removeFirst());
      }
    } finally {
      _processingUpdates = false;
    }
  }

  void _accept(ExternalStoreSnapshot<TState> update) {
    if (update.version <= _sourceVersion) {
      return; // old receipts and echoed notifications
    }
    _initialize();
    final before = _snapshot;
    late final FormStateSnapshot mapped;
    try {
      mapped = _project(update.state, before.revision);
    } catch (error) {
      _sourceVersion = update.version;
      _mappingFailed = true;
      _error(BridgeErrorCode.mappingFailure,
          'Authoritative state could not be mapped', error);
      return;
    }
    _sourceVersion = update.version;
    _mappingFailed = false;
    final changes = _diff(before, mapped);
    final semanticChange =
        changes.isNotEmpty || mapped.lifecycle != before.lifecycle;
    _snapshot = FormStateSnapshot(
        formId: form.id,
        revision: before.revision + (semanticChange ? 1 : 0),
        values: mapped.values,
        activeFieldId: mapped.activeFieldId,
        lifecycle: mapped.lifecycle);
    final pending = _pending;
    final correlated = pending != null &&
        update.operationId == pending.context.operationId &&
        update.version > pending.sourceVersion &&
        _matches(pending, _snapshot);
    final context = correlated ? pending.context : null;
    if (correlated) {
      pending.acknowledged = _snapshot;
      if (!pending.acknowledgement.isCompleted) {
        pending.acknowledgement.complete(ExternalWriteCommitted(update));
      }
    }
    if (!correlated &&
        (semanticChange || before.activeFieldId != mapped.activeFieldId)) {
      _externalGeneration++;
    }
    final origin = context == null
        ? ChangeOrigin.external
        : ChangeOrigin.values.byName(context.origin.name);
    if (semanticChange) {
      _emit(StateChanged(
          bridgeId: id,
          timestamp: _now(),
          previousRevision: before.revision,
          revision: _snapshot.revision,
          changes: changes,
          origin: origin,
          interactionId: context?.interactionId,
          operationId: context?.operationId,
          proposalId: context?.proposalId));
    }
    if (before.activeFieldId != mapped.activeFieldId) {
      _emit(ActiveFieldChanged(
          bridgeId: id,
          timestamp: _now(),
          previousFieldId: before.activeFieldId,
          fieldId: mapped.activeFieldId,
          origin: origin,
          interactionId: context?.interactionId,
          operationId: context?.operationId));
    }
  }

  bool _matches(_PendingWrite<TState> pending, FormStateSnapshot state) =>
      pending.fields.every(
          (field) => state.values[field] == pending.expected.values[field]) &&
      (!pending.navigation ||
          state.activeFieldId == pending.expected.activeFieldId);
  FormStateSnapshot _candidate(FormStateSnapshot base,
          Map<FieldId, FormValue> values, FieldId? active) =>
      FormStateSnapshot(
          formId: form.id,
          revision: base.revision,
          values: values,
          activeFieldId: active,
          lifecycle: base.lifecycle);
  ActionRejected _reject(FormAction action, ActionRejectionCode code,
          {Map<String, Object?> details = const {}}) =>
      ActionRejected(
          action: action,
          rejection: ActionRejection(code: code, details: details),
          snapshot: _snapshot);
  ActionNoOp _noop(
          FormAction action, NoOpReason reason, FormStateSnapshot state) =>
      ActionNoOp(
          action: action,
          revision: state.revision,
          snapshot: state,
          reason: reason);
  ActionRejectionCode? _guard(ApplyContext context) {
    if (_disposed) return ActionRejectionCode.disposed;
    if (_mappingFailed || _sourceFailed) {
      return ActionRejectionCode.capabilityUnavailable;
    }
    if (context.expectedRevision != _snapshot.revision) {
      return ActionRejectionCode.staleRevision;
    }
    return null;
  }

  ActionResult _plan(FormAction action, FormStateSnapshot state) {
    if (action is FormMutationAction) {
      if (!capabilities.writable || state.lifecycle != FormLifecycle.active) {
        return _reject(action, ActionRejectionCode.readOnly);
      }
      final field = _fields[action.fieldId];
      if (field == null) {
        return _reject(action, ActionRejectionCode.unknownField);
      }
      final issues = validateFieldAction(field, action);
      if (issues.isNotEmpty) {
        return _reject(
            action,
            issues.any((i) =>
                    i.code == 'value.type_mismatch' ||
                    i.code == 'value.option_unknown')
                ? ActionRejectionCode.invalidValue
                : ActionRejectionCode.validationFailed,
            details: {'issues': issues.map((i) => i.toJson()).toList()});
      }
      final values = Map<FieldId, FormValue>.of(state.values);
      if (action is SetValueAction) {
        if (values[action.fieldId] == action.value) {
          return _noop(action, NoOpReason.valueUnchanged, state);
        }
        values[action.fieldId] = action.value;
      } else {
        if (!values.containsKey(action.fieldId)) {
          return _noop(action, NoOpReason.alreadyClear, state);
        }
        values.remove(action.fieldId);
      }
      return ActionApplied(
          action: action,
          previousRevision: state.revision,
          revision: state.revision,
          snapshot: _candidate(state, values, state.activeFieldId));
    }
    if (action is NavigateAction) {
      if (!capabilities.supportsNavigation ||
          !capabilities.supportsActiveField) {
        return _reject(action, ActionRejectionCode.capabilityUnavailable);
      }
      FieldId? active;
      switch (action.target) {
        case FieldNavigationTarget(:final fieldId):
          if (!_fields.containsKey(fieldId)) {
            return _reject(action, ActionRejectionCode.unknownField);
          }
          active = fieldId;
        case NextNavigationTarget():
          final index =
              form.fields.indexWhere((f) => f.id == state.activeFieldId);
          active = form.fields.isEmpty
              ? null
              : form.fields[(index + 1).clamp(0, form.fields.length - 1)].id;
        case PreviousNavigationTarget():
          final index =
              form.fields.indexWhere((f) => f.id == state.activeFieldId);
          active = form.fields.isEmpty
              ? null
              : form.fields[(index - 1).clamp(0, form.fields.length - 1)].id;
      }
      if (active == state.activeFieldId) {
        return _noop(action, NoOpReason.alreadyAtTarget, state);
      }
      return ActionApplied(
          action: action,
          previousRevision: state.revision,
          revision: state.revision,
          snapshot: _candidate(state, state.values, active));
    }
    return _reject(action, ActionRejectionCode.unsupportedAction);
  }

  void _completed(ActionResult result, ApplyContext context) {
    if (!_disposed) {
      _emit(ActionCompleted(
          bridgeId: id,
          timestamp: _now(),
          operationId: context.operationId,
          interactionId: context.interactionId,
          proposalId: context.proposalId,
          result: result));
    }
  }

  @override
  Future<ActionResult> apply(FormAction action,
          {required ApplyContext context}) =>
      _enqueue(() async {
        final guard = _guard(context);
        final result = guard == null
            ? await _execute(action, context)
            : _reject(action, guard);
        _completed(result, context);
        return result;
      });
  Future<ActionResult> _execute(FormAction action, ApplyContext context) async {
    final planned = _plan(action, _snapshot);
    if (planned is! ActionApplied) return planned;
    final outcome = await _write([planned], context, atomic: false);
    if (outcome.code != null) {
      return _reject(action, outcome.code!, details: outcome.details);
    }
    final acknowledged = outcome.snapshot!;
    return ActionApplied(
        action: action,
        previousRevision: outcome.previousRevision,
        revision: acknowledged.revision,
        snapshot: acknowledged);
  }

  Future<_WriteOutcome> _write(List<ActionApplied> plans, ApplyContext context,
      {required bool atomic}) async {
    final before = _snapshot;
    final sourceVersion = _sourceVersion;
    late final List<TMutation> mutations;
    try {
      mutations = [
        for (final plan in plans) mapMutation(plan.action, plan.snapshot)
      ];
    } catch (error) {
      _error(BridgeErrorCode.mappingFailure,
          'Canonical action could not be mapped', error,
          context: context);
      return _WriteOutcome.rejected(before.revision,
          ActionRejectionCode.internalError, 'bridge.mutation_mapping_failed');
    }
    // A mapper must be pure; any source change during preparation still rejects.
    if (_sourceVersion != sourceVersion || _disposed) {
      return _WriteOutcome.rejected(
          before.revision,
          _disposed
              ? ActionRejectionCode.disposed
              : ActionRejectionCode.staleRevision,
          'bridge.source_changed');
    }
    final pending = _PendingWrite<TState>(
        context: context,
        sourceVersion: sourceVersion,
        expected: plans.last.snapshot,
        fields: plans
            .map((p) => p.action)
            .whereType<FormMutationAction>()
            .map((a) => a.fieldId)
            .toSet(),
        navigation: plans.any((p) => p.action is NavigateAction));
    _pending = pending;
    try {
      final receipt = source
          .compareAndApply(List<TMutation>.unmodifiable(mutations),
              expectedSourceVersion: sourceVersion,
              operationId: context.operationId,
              atomic: atomic)
          .then((result) {
        // This continuation also reconciles a late receipt after timeout. It
        // becomes an external change once no operation is pending.
        _observe(result.snapshot);
        return result;
      });
      final result = await Future.any<ExternalWriteResult<TState>?>([
        receipt,
        pending.acknowledgement.future,
        pending.cancelled.future
      ]).timeout(acknowledgementTimeout);
      if (_disposed || result == null) {
        return _WriteOutcome.rejected(
            before.revision, ActionRejectionCode.disposed, 'bridge.disposed');
      }
      if (result is ExternalWriteConflict<TState>) {
        return _WriteOutcome.rejected(
            before.revision,
            ActionRejectionCode.staleRevision,
            'bridge.source_version_conflict');
      }
      if (_mappingFailed) {
        return _WriteOutcome.rejected(
            before.revision,
            ActionRejectionCode.internalError,
            'bridge.snapshot_mapping_failed');
      }
      final acknowledged = pending.acknowledged;
      if (acknowledged == null || !_matches(pending, _snapshot)) {
        return _WriteOutcome.rejected(before.revision,
            ActionRejectionCode.conflict, 'bridge.authoritative_overwrite');
      }
      return _WriteOutcome.applied(before.revision, acknowledged);
    } on TimeoutException catch (error) {
      _error(BridgeErrorCode.operationFailure,
          'Authoritative acknowledgement timed out', error,
          context: context);
      return _WriteOutcome.rejected(before.revision,
          ActionRejectionCode.conflict, 'bridge.acknowledgement_timeout');
    } catch (error) {
      if (!_disposed) {
        _error(BridgeErrorCode.externalStoreFailure,
            'External store write failed', error,
            context: context);
      }
      return _WriteOutcome.rejected(
          before.revision,
          _disposed
              ? ActionRejectionCode.disposed
              : ActionRejectionCode.internalError,
          'bridge.external_store_failure');
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  @override
  Future<BatchActionResult> applyBatch(List<FormAction> actions,
      {required ApplyContext context,
      BatchApplyMode mode = BatchApplyMode.bestEffort}) {
    final copied = List<FormAction>.unmodifiable(actions);
    return _enqueue(() => _batch(copied, context, mode));
  }

  Future<BatchActionResult> _batch(List<FormAction> actions,
      ApplyContext context, BatchApplyMode mode) async {
    final before = _snapshot;
    final guard = _guard(context);
    final rejection = guard == ActionRejectionCode.disposed
        ? BatchRejectionCode.disposed
        : guard == ActionRejectionCode.staleRevision
            ? BatchRejectionCode.staleRevision
            : guard != null
                ? BatchRejectionCode.conflict
                : !capabilities.supportsBatch
                    ? BatchRejectionCode.batchUnsupported
                    : mode == BatchApplyMode.atomic &&
                            !capabilities.supportsAtomicBatch
                        ? BatchRejectionCode.atomicBatchUnsupported
                        : null;
    final results = <ActionResult>[];
    BatchRejection? batchRejection;
    if (rejection != null) {
      batchRejection = BatchRejection(code: rejection);
    } else if (mode == BatchApplyMode.bestEffort) {
      var expected = context.expectedRevision;
      final generation = _externalGeneration;
      for (final action in actions) {
        final internalContext = ApplyContext(
            expectedRevision: expected,
            interactionId: context.interactionId,
            operationId: context.operationId,
            proposalId: context.proposalId,
            origin: context.origin);
        final code = _guard(internalContext);
        final result = code != null
            ? _reject(action, code)
            : _externalGeneration != generation
                ? _reject(action, ActionRejectionCode.staleRevision)
                : await _execute(action, internalContext);
        results.add(result);
        if (result is ActionApplied) expected = result.revision;
        _completed(result, context);
      }
    } else {
      var candidate = before;
      final plans = <ActionResult>[];
      for (final action in actions) {
        final plan = _plan(action, candidate);
        plans.add(plan);
        if (plan is ActionApplied) candidate = plan.snapshot;
      }
      if (plans.any((p) => p is ActionRejected)) {
        results.addAll([
          for (final plan in plans)
            plan is ActionRejected
                ? plan
                : _reject(plan.action, ActionRejectionCode.atomicBatchAborted)
        ]);
      } else if (_diff(before, candidate).isEmpty &&
          before.activeFieldId == candidate.activeFieldId) {
        results.addAll([
          for (final plan in plans)
            _noop(
                plan.action,
                plan is ActionNoOp
                    ? plan.reason
                    : plan.action is NavigateAction
                        ? NoOpReason.alreadyAtTarget
                        : plan.action is ClearValueAction
                            ? NoOpReason.alreadyClear
                            : NoOpReason.valueUnchanged,
                before)
        ]);
      } else {
        final applied = plans.whereType<ActionApplied>().toList();
        final outcome = await _write(applied, context, atomic: true);
        if (outcome.code != null) {
          results.addAll([
            for (final plan in plans)
              _reject(plan.action, outcome.code!, details: outcome.details)
          ]);
        } else {
          final acknowledged = outcome.snapshot!;
          results.addAll([
            for (final plan in plans)
              plan is ActionNoOp
                  ? _noop(plan.action, plan.reason, acknowledged)
                  : ActionApplied(
                      action: plan.action,
                      previousRevision: before.revision,
                      revision: acknowledged.revision,
                      snapshot: acknowledged)
          ]);
        }
      }
      for (final result in results) {
        _completed(result, context);
      }
    }
    final applied = results.whereType<ActionApplied>().length;
    final rejected = results.whereType<ActionRejected>().length;
    final status = batchRejection != null
        ? BatchStatus.rejected
        : rejected > 0
            ? (applied > 0
                ? BatchStatus.partiallyApplied
                : BatchStatus.rejected)
            : applied > 0
                ? BatchStatus.applied
                : BatchStatus.noOp;
    final result = BatchActionResult(
        mode: mode,
        baseRevision: before.revision,
        finalRevision: _snapshot.revision,
        status: status,
        results: results,
        snapshot: _snapshot,
        rejection: batchRejection);
    if (!_disposed) {
      _emit(BatchCompleted(
          bridgeId: id,
          timestamp: _now(),
          operationId: context.operationId,
          interactionId: context.interactionId,
          proposalId: context.proposalId,
          result: result));
    }
    return result;
  }

  Future<ActionResult> _unavailableHistory(ApplyContext context) =>
      _enqueue(() {
        final action = NavigateAction(
            target: _snapshot.activeFieldId == null
                ? const NextNavigationTarget()
                : FieldNavigationTarget(fieldId: _snapshot.activeFieldId!));
        final result = _reject(action,
            _guard(context) ?? ActionRejectionCode.capabilityUnavailable);
        _completed(result, context);
        return result;
      });
  @override
  Future<ActionResult> undo({required ApplyContext context}) =>
      _unavailableHistory(context);
  @override
  Future<ActionResult> redo({required ApplyContext context}) =>
      _unavailableHistory(context);
  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    final pending = _pending;
    if (pending != null && !pending.cancelled.isCompleted) {
      pending.cancelled.complete(null);
    }
    await _subscription.cancel();
    _updates.clear();
    await _tail;
    _emit(BridgeDisposed(bridgeId: id, timestamp: _now()));
    await _events.close();
  }
}

final class _PendingWrite<TState> {
  final ApplyContext context;
  final int sourceVersion;
  final FormStateSnapshot expected;
  final Set<FieldId> fields;
  final bool navigation;
  final Completer<ExternalWriteResult<TState>?> cancelled = Completer();
  final Completer<ExternalWriteResult<TState>?> acknowledgement = Completer();
  FormStateSnapshot? acknowledged;
  _PendingWrite(
      {required this.context,
      required this.sourceVersion,
      required this.expected,
      required this.fields,
      required this.navigation});
}

final class _WriteOutcome {
  final Revision previousRevision;
  final FormStateSnapshot? snapshot;
  final ActionRejectionCode? code;
  final Map<String, Object?> details;
  const _WriteOutcome.applied(this.previousRevision, this.snapshot)
      : code = null,
        details = const {};
  _WriteOutcome.rejected(this.previousRevision, this.code, String issue)
      : snapshot = null,
        details = {'code': issue};
}

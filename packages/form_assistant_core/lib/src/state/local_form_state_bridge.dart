import 'dart:async';

import '../contracts/bridge_events.dart';
import '../contracts/form_action.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_state.dart';
import '../contracts/form_state_bridge.dart';
import '../contracts/form_value.dart';
import '../validation/form_ir_validator.dart';

/// Owns canonical state. Every operation is serialized with its revision check.
/// State events are synchronous and emitted only after publishing the snapshot.
final class LocalFormStateBridge implements FormStateBridge {
  @override
  final String id;
  @override
  String get version => '0.1.0';
  @override
  final FormStateBridgeCapabilities capabilities;
  final FormIR form;
  late final Map<FieldId, FormField> _fields;
  late FormStateSnapshot _snapshot;
  late final StreamController<FormStateBridgeEvent> _events;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;
  bool _initialized = false;
  Future<void>? _disposal;
  final List<_HistoryEntry> _undo = [];
  final List<_HistoryEntry> _redo = [];

  LocalFormStateBridge({
    required this.form,
    this.id = 'local',
    Map<FieldId, FormValue> initialValues = const {},
    FieldId? activeFieldId,
    FormLifecycle lifecycle = FormLifecycle.active,
    this.capabilities = const FormStateBridgeCapabilities(
        writable: true,
        supportsBatch: true,
        supportsAtomicBatch: true,
        supportsUndo: true,
        supportsRedo: true,
        supportsExternalChanges: false,
        supportsActiveField: true,
        supportsNavigation: true),
  }) {
    if (capabilities.supportsExternalChanges ||
        (capabilities.supportsAtomicBatch && !capabilities.supportsBatch) ||
        (capabilities.supportsNavigation &&
            !capabilities.supportsActiveField)) {
      throw ArgumentError('Inconsistent local bridge capabilities');
    }
    _fields = {for (final field in form.fields) field.id: field};
    if (_fields.length != form.fields.length ||
        _fields.keys.any((id) => id.isEmpty)) {
      throw ArgumentError('Form field IDs must be unique and nonempty');
    }
    for (final field in form.fields) {
      final constraints = field.constraints;
      if (constraints?.pattern case final String pattern) {
        RegExp(pattern);
      }
      if (constraints != null &&
          ((constraints.min != null &&
                  constraints.max != null &&
                  constraints.min! > constraints.max!) ||
              (constraints.minLength != null && constraints.minLength! < 0) ||
              (constraints.maxLength != null && constraints.maxLength! < 0) ||
              (constraints.minLength != null &&
                  constraints.maxLength != null &&
                  constraints.minLength! > constraints.maxLength!))) {
        throw ArgumentError('Invalid constraints for ${field.id}');
      }
      final options = field.options;
      if (options != null &&
          (options.any((o) => o.id.isEmpty) ||
              options.map((o) => o.id).toSet().length != options.length)) {
        throw ArgumentError('Option IDs must be unique and nonempty');
      }
    }
    for (final entry in initialValues.entries) {
      final field = _fields[entry.key];
      if (field == null ||
          validateFieldAction(
                  field, SetValueAction(fieldId: entry.key, value: entry.value))
              .isNotEmpty) {
        throw ArgumentError('Invalid initial value for ${entry.key}');
      }
    }
    if (activeFieldId != null &&
        (!capabilities.supportsActiveField ||
            !_fields.containsKey(activeFieldId))) {
      throw ArgumentError('Invalid initial active field');
    }
    _snapshot = FormStateSnapshot(
        formId: form.id,
        revision: 0,
        values: initialValues,
        activeFieldId: activeFieldId,
        lifecycle: lifecycle);
    _events = StreamController<FormStateBridgeEvent>.broadcast(
        sync: true,
        onListen: () {
          if (!_initialized && !_disposed) {
            unawaited(_enqueue<void>(() {}));
          }
        });
  }

  @override
  FormStateSnapshot get snapshot => _snapshot;
  @override
  Stream<FormStateBridgeEvent> get events => _events.stream;
  DateTime _now() => DateTime.now().toUtc();
  void _emit(FormStateBridgeEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<T> _enqueue<T>(FutureOr<T> Function() work) {
    final result = _tail.then<T>((_) {
      if (!_initialized && !_disposed && _events.hasListener) {
        _initialized = true;
        _emit(BridgeInitialized(
            bridgeId: id, timestamp: _now(), snapshot: snapshot));
      }
      return work();
    });
    _tail =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  ChangeOrigin _origin(ApplyContext context) =>
      ChangeOrigin.values.byName(context.origin.name);
  FormStateSnapshot _state(Map<FieldId, FormValue> values, FieldId? active,
          {Revision? revision}) =>
      FormStateSnapshot(
          formId: form.id,
          revision: revision ?? snapshot.revision,
          values: values,
          activeFieldId: active,
          lifecycle: snapshot.lifecycle);
  ActionRejected _reject(FormAction action, ActionRejectionCode code,
          {FormStateSnapshot? state,
          Map<String, Object?> details = const {}}) =>
      ActionRejected(
          action: action,
          rejection: ActionRejection(code: code, details: details),
          snapshot: state ?? snapshot);
  ActionNoOp _noOp(
          FormAction action, NoOpReason reason, FormStateSnapshot state) =>
      ActionNoOp(
          action: action,
          reason: reason,
          revision: state.revision,
          snapshot: state);
  ActionRejectionCode? _guard(ApplyContext context) {
    if (_disposed) return ActionRejectionCode.disposed;
    if (context.expectedRevision != snapshot.revision) {
      return ActionRejectionCode.staleRevision;
    }
    return null;
  }

  bool get _writable =>
      capabilities.writable && snapshot.lifecycle == FormLifecycle.active;

  // Pure planning: candidate snapshots never become authoritative until commit.
  ActionResult _plan(FormAction action, FormStateSnapshot state) {
    if (action is FormMutationAction) {
      if (!_writable) {
        return _reject(action, ActionRejectionCode.readOnly, state: state);
      }
      final field = _fields[action.fieldId];
      if (field == null) {
        return _reject(action, ActionRejectionCode.unknownField, state: state);
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
            state: state,
            details: {'issues': issues.map((i) => i.toJson()).toList()});
      }
      final values = Map<FieldId, FormValue>.of(state.values);
      if (action is SetValueAction) {
        if (values[action.fieldId] == action.value) {
          return _noOp(action, NoOpReason.valueUnchanged, state);
        }
        values[action.fieldId] = action.value;
      } else {
        if (!values.containsKey(action.fieldId)) {
          return _noOp(action, NoOpReason.alreadyClear, state);
        }
        values.remove(action.fieldId);
      }
      return ActionApplied(
          action: action,
          previousRevision: state.revision,
          revision: state.revision,
          snapshot: _state(values, state.activeFieldId));
    }
    if (action is NavigateAction) {
      if (!capabilities.supportsNavigation ||
          !capabilities.supportsActiveField) {
        return _reject(action, ActionRejectionCode.capabilityUnavailable,
            state: state);
      }
      FieldId? target;
      switch (action.target) {
        case FieldNavigationTarget(:final fieldId):
          if (!_fields.containsKey(fieldId)) {
            return _reject(action, ActionRejectionCode.unknownField,
                state: state);
          }
          target = fieldId;
        case NextNavigationTarget():
          final index =
              form.fields.indexWhere((f) => f.id == state.activeFieldId);
          target = form.fields.isEmpty
              ? null
              : form.fields[(index + 1).clamp(0, form.fields.length - 1)].id;
        case PreviousNavigationTarget():
          final index =
              form.fields.indexWhere((f) => f.id == state.activeFieldId);
          target = form.fields.isEmpty
              ? null
              : form.fields[(index - 1).clamp(0, form.fields.length - 1)].id;
      }
      if (target == state.activeFieldId) {
        return _noOp(action, NoOpReason.alreadyAtTarget, state);
      }
      return ActionApplied(
          action: action,
          previousRevision: state.revision,
          revision: state.revision,
          snapshot: _state(state.values, target));
    }
    return _reject(action, ActionRejectionCode.unsupportedAction, state: state);
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

  FormStateSnapshot _commit(FormStateSnapshot candidate, ApplyContext context,
      {bool recordHistory = true, ChangeOrigin? origin}) {
    final before = snapshot;
    final changes = _diff(before, candidate);
    _snapshot = _state(candidate.values, candidate.activeFieldId,
        revision: before.revision + (changes.isEmpty ? 0 : 1));
    if (changes.isNotEmpty && recordHistory) {
      _undo.add(_HistoryEntry(before.values, snapshot.values));
      _redo.clear();
    }
    if (changes.isNotEmpty) {
      _emit(StateChanged(
          bridgeId: id,
          timestamp: _now(),
          previousRevision: before.revision,
          revision: snapshot.revision,
          changes: changes,
          origin: origin ?? _origin(context),
          interactionId: context.interactionId,
          operationId: context.operationId,
          proposalId: context.proposalId));
    }
    if (before.activeFieldId != snapshot.activeFieldId) {
      _emit(ActiveFieldChanged(
          bridgeId: id,
          timestamp: _now(),
          previousFieldId: before.activeFieldId,
          fieldId: snapshot.activeFieldId,
          origin: origin ?? _origin(context),
          interactionId: context.interactionId,
          operationId: context.operationId));
    }
    return snapshot;
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

  ActionResult _execute(FormAction action, ApplyContext context) {
    final planned = _plan(action, snapshot);
    if (planned is! ActionApplied) return planned;
    final before = snapshot.revision;
    final committed = _commit(planned.snapshot, context);
    return ActionApplied(
        action: action,
        previousRevision: before,
        revision: committed.revision,
        snapshot: committed);
  }

  @override
  Future<ActionResult> apply(FormAction action,
          {required ApplyContext context}) =>
      _enqueue(() {
        final guard = _guard(context);
        final result =
            guard == null ? _execute(action, context) : _reject(action, guard);
        _completed(result, context);
        return result;
      });

  @override
  Future<BatchActionResult> applyBatch(List<FormAction> actions,
      {required ApplyContext context,
      BatchApplyMode mode = BatchApplyMode.bestEffort}) {
    final copied = List<FormAction>.unmodifiable(actions);
    return _enqueue(() => _batch(copied, context, mode));
  }

  BatchActionResult _batch(
      List<FormAction> actions, ApplyContext context, BatchApplyMode mode) {
    final base = snapshot;
    final guard = _guard(context);
    final rejection = guard == ActionRejectionCode.disposed
        ? BatchRejectionCode.disposed
        : guard == ActionRejectionCode.staleRevision
            ? BatchRejectionCode.staleRevision
            : !capabilities.supportsBatch
                ? BatchRejectionCode.batchUnsupported
                : mode == BatchApplyMode.atomic &&
                        !capabilities.supportsAtomicBatch
                    ? BatchRejectionCode.atomicBatchUnsupported
                    : null;
    late final List<ActionResult> results;
    BatchRejection? batchRejection;
    if (rejection != null) {
      batchRejection = BatchRejection(code: rejection);
      results = [];
    } else if (mode == BatchApplyMode.bestEffort) {
      results = [];
      for (final action in actions) {
        final result = _execute(action, context);
        results.add(result);
        _completed(result, context);
      }
    } else {
      final plans = <ActionResult>[];
      var candidate = base;
      for (final action in actions) {
        final plan = _plan(action, candidate);
        plans.add(plan);
        if (plan is ActionApplied) candidate = plan.snapshot;
      }
      if (plans.any((p) => p is ActionRejected)) {
        results = [
          for (final plan in plans)
            plan is ActionRejected
                ? _reject(plan.action, plan.rejection.code,
                    details: plan.rejection.details)
                : _reject(plan.action, ActionRejectionCode.atomicBatchAborted)
        ];
      } else {
        final semanticChange = _diff(base, candidate).isNotEmpty;
        final committed = _commit(candidate, context);
        results = [
          for (final plan in plans)
            if (plan is ActionApplied &&
                (semanticChange || plan.action is NavigateAction))
              ActionApplied(
                  action: plan.action,
                  previousRevision: base.revision,
                  revision: committed.revision,
                  snapshot: committed)
            else if (plan is ActionNoOp)
              _noOp(plan.action, plan.reason, committed)
            else
              _noOp(
                  plan.action,
                  plan.action is ClearValueAction
                      ? NoOpReason.alreadyClear
                      : NoOpReason.valueUnchanged,
                  committed)
        ];
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
        baseRevision: base.revision,
        finalRevision: snapshot.revision,
        status: status,
        results: results,
        snapshot: snapshot,
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

  @override
  Future<ActionResult> undo({required ApplyContext context}) =>
      _enqueue(() => _restore(context, redo: false));
  @override
  Future<ActionResult> redo({required ApplyContext context}) =>
      _enqueue(() => _restore(context, redo: true));
  ActionResult _restore(ApplyContext context, {required bool redo}) {
    final source = redo ? _redo : _undo;
    final entry = source.isEmpty ? null : source.last;
    final target = entry == null
        ? snapshot.values
        : redo
            ? entry.after
            : entry.before;
    final candidate = _state(target, snapshot.activeFieldId);
    final changes = _diff(snapshot, candidate);
    // Result.action names the first restored field; snapshot/events describe all.
    final FormAction action = changes.isEmpty
        ? NavigateAction(
            target: snapshot.activeFieldId == null
                ? const NextNavigationTarget()
                : FieldNavigationTarget(fieldId: snapshot.activeFieldId!))
        : changes.first.value == null
            ? ClearValueAction(fieldId: changes.first.fieldId)
            : SetValueAction(
                fieldId: changes.first.fieldId, value: changes.first.value!);
    final guard = _guard(context);
    late final ActionResult result;
    if (guard != null) {
      result = _reject(action, guard);
    } else if (!_writable) {
      result = _reject(action, ActionRejectionCode.readOnly);
    } else if (!(redo
            ? capabilities.supportsRedo
            : capabilities.supportsUndo) ||
        entry == null) {
      result = _reject(action, ActionRejectionCode.capabilityUnavailable);
    } else {
      final before = snapshot.revision;
      source.removeLast();
      (redo ? _undo : _redo).add(entry);
      final committed = _commit(candidate, context,
          recordHistory: false,
          origin: redo ? ChangeOrigin.redo : ChangeOrigin.undo);
      result = ActionApplied(
          action: action,
          previousRevision: before,
          revision: committed.revision,
          snapshot: committed);
    }
    _completed(result, context);
    return result;
  }

  @override
  Future<void> dispose() => _disposal ??= _enqueue<void>(() async {
        _disposed = true;
        _undo.clear();
        _redo.clear();
        _emit(BridgeDisposed(bridgeId: id, timestamp: _now()));
        await _events.close();
      });
}

final class _HistoryEntry {
  final Map<FieldId, FormValue> before;
  final Map<FieldId, FormValue> after;
  const _HistoryEntry(this.before, this.after);
}

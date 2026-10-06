import 'canonical_json.dart';
import 'form_value.dart';
import 'form_action.dart';
import 'form_state.dart';
import 'form_state_bridge.dart';
import 'bridge_events.dart';

String _enumName(Enum value) => value.name
    .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
T _enum<T extends Enum>(List<T> values, Object? input) =>
    values.firstWhere((v) => _enumName(v) == requireType<String>(input),
        orElse: () => throw const FormatException('Unknown enum value'));
void _version(Map<String, Object?> j) {
  if (!RegExp(r'^1\.\d+$').hasMatch(requiredString(j, 'specVersion'))) {
    throw const FormatException('Unsupported specVersion');
  }
}

int _revision(Object? value) {
  final revision = requireType<int>(value);
  if (revision < 0) throw const FormatException('Negative revision');
  return revision;
}

DateTime _timestamp(Object? value) {
  final text = requireType<String>(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:\d{3})?Z$')
      .hasMatch(text)) {
    throw const FormatException('Expected UTC ISO timestamp');
  }
  final date = DateTime.parse(text);
  if (date.toIso8601String() != text) {
    throw const FormatException('Invalid timestamp');
  }
  return date;
}

abstract final class FormStateSnapshotCodec {
  static FormStateSnapshot decode(Object? input) {
    final j = jsonObject(input);
    _version(j);
    return FormStateSnapshot(
      formId: requireType<String>(j['formId']),
      revision: _revision(j['revision']),
      values: jsonObject(j['values'])
          .map((k, v) => MapEntry(k, FormValueCodec.decode(v))),
      activeFieldId: j.containsKey('activeFieldId')
          ? requireType<String>(j['activeFieldId'])
          : null,
      lifecycle: _enum(FormLifecycle.values, j['lifecycle']),
    );
  }

  static Map<String, Object?> encode(FormStateSnapshot value) => {
        'specVersion': protocolSpecVersion,
        'formId': value.formId,
        'revision': value.revision,
        'values':
            value.values.map((k, v) => MapEntry(k, FormValueCodec.encode(v))),
        if (value.activeFieldId != null) 'activeFieldId': value.activeFieldId!,
        'lifecycle': _enumName(value.lifecycle),
      };
}

abstract final class FormStateBridgeCapabilitiesCodec {
  static FormStateBridgeCapabilities decode(Object? input) {
    final j = jsonObject(input);
    return FormStateBridgeCapabilities(
      writable: requireType<bool>(j['writable']),
      supportsBatch: requireType<bool>(j['supportsBatch']),
      supportsAtomicBatch: requireType<bool>(j['supportsAtomicBatch']),
      supportsUndo: requireType<bool>(j['supportsUndo']),
      supportsRedo: requireType<bool>(j['supportsRedo']),
      supportsExternalChanges: requireType<bool>(j['supportsExternalChanges']),
      supportsActiveField: requireType<bool>(j['supportsActiveField']),
      supportsNavigation: requireType<bool>(j['supportsNavigation']),
    );
  }

  static Map<String, Object?> encode(FormStateBridgeCapabilities value) => {
        'writable': value.writable,
        'supportsBatch': value.supportsBatch,
        'supportsAtomicBatch': value.supportsAtomicBatch,
        'supportsUndo': value.supportsUndo,
        'supportsRedo': value.supportsRedo,
        'supportsExternalChanges': value.supportsExternalChanges,
        'supportsActiveField': value.supportsActiveField,
        'supportsNavigation': value.supportsNavigation,
      };
}

abstract final class ApplyContextCodec {
  static ApplyContext decode(Object? input) {
    final j = jsonObject(input);
    return ApplyContext(
      expectedRevision: _revision(j['expectedRevision']),
      interactionId: requireType<String>(j['interactionId']),
      operationId: requireType<String>(j['operationId']),
      proposalId: j.containsKey('proposalId')
          ? requireType<String>(j['proposalId'])
          : null,
      origin: _enum(ActionOrigin.values, j['origin']),
    );
  }

  static Map<String, Object?> encode(ApplyContext value) => {
        'expectedRevision': value.expectedRevision,
        'interactionId': value.interactionId,
        'operationId': value.operationId,
        if (value.proposalId != null) 'proposalId': value.proposalId!,
        'origin': _enumName(value.origin),
      };
}

abstract final class ActionAppliedCodec {
  static ActionApplied decode(Object? input) {
    final j = jsonObject(input);
    if (requiredString(j, 'type') != 'action_applied') {
      throw const FormatException('Wrong discriminator');
    }
    return ActionApplied(
      action: FormActionCodec.decode(j['action']),
      previousRevision: _revision(j['previousRevision']),
      revision: _revision(j['revision']),
      snapshot: FormStateSnapshotCodec.decode(j['snapshot']),
    );
  }

  static Map<String, Object?> encode(ActionApplied value) => {
        'type': 'action_applied',
        'action': FormActionCodec.encode(value.action),
        'previousRevision': value.previousRevision,
        'revision': value.revision,
        'snapshot': FormStateSnapshotCodec.encode(value.snapshot),
      };
}

abstract final class ActionNoOpCodec {
  static ActionNoOp decode(Object? input) {
    final j = jsonObject(input);
    if (requiredString(j, 'type') != 'action_no_op') {
      throw const FormatException('Wrong discriminator');
    }
    return ActionNoOp(
      action: FormActionCodec.decode(j['action']),
      revision: _revision(j['revision']),
      snapshot: FormStateSnapshotCodec.decode(j['snapshot']),
      reason: _enum(NoOpReason.values, j['reason']),
    );
  }

  static Map<String, Object?> encode(ActionNoOp value) => {
        'type': 'action_no_op',
        'action': FormActionCodec.encode(value.action),
        'revision': value.revision,
        'snapshot': FormStateSnapshotCodec.encode(value.snapshot),
        'reason': _enumName(value.reason),
      };
}

abstract final class ActionRejectionCodec {
  static ActionRejection decode(Object? input) {
    final j = jsonObject(input);
    return ActionRejection(
      code: _enum(ActionRejectionCode.values, j['code']),
      message:
          j.containsKey('message') ? requireType<String>(j['message']) : null,
      details: j.containsKey('details') ? jsonObject(j['details']) : const {},
    );
  }

  static Map<String, Object?> encode(ActionRejection value) => {
        'code': _enumName(value.code),
        if (value.message != null) 'message': value.message!,
        'details': value.details,
      };
}

abstract final class ActionRejectedCodec {
  static ActionRejected decode(Object? input) {
    final j = jsonObject(input);
    if (requiredString(j, 'type') != 'action_rejected') {
      throw const FormatException('Wrong discriminator');
    }
    return ActionRejected(
      action: FormActionCodec.decode(j['action']),
      rejection: ActionRejectionCodec.decode(j['rejection']),
      snapshot: FormStateSnapshotCodec.decode(j['snapshot']),
    );
  }

  static Map<String, Object?> encode(ActionRejected value) => {
        'type': 'action_rejected',
        'action': FormActionCodec.encode(value.action),
        'rejection': ActionRejectionCodec.encode(value.rejection),
        'snapshot': FormStateSnapshotCodec.encode(value.snapshot),
      };
}

abstract final class BatchRejectionCodec {
  static BatchRejection decode(Object? input) {
    final j = jsonObject(input);
    return BatchRejection(
      code: _enum(BatchRejectionCode.values, j['code']),
      message:
          j.containsKey('message') ? requireType<String>(j['message']) : null,
      details: j.containsKey('details') ? jsonObject(j['details']) : const {},
    );
  }

  static Map<String, Object?> encode(BatchRejection value) => {
        'code': _enumName(value.code),
        if (value.message != null) 'message': value.message!,
        'details': value.details,
      };
}

abstract final class BatchActionResultCodec {
  static BatchActionResult decode(Object? input) {
    final j = jsonObject(input);
    return BatchActionResult(
      mode: _enum(BatchApplyMode.values, j['mode']),
      baseRevision: _revision(j['baseRevision']),
      finalRevision: _revision(j['finalRevision']),
      status: _enum(BatchStatus.values, j['status']),
      results: requireType<List<Object?>>(j['results'])
          .map(ActionResultCodec.decode)
          .toList(),
      snapshot: FormStateSnapshotCodec.decode(j['snapshot']),
      rejection: j.containsKey('rejection')
          ? BatchRejectionCodec.decode(j['rejection'])
          : null,
    );
  }

  static Map<String, Object?> encode(BatchActionResult value) => {
        'mode': _enumName(value.mode),
        'baseRevision': value.baseRevision,
        'finalRevision': value.finalRevision,
        'status': _enumName(value.status),
        'results': value.results.map(ActionResultCodec.encode).toList(),
        'snapshot': FormStateSnapshotCodec.encode(value.snapshot),
        if (value.rejection != null)
          'rejection': BatchRejectionCodec.encode(value.rejection!),
      };
}

abstract final class BridgeInitializedCodec {
  static BridgeInitialized decode(Object? input) {
    final j = jsonObject(input);
    _version(j);
    if (requiredString(j, 'type') != 'bridge_initialized') {
      throw const FormatException('Wrong discriminator');
    }
    return BridgeInitialized(
      bridgeId: requireType<String>(j['bridgeId']),
      timestamp: _timestamp(j['timestamp']),
      snapshot: FormStateSnapshotCodec.decode(j['snapshot']),
    );
  }

  static Map<String, Object?> encode(BridgeInitialized value) => {
        'specVersion': protocolSpecVersion,
        'type': 'bridge_initialized',
        'bridgeId': value.bridgeId,
        'timestamp': value.timestamp.toUtc().toIso8601String(),
        'snapshot': FormStateSnapshotCodec.encode(value.snapshot),
      };
}

abstract final class FieldChangeCodec {
  static FieldChange decode(Object? input) {
    final j = jsonObject(input);
    return FieldChange(
      fieldId: requireType<String>(j['fieldId']),
      previousValue: j.containsKey('previousValue')
          ? FormValueCodec.decode(j['previousValue'])
          : null,
      value: j.containsKey('value') ? FormValueCodec.decode(j['value']) : null,
      type: _enum(FieldChangeType.values, j['type']),
    );
  }

  static Map<String, Object?> encode(FieldChange value) => {
        'fieldId': value.fieldId,
        if (value.previousValue != null)
          'previousValue': FormValueCodec.encode(value.previousValue!),
        if (value.value != null) 'value': FormValueCodec.encode(value.value!),
        'type': _enumName(value.type),
      };
}

abstract final class StateChangedCodec {
  static StateChanged decode(Object? input) {
    final j = jsonObject(input);
    _version(j);
    if (requiredString(j, 'type') != 'state_changed') {
      throw const FormatException('Wrong discriminator');
    }
    return StateChanged(
      bridgeId: requireType<String>(j['bridgeId']),
      timestamp: _timestamp(j['timestamp']),
      previousRevision: _revision(j['previousRevision']),
      revision: _revision(j['revision']),
      changes: requireType<List<Object?>>(j['changes'])
          .map(FieldChangeCodec.decode)
          .toList(),
      origin: _enum(ChangeOrigin.values, j['origin']),
      interactionId: j.containsKey('interactionId')
          ? requireType<String>(j['interactionId'])
          : null,
      operationId: j.containsKey('operationId')
          ? requireType<String>(j['operationId'])
          : null,
      proposalId: j.containsKey('proposalId')
          ? requireType<String>(j['proposalId'])
          : null,
    );
  }

  static Map<String, Object?> encode(StateChanged value) => {
        'specVersion': protocolSpecVersion,
        'type': 'state_changed',
        'bridgeId': value.bridgeId,
        'timestamp': value.timestamp.toUtc().toIso8601String(),
        'previousRevision': value.previousRevision,
        'revision': value.revision,
        'changes': value.changes.map(FieldChangeCodec.encode).toList(),
        'origin': _enumName(value.origin),
        if (value.interactionId != null) 'interactionId': value.interactionId!,
        if (value.operationId != null) 'operationId': value.operationId!,
        if (value.proposalId != null) 'proposalId': value.proposalId!,
      };
}

abstract final class ActiveFieldChangedCodec {
  static ActiveFieldChanged decode(Object? input) {
    final j = jsonObject(input);
    _version(j);
    if (requiredString(j, 'type') != 'active_field_changed') {
      throw const FormatException('Wrong discriminator');
    }
    return ActiveFieldChanged(
      bridgeId: requireType<String>(j['bridgeId']),
      timestamp: _timestamp(j['timestamp']),
      previousFieldId: j.containsKey('previousFieldId')
          ? requireType<String>(j['previousFieldId'])
          : null,
      fieldId:
          j.containsKey('fieldId') ? requireType<String>(j['fieldId']) : null,
      origin: _enum(ChangeOrigin.values, j['origin']),
      interactionId: j.containsKey('interactionId')
          ? requireType<String>(j['interactionId'])
          : null,
      operationId: j.containsKey('operationId')
          ? requireType<String>(j['operationId'])
          : null,
    );
  }

  static Map<String, Object?> encode(ActiveFieldChanged value) => {
        'specVersion': protocolSpecVersion,
        'type': 'active_field_changed',
        'bridgeId': value.bridgeId,
        'timestamp': value.timestamp.toUtc().toIso8601String(),
        if (value.previousFieldId != null)
          'previousFieldId': value.previousFieldId!,
        if (value.fieldId != null) 'fieldId': value.fieldId!,
        'origin': _enumName(value.origin),
        if (value.interactionId != null) 'interactionId': value.interactionId!,
        if (value.operationId != null) 'operationId': value.operationId!,
      };
}

abstract final class ActionCompletedCodec {
  static ActionCompleted decode(Object? input) {
    final j = jsonObject(input);
    _version(j);
    if (requiredString(j, 'type') != 'action_completed') {
      throw const FormatException('Wrong discriminator');
    }
    return ActionCompleted(
      bridgeId: requireType<String>(j['bridgeId']),
      timestamp: _timestamp(j['timestamp']),
      operationId: requireType<String>(j['operationId']),
      interactionId: requireType<String>(j['interactionId']),
      proposalId: j.containsKey('proposalId')
          ? requireType<String>(j['proposalId'])
          : null,
      result: ActionResultCodec.decode(j['result']),
    );
  }

  static Map<String, Object?> encode(ActionCompleted value) => {
        'specVersion': protocolSpecVersion,
        'type': 'action_completed',
        'bridgeId': value.bridgeId,
        'timestamp': value.timestamp.toUtc().toIso8601String(),
        'operationId': value.operationId,
        'interactionId': value.interactionId,
        if (value.proposalId != null) 'proposalId': value.proposalId!,
        'result': ActionResultCodec.encode(value.result),
      };
}

abstract final class BatchCompletedCodec {
  static BatchCompleted decode(Object? input) {
    final j = jsonObject(input);
    _version(j);
    if (requiredString(j, 'type') != 'batch_completed') {
      throw const FormatException('Wrong discriminator');
    }
    return BatchCompleted(
      bridgeId: requireType<String>(j['bridgeId']),
      timestamp: _timestamp(j['timestamp']),
      operationId: requireType<String>(j['operationId']),
      interactionId: requireType<String>(j['interactionId']),
      proposalId: j.containsKey('proposalId')
          ? requireType<String>(j['proposalId'])
          : null,
      result: BatchActionResultCodec.decode(j['result']),
    );
  }

  static Map<String, Object?> encode(BatchCompleted value) => {
        'specVersion': protocolSpecVersion,
        'type': 'batch_completed',
        'bridgeId': value.bridgeId,
        'timestamp': value.timestamp.toUtc().toIso8601String(),
        'operationId': value.operationId,
        'interactionId': value.interactionId,
        if (value.proposalId != null) 'proposalId': value.proposalId!,
        'result': BatchActionResultCodec.encode(value.result),
      };
}

abstract final class BridgeErrorCodec {
  static BridgeError decode(Object? input) {
    final j = jsonObject(input);
    _version(j);
    if (requiredString(j, 'type') != 'bridge_error') {
      throw const FormatException('Wrong discriminator');
    }
    return BridgeError(
      bridgeId: requireType<String>(j['bridgeId']),
      timestamp: _timestamp(j['timestamp']),
      code: _enum(BridgeErrorCode.values, j['code']),
      message: requireType<String>(j['message']),
      recoverable: requireType<bool>(j['recoverable']),
      interactionId: j.containsKey('interactionId')
          ? requireType<String>(j['interactionId'])
          : null,
      operationId: j.containsKey('operationId')
          ? requireType<String>(j['operationId'])
          : null,
    );
  }

  static Map<String, Object?> encode(BridgeError value) => {
        'specVersion': protocolSpecVersion,
        'type': 'bridge_error',
        'bridgeId': value.bridgeId,
        'timestamp': value.timestamp.toUtc().toIso8601String(),
        'code': _enumName(value.code),
        'message': value.message,
        'recoverable': value.recoverable,
        if (value.interactionId != null) 'interactionId': value.interactionId!,
        if (value.operationId != null) 'operationId': value.operationId!,
      };
}

abstract final class BridgeDisposedCodec {
  static BridgeDisposed decode(Object? input) {
    final j = jsonObject(input);
    _version(j);
    if (requiredString(j, 'type') != 'bridge_disposed') {
      throw const FormatException('Wrong discriminator');
    }
    return BridgeDisposed(
      bridgeId: requireType<String>(j['bridgeId']),
      timestamp: _timestamp(j['timestamp']),
    );
  }

  static Map<String, Object?> encode(BridgeDisposed value) => {
        'specVersion': protocolSpecVersion,
        'type': 'bridge_disposed',
        'bridgeId': value.bridgeId,
        'timestamp': value.timestamp.toUtc().toIso8601String(),
      };
}

abstract final class ActionResultCodec {
  static ActionResult decode(Object? input) {
    final j = jsonObject(input);
    return switch (requiredString(j, "type")) {
      'action_applied' => ActionAppliedCodec.decode(j),
      'action_no_op' => ActionNoOpCodec.decode(j),
      'action_rejected' => ActionRejectedCodec.decode(j),
      _ => throw const FormatException('Unknown discriminator'),
    };
  }

  static Map<String, Object?> encode(ActionResult value) => switch (value) {
        ActionApplied() => ActionAppliedCodec.encode(value),
        ActionNoOp() => ActionNoOpCodec.encode(value),
        ActionRejected() => ActionRejectedCodec.encode(value),
      };
}

abstract final class BridgeEventCodec {
  static FormStateBridgeEvent decode(Object? input) {
    final j = jsonObject(input);
    return switch (requiredString(j, "type")) {
      'bridge_initialized' => BridgeInitializedCodec.decode(j),
      'state_changed' => StateChangedCodec.decode(j),
      'active_field_changed' => ActiveFieldChangedCodec.decode(j),
      'action_completed' => ActionCompletedCodec.decode(j),
      'batch_completed' => BatchCompletedCodec.decode(j),
      'bridge_error' => BridgeErrorCodec.decode(j),
      'bridge_disposed' => BridgeDisposedCodec.decode(j),
      _ => throw const FormatException('Unknown discriminator'),
    };
  }

  static Map<String, Object?> encode(FormStateBridgeEvent value) =>
      switch (value) {
        BridgeInitialized() => BridgeInitializedCodec.encode(value),
        StateChanged() => StateChangedCodec.encode(value),
        ActiveFieldChanged() => ActiveFieldChangedCodec.encode(value),
        ActionCompleted() => ActionCompletedCodec.encode(value),
        BatchCompleted() => BatchCompletedCodec.encode(value),
        BridgeError() => BridgeErrorCodec.encode(value),
        BridgeDisposed() => BridgeDisposedCodec.encode(value),
      };
}

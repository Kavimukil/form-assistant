import 'bridge_codec.dart';
import 'structural_contract.dart';
import 'form_value.dart';
import 'form_state.dart';
import 'form_state_bridge.dart';

sealed class FormStateBridgeEvent with StructuralContract {
  final String bridgeId;
  final DateTime timestamp;
  const FormStateBridgeEvent({required this.bridgeId, required this.timestamp});
}

final class BridgeInitialized extends FormStateBridgeEvent {
  final FormStateSnapshot snapshot;
  const BridgeInitialized({
    required super.bridgeId,
    required super.timestamp,
    required this.snapshot,
  });
  @override
  Map<String, Object?> toJson() => BridgeInitializedCodec.encode(this);
}

enum ChangeOrigin {
  user,
  deterministic,
  intelligence,
  external,
  system,
  undo,
  redo
}

enum FieldChangeType { set, changed, cleared }

final class FieldChange with StructuralContract {
  final FieldId fieldId;
  final FormValue? previousValue;
  final FormValue? value;
  final FieldChangeType type;
  const FieldChange({
    required this.fieldId,
    required this.previousValue,
    required this.value,
    required this.type,
  });
  @override
  Map<String, Object?> toJson() => FieldChangeCodec.encode(this);
}

final class StateChanged extends FormStateBridgeEvent {
  final Revision previousRevision;
  final Revision revision;
  final List<FieldChange> changes;
  final ChangeOrigin origin;
  final InteractionId? interactionId;
  final OperationId? operationId;
  final ProposalId? proposalId;
  StateChanged({
    required super.bridgeId,
    required super.timestamp,
    required this.previousRevision,
    required this.revision,
    required List<FieldChange> changes,
    required this.origin,
    this.interactionId,
    this.operationId,
    this.proposalId,
  }) : changes = List.unmodifiable(changes);
  @override
  Map<String, Object?> toJson() => StateChangedCodec.encode(this);
}

final class ActiveFieldChanged extends FormStateBridgeEvent {
  final FieldId? previousFieldId;
  final FieldId? fieldId;
  final ChangeOrigin origin;
  final InteractionId? interactionId;
  final OperationId? operationId;
  const ActiveFieldChanged({
    required super.bridgeId,
    required super.timestamp,
    required this.previousFieldId,
    required this.fieldId,
    required this.origin,
    this.interactionId,
    this.operationId,
  });
  @override
  Map<String, Object?> toJson() => ActiveFieldChangedCodec.encode(this);
}

final class ActionCompleted extends FormStateBridgeEvent {
  final OperationId operationId;
  final InteractionId interactionId;
  final ProposalId? proposalId;
  final ActionResult result;
  const ActionCompleted({
    required super.bridgeId,
    required super.timestamp,
    required this.operationId,
    required this.interactionId,
    this.proposalId,
    required this.result,
  });
  @override
  Map<String, Object?> toJson() => ActionCompletedCodec.encode(this);
}

final class BatchCompleted extends FormStateBridgeEvent {
  final OperationId operationId;
  final InteractionId interactionId;
  final ProposalId? proposalId;
  final BatchActionResult result;
  const BatchCompleted({
    required super.bridgeId,
    required super.timestamp,
    required this.operationId,
    required this.interactionId,
    this.proposalId,
    required this.result,
  });
  @override
  Map<String, Object?> toJson() => BatchCompletedCodec.encode(this);
}

enum BridgeErrorCode {
  initializationFailed,
  externalStoreFailure,
  mappingFailure,
  serializationFailure,
  unexpectedState,
  operationFailure,
  disposed,
  unknown,
}

final class BridgeError extends FormStateBridgeEvent {
  final BridgeErrorCode code;
  final String message;
  final bool recoverable;
  final Object? cause; // runtime-only; never serialize
  final InteractionId? interactionId;
  final OperationId? operationId;
  const BridgeError({
    required super.bridgeId,
    required super.timestamp,
    required this.code,
    required this.message,
    required this.recoverable,
    this.cause,
    this.interactionId,
    this.operationId,
  });
  @override
  Map<String, Object?> toJson() => BridgeErrorCodec.encode(this);
}

final class BridgeDisposed extends FormStateBridgeEvent {
  const BridgeDisposed({required super.bridgeId, required super.timestamp});
  @override
  Map<String, Object?> toJson() => BridgeDisposedCodec.encode(this);
}

import 'bridge_codec.dart';
import 'structural_contract.dart';
import 'canonical_json.dart';
import 'form_value.dart';
import 'form_action.dart';
import 'form_state.dart';
import 'bridge_events.dart';

enum ActionOrigin { user, deterministic, intelligence, system, undo, redo }

final class ApplyContext with StructuralContract {
  final Revision expectedRevision;
  final InteractionId interactionId;
  final OperationId operationId;
  final ProposalId? proposalId;
  final ActionOrigin origin;
  const ApplyContext({
    required this.expectedRevision,
    required this.interactionId,
    required this.operationId,
    required this.origin,
    this.proposalId,
  });
  @override
  Map<String, Object?> toJson() => ApplyContextCodec.encode(this);
}

abstract interface class FormStateBridge {
  String get id;
  String get version;
  FormStateBridgeCapabilities get capabilities;
  FormStateSnapshot get snapshot;
  Stream<FormStateBridgeEvent> get events;

  Future<ActionResult> apply(FormAction action,
      {required ApplyContext context});

  Future<BatchActionResult> applyBatch(
    List<FormAction> actions, {
    required ApplyContext context,
    BatchApplyMode mode = BatchApplyMode.bestEffort,
  });

  Future<ActionResult> undo({required ApplyContext context});
  Future<ActionResult> redo({required ApplyContext context});
  Future<void> dispose();
}

sealed class ActionResult with StructuralContract {
  final FormAction action;
  const ActionResult({required this.action});
}

final class ActionApplied extends ActionResult {
  final Revision previousRevision;
  final Revision revision;
  final FormStateSnapshot snapshot;
  const ActionApplied({
    required super.action,
    required this.previousRevision,
    required this.revision,
    required this.snapshot,
  });
  @override
  Map<String, Object?> toJson() => ActionAppliedCodec.encode(this);
}

enum NoOpReason { valueUnchanged, alreadyClear, alreadyAtTarget }

final class ActionNoOp extends ActionResult {
  final Revision revision;
  final FormStateSnapshot snapshot;
  final NoOpReason reason;
  const ActionNoOp({
    required super.action,
    required this.revision,
    required this.snapshot,
    required this.reason,
  });
  @override
  Map<String, Object?> toJson() => ActionNoOpCodec.encode(this);
}

enum ActionRejectionCode {
  staleRevision,
  readOnly,
  unknownField,
  invalidValue,
  validationFailed,
  unsupportedAction,
  capabilityUnavailable,
  conflict,
  atomicBatchAborted,
  disposed,
  internalError,
}

final class ActionRejection with StructuralContract {
  final ActionRejectionCode code;
  final String? message;
  final Map<String, Object?> details;
  ActionRejection(
      {required this.code,
      this.message,
      Map<String, Object?> details = const {}})
      : details = jsonObject(details);
  @override
  Map<String, Object?> toJson() => ActionRejectionCodec.encode(this);
}

final class ActionRejected extends ActionResult {
  final ActionRejection rejection;
  final FormStateSnapshot snapshot;
  const ActionRejected({
    required super.action,
    required this.rejection,
    required this.snapshot,
  });
  @override
  Map<String, Object?> toJson() => ActionRejectedCodec.encode(this);
}

enum BatchApplyMode { atomic, bestEffort }

enum BatchStatus { applied, partiallyApplied, noOp, rejected }

enum BatchRejectionCode {
  staleRevision,
  batchUnsupported,
  atomicBatchUnsupported,
  readOnly,
  conflict,
  disposed,
  internalError,
}

final class BatchRejection with StructuralContract {
  final BatchRejectionCode code;
  final String? message;
  final Map<String, Object?> details;
  BatchRejection(
      {required this.code,
      this.message,
      Map<String, Object?> details = const {}})
      : details = jsonObject(details);
  @override
  Map<String, Object?> toJson() => BatchRejectionCodec.encode(this);
}

final class BatchActionResult with StructuralContract {
  final BatchApplyMode mode;
  final Revision baseRevision;
  final Revision finalRevision;
  final BatchStatus status;
  final List<ActionResult> results;
  final FormStateSnapshot snapshot;
  final BatchRejection? rejection;
  BatchActionResult({
    required this.mode,
    required this.baseRevision,
    required this.finalRevision,
    required this.status,
    required List<ActionResult> results,
    required this.snapshot,
    this.rejection,
  }) : results = List.unmodifiable(results);
  @override
  Map<String, Object?> toJson() => BatchActionResultCodec.encode(this);
}

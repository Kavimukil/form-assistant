import '../contracts/context_configuration.dart';
import 'input_router.dart';
import '../contracts/bridge_events.dart';
import '../contracts/form_action.dart';
import '../contracts/form_state.dart';
import '../contracts/form_state_bridge.dart';
import '../contracts/intelligence.dart';
import '../contracts/trace.dart';
import '../contracts/validation_metadata.dart';

enum RuntimePhase {
  idle,
  interpreting,
  executing,
  awaitingClarification,
  error,
  disposed
}

/// Interaction state, deliberately distinct from authoritative form state.
final class RuntimeState {
  final RuntimePhase phase;
  final TraceContext? trace;
  final List<RequestClarificationAction> clarifications;
  final String? errorCode;
  RuntimeState(
      {required this.phase,
      this.trace,
      List<RequestClarificationAction> clarifications = const [],
      this.errorCode})
      : clarifications = List.unmodifiable(clarifications);
}

final class RuntimeActionResult {
  final ProposedAction proposedAction;
  final TraceContext trace;
  final ActionValidationMetadata validation;
  final ActionResult? bridgeResult;
  final RequestClarificationAction? clarification;
  const RuntimeActionResult(
      {required this.proposedAction,
      required this.trace,
      required this.validation,
      this.bridgeResult,
      this.clarification});
  bool get accepted =>
      bridgeResult is ActionApplied ||
      bridgeResult is ActionNoOp ||
      clarification != null;
}

final class RuntimeInteractionResult {
  final ActionProposal? proposal;
  final TraceContext trace;
  final List<RuntimeActionResult> actions;
  final FormStateSnapshot snapshot;
  final BatchStatus status;
  final String? errorCode;
  RuntimeInteractionResult(
      {this.proposal,
      required this.trace,
      required List<RuntimeActionResult> actions,
      required this.snapshot,
      required this.status,
      this.errorCode})
      : actions = List.unmodifiable(actions);
}

/// Runtime-only event map. Canonical bridge JSON is unchanged.
sealed class RuntimeEvent {
  final TraceContext? trace;
  const RuntimeEvent({this.trace});
}

final class RuntimeStateChanged extends RuntimeEvent {
  final RuntimeState state;
  const RuntimeStateChanged({required this.state, super.trace});
}

final class InterpretationRequested extends RuntimeEvent {
  final IntelligenceRequest request;
  InterpretationRequested(this.request) : super(trace: request.trace);
}

final class ProposalReceived extends RuntimeEvent {
  final ActionProposal proposal;
  const ProposalReceived({required this.proposal, required super.trace});
}

final class ProposalDiscarded extends RuntimeEvent {
  final ActionProposal proposal;
  final String reason;
  const ProposalDiscarded(
      {required this.proposal, required this.reason, required super.trace});
}

final class ProposalRevalidated extends RuntimeEvent {
  final ActionProposal proposal;
  final int revision;
  const ProposalRevalidated(
      {required this.proposal, required this.revision, required super.trace});
}

final class RuntimeActionValidated extends RuntimeEvent {
  final ProposedAction proposedAction;
  final ActionValidationMetadata validation;
  const RuntimeActionValidated(
      {required this.proposedAction,
      required this.validation,
      required super.trace});
}

final class RuntimeActionCompleted extends RuntimeEvent {
  final RuntimeActionResult result;
  RuntimeActionCompleted(this.result) : super(trace: result.trace);
}

final class ClarificationRequested extends RuntimeEvent {
  final RequestClarificationAction action;
  const ClarificationRequested({required this.action, required super.trace});
}

final class RuntimeBridgeEvent extends RuntimeEvent {
  final FormStateBridgeEvent event;
  const RuntimeBridgeEvent({required this.event, super.trace});
}

final class InteractionCompleted extends RuntimeEvent {
  final RuntimeInteractionResult result;
  InteractionCompleted(this.result) : super(trace: result.trace);
}

final class RuntimeError extends RuntimeEvent {
  final String code;
  final Object? cause;
  const RuntimeError({required this.code, this.cause, super.trace});
}

final class InputRouted extends RuntimeEvent {
  final InputRouterResult result;
  const InputRouted({required this.result, required super.trace});
}

final class ContextCompiled extends RuntimeEvent {
  final ContextDiagnostics diagnostics;
  const ContextCompiled({required this.diagnostics, required super.trace});
}

final class IntelligenceQualityEvaluated extends RuntimeEvent {
  final QualityOutcome? outcome;
  final String? reason;
  const IntelligenceQualityEvaluated(
      {this.outcome, this.reason, required super.trace});
}

import '../contracts/form_action.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_state.dart';
import '../contracts/form_state_bridge.dart';
import '../contracts/trace.dart';
import '../contracts/validation_metadata.dart';
import '../validation/form_ir_validator.dart';
import 'runtime_events.dart';

/// Routes only through FormStateBridge capabilities and interaction callbacks.
final class ActionRuntime {
  final FormIR form;
  final FormStateBridge bridge;
  final void Function(RuntimeEvent event) emit;
  final void Function(
          TraceContext trace, List<ProposedAction> actions, bool batch)
      registerOperation;
  final bool Function() isDisposed;
  ActionRuntime(
      {required this.form,
      required this.bridge,
      required this.emit,
      required this.registerOperation,
      required this.isDisposed});

  ActionValidationMetadata validate(
      FormAction action, FormStateSnapshot state) {
    final issues = <ValidationIssue>[];
    void issue(String code, {String? fieldId}) => issues.add(ValidationIssue(
        code: code, severity: ValidationSeverity.error, fieldId: fieldId));
    switch (action.classification) {
      case ActionClassification.mutation:
        final mutation = action as FormMutationAction;
        if (!bridge.capabilities.writable ||
            state.lifecycle != FormLifecycle.active) {
          issue('policy.read_only', fieldId: mutation.fieldId);
        }
        final matching = form.fields.where((f) => f.id == mutation.fieldId);
        if (matching.isEmpty) {
          issue('value.field_unknown', fieldId: mutation.fieldId);
        } else {
          issues.addAll(validateFieldAction(matching.first, mutation));
        }
      case ActionClassification.navigation:
        if (!bridge.capabilities.supportsNavigation ||
            !bridge.capabilities.supportsActiveField) {
          issue('policy.navigation_unavailable');
        }
        final target = (action as NavigateAction).target;
        if (target is FieldNavigationTarget &&
            !form.fields.any((f) => f.id == target.fieldId)) {
          issue('value.field_unknown', fieldId: target.fieldId);
        }
      case ActionClassification.assistantControl:
        final clarification = action as RequestClarificationAction;
        for (final field in clarification.fieldIds) {
          if (!form.fields.any((f) => f.id == field)) {
            issue('value.field_unknown', fieldId: field);
          }
        }
      case ActionClassification.privileged:
        issue('policy.privileged_action_unsupported');
    }
    return ActionValidationMetadata(
        status:
            issues.isEmpty ? ValidationStatus.valid : ValidationStatus.invalid,
        issues: issues,
        validatedAgainstRevision: state.revision);
  }

  ActionRejected _reject(ProposedAction proposed, ActionRejectionCode code,
          {ActionValidationMetadata? validation}) =>
      ActionRejected(
          action: proposed.action,
          rejection: ActionRejection(
              code: code,
              details: validation == null
                  ? const {}
                  : {
                      'issues':
                          validation.issues.map((i) => i.toJson()).toList()
                    }),
          snapshot: bridge.snapshot);
  ActionRejectionCode _code(ActionValidationMetadata validation) {
    final codes = validation.issues.map((i) => i.code);
    if (codes.contains('policy.read_only')) return ActionRejectionCode.readOnly;
    if (codes.contains('value.field_unknown')) {
      return ActionRejectionCode.unknownField;
    }
    if (codes.any((c) => c.startsWith('policy.'))) {
      return ActionRejectionCode.capabilityUnavailable;
    }
    if (codes.contains('value.type_mismatch') ||
        codes.contains('value.option_unknown')) {
      return ActionRejectionCode.invalidValue;
    }
    return ActionRejectionCode.validationFailed;
  }

  ApplyContext _context(
          TraceContext trace, int revision, ActionOrigin origin) =>
      ApplyContext(
          expectedRevision: revision,
          interactionId: trace.interactionId,
          operationId: trace.operationId,
          proposalId: trace.proposalId,
          origin: origin);
  RuntimeActionResult _result(ProposedAction proposed, TraceContext trace,
          ActionValidationMetadata validation,
          {ActionResult? bridgeResult,
          RequestClarificationAction? clarification}) =>
      RuntimeActionResult(
          proposedAction: proposed,
          trace: trace.withProposal(trace.proposalId!, actionId: proposed.id),
          validation: validation,
          bridgeResult: bridgeResult,
          clarification: clarification);

  Future<List<RuntimeActionResult>> execute(List<ProposedAction> actions,
      {required TraceContext trace,
      required FormStateSnapshot expected,
      ActionOrigin origin = ActionOrigin.intelligence,
      BatchApplyMode mode = BatchApplyMode.bestEffort}) async {
    if (mode == BatchApplyMode.atomic) {
      return _atomic(actions, trace, expected, origin);
    }
    final results = <RuntimeActionResult>[];
    var revision = expected.revision;
    var stopped = false;
    for (final proposed in actions) {
      final current = bridge.snapshot;
      final validation = validate(proposed.action, current);
      final actionTrace =
          trace.withProposal(trace.proposalId!, actionId: proposed.id);
      emit(RuntimeActionValidated(
          proposedAction: proposed,
          validation: validation,
          trace: actionTrace));
      late final RuntimeActionResult result;
      if (isDisposed() || stopped || current.revision != revision) {
        stopped = true;
        result = _result(proposed, trace, validation,
            bridgeResult: _reject(
                proposed,
                isDisposed()
                    ? ActionRejectionCode.disposed
                    : ActionRejectionCode.staleRevision));
      } else if (validation.status == ValidationStatus.invalid) {
        result = _result(proposed, trace, validation,
            bridgeResult:
                _reject(proposed, _code(validation), validation: validation));
      } else if (proposed.action is RequestClarificationAction) {
        final clarification = proposed.action as RequestClarificationAction;
        emit(ClarificationRequested(action: clarification, trace: actionTrace));
        result =
            _result(proposed, trace, validation, clarification: clarification);
      } else {
        final operationTrace = actionTrace;
        registerOperation(operationTrace, [proposed], false);
        final applied = await bridge.apply(proposed.action,
            context: _context(operationTrace, revision, origin));
        if (applied is ActionApplied) revision = applied.revision;
        if (applied is ActionRejected &&
            applied.rejection.code == ActionRejectionCode.staleRevision) {
          stopped = true;
        }
        result = _result(proposed, operationTrace, validation,
            bridgeResult: applied);
      }
      results.add(result);
      emit(RuntimeActionCompleted(result));
    }
    return List.unmodifiable(results);
  }

  Future<List<RuntimeActionResult>> _atomic(
      List<ProposedAction> actions,
      TraceContext trace,
      FormStateSnapshot expected,
      ActionOrigin origin) async {
    final validations = [
      for (final proposed in actions) validate(proposed.action, expected)
    ];
    final owned = actions
        .where((p) =>
            p.action.classification != ActionClassification.assistantControl)
        .toList();
    final unavailable = owned.isNotEmpty &&
        (!bridge.capabilities.supportsBatch ||
            !bridge.capabilities.supportsAtomicBatch);
    for (var i = 0; i < actions.length; i++) {
      emit(RuntimeActionValidated(
          proposedAction: actions[i],
          validation: validations[i],
          trace:
              trace.withProposal(trace.proposalId!, actionId: actions[i].id)));
    }
    final invalid =
        validations.any((v) => v.status == ValidationStatus.invalid);
    BatchActionResult? batch;
    if (!invalid && !unavailable && !isDisposed() && owned.isNotEmpty) {
      registerOperation(trace, owned, true);
      batch = await bridge.applyBatch(owned.map((p) => p.action).toList(),
          context: _context(trace, expected.revision, origin),
          mode: BatchApplyMode.atomic);
    }
    final successful = !invalid &&
        !unavailable &&
        !isDisposed() &&
        (batch == null ||
            batch.status == BatchStatus.applied ||
            batch.status == BatchStatus.noOp);
    var ownedIndex = 0;
    final results = <RuntimeActionResult>[];
    for (var i = 0; i < actions.length; i++) {
      final proposed = actions[i];
      final validation = validations[i];
      ActionResult? bridgeResult;
      RequestClarificationAction? clarification;
      if (successful && proposed.action is RequestClarificationAction) {
        clarification = proposed.action as RequestClarificationAction;
        emit(ClarificationRequested(
            action: clarification,
            trace:
                trace.withProposal(trace.proposalId!, actionId: proposed.id)));
      } else if (batch != null &&
          proposed.action.classification !=
              ActionClassification.assistantControl &&
          batch.results.isNotEmpty) {
        bridgeResult = batch.results[ownedIndex++];
      } else if (!successful) {
        final code = isDisposed()
            ? ActionRejectionCode.disposed
            : unavailable
                ? ActionRejectionCode.capabilityUnavailable
                : validation.status == ValidationStatus.invalid
                    ? _code(validation)
                    : batch?.rejection?.code == BatchRejectionCode.staleRevision
                        ? ActionRejectionCode.staleRevision
                        : ActionRejectionCode.atomicBatchAborted;
        bridgeResult = _reject(proposed, code, validation: validation);
      }
      final result = _result(proposed, trace, validation,
          bridgeResult: bridgeResult, clarification: clarification);
      results.add(result);
      emit(RuntimeActionCompleted(result));
    }
    return List.unmodifiable(results);
  }
}

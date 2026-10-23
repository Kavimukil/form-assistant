import '../contracts/form_action.dart';
import '../contracts/intelligence.dart';
import '../contracts/validation_metadata.dart';
import '../validation/form_ir_validator.dart';

final class QualityDecision {
  final QualityOutcome outcome;
  final String reason;
  final List<ProposedAction> actions;
  QualityDecision(this.outcome, this.reason, List<ProposedAction> actions)
      : actions = List.unmodifiable(actions);
}

/// Reasons that stay clarification. They are not cloud fallbacks.
const qualityClarificationReasons = {
  'low_confidence',
  'no_answer',
  'conflicting_writes',
  'invalid_value',
  'non_writable_field',
  'disallowed_action',
  'unknown_context_field',
  'unknown_navigation_field',
  'unknown_clarification_field',
};

/// Provider-neutral proposal safety check. Runtime/bridge still validate commits.
final class QualityGate {
  final double minimumConfidence;
  QualityGate({this.minimumConfidence = 0.8}) {
    if (!minimumConfidence.isFinite ||
        minimumConfidence < 0 ||
        minimumConfidence > 1) {
      throw ArgumentError('Invalid confidence threshold');
    }
  }
  QualityDecision evaluate(
      IntelligenceRequest request, List<ProposedAction> actions,
      {double? confidence, bool rejectConflictingWrites = false}) {
    final fields = {
      for (final f in request.context.fields) f.field.id: f.field
    };
    QualityDecision clarify(String reason, ClarificationReason kind,
            [List<String> ids = const []]) =>
        QualityDecision(QualityOutcome.clarify, reason, [
          ProposedAction(
              id: '${request.trace.requestId}/clarify',
              action: RequestClarificationAction(reason: kind, fieldIds: ids))
        ]);
    if (confidence != null &&
        (!confidence.isFinite || confidence < 0 || confidence > 1)) {
      throw const FormatException('Invalid model confidence');
    }
    if (confidence != null && confidence < minimumConfidence) {
      return clarify('low_confidence', ClarificationReason.lowConfidence);
    }
    if (actions.isEmpty) {
      return clarify('no_answer', ClarificationReason.missingInformation);
    }
    final writable = {for (final f in request.context.fields) f.id: f.writable};
    final writes = <String, FormMutationAction>{};
    final unique = <ProposedAction>[];
    for (final proposed in actions) {
      final action = proposed.action;
      if (action is FormMutationAction) {
        if (writable[action.fieldId] == false) {
          return clarify(
              'non_writable_field', ClarificationReason.invalidValue);
        }
        final prior = writes[action.fieldId];
        if (rejectConflictingWrites && prior != null) {
          if (prior != action) {
            return clarify(
                'conflicting_writes', ClarificationReason.invalidValue);
          }
          continue;
        }
        writes[action.fieldId] = action;
      }
      unique.add(proposed);
    }
    final checked = <ProposedAction>[];
    var invalid = false;
    for (final proposed in unique) {
      final action = proposed.action;
      final type = action.toJson()['type'];
      if (!request.allowedActionTypes.contains(type)) {
        return clarify('disallowed_action', ClarificationReason.invalidValue);
      }
      if (action is FormMutationAction) {
        final field = fields[action.fieldId];
        if (field == null) {
          return clarify(
              'unknown_context_field', ClarificationReason.missingInformation);
        }
        final issues = validateFieldAction(field, action);
        if (issues.isNotEmpty) {
          invalid = true;
          checked.add(ProposedAction(
              id: proposed.id,
              action: RequestClarificationAction(
                  reason: ClarificationReason.invalidValue,
                  fieldIds: [field.id]),
              validation: ActionValidationMetadata(
                  status: ValidationStatus.invalid,
                  issues: issues,
                  validatedAgainstRevision: request.context.revision)));
          continue;
        }
      }
      if (action is NavigateAction &&
          action.target is FieldNavigationTarget &&
          !fields
              .containsKey((action.target as FieldNavigationTarget).fieldId)) {
        return clarify(
            'unknown_navigation_field', ClarificationReason.missingInformation);
      }
      if (action is RequestClarificationAction &&
          action.fieldIds.any((id) => !fields.containsKey(id))) {
        return clarify('unknown_clarification_field',
            ClarificationReason.missingInformation);
      }
      checked.add(proposed);
    }
    return QualityDecision(
        invalid ? QualityOutcome.clarify : QualityOutcome.accept,
        invalid ? 'invalid_value' : 'validated',
        checked);
  }

  /// Accept stays accept. Ambiguous and invalid clarifications stay clarify.
  /// Any other clarify or an existing fallback becomes fallback only when
  /// [allowFallback] is true; otherwise it stays clarify.
  QualityDecision considerFallback(QualityDecision decision,
      {required bool allowFallback}) {
    if (decision.outcome == QualityOutcome.accept) return decision;
    final staysLocal = qualityClarificationReasons.contains(decision.reason);
    if (!allowFallback || staysLocal) {
      return decision.outcome == QualityOutcome.clarify
          ? decision
          : QualityDecision(
              QualityOutcome.clarify, decision.reason, decision.actions);
    }
    return decision.outcome == QualityOutcome.fallback
        ? decision
        : QualityDecision(
            QualityOutcome.fallback, decision.reason, decision.actions);
  }
}

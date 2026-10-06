import 'package:form_assistant_core/form_assistant_core.dart';

/// Internal extraction outcomes. No cloud route is enabled in Phase 6R.
enum ExtractionQualityOutcome { accept, reject, clarify, fallback }

final class ExtractionQualityDecision {
  final ExtractionQualityOutcome outcome;
  final QualityDecision? canonical;
  final String reason;
  const ExtractionQualityDecision(this.outcome, this.reason, [this.canonical]);
}

final class FunctionGemmaQualityGate {
  final QualityGate canonicalGate;
  FunctionGemmaQualityGate(this.canonicalGate);
  ExtractionQualityDecision evaluate(
      IntelligenceRequest request, List<ProposedAction> actions,
      {double? confidence}) {
    final decision = canonicalGate.evaluate(request, actions,
        confidence: confidence, rejectConflictingWrites: true);
    return ExtractionQualityDecision(
        decision.outcome == QualityOutcome.accept
            ? ExtractionQualityOutcome.accept
            : ExtractionQualityOutcome.clarify,
        decision.reason,
        decision);
  }

  ExtractionQualityDecision reject(FormatException error) =>
      ExtractionQualityDecision(ExtractionQualityOutcome.reject, error.message);
}

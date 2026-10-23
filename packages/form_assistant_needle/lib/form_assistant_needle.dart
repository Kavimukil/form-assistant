library;

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/tools/validator.dart';
import 'package:form_assistant_function_gemma/src/tools/mapper.dart';
import 'src/native.dart';
export 'src/native.dart'
    show NeedleInferenceRequest, NeedleOutput, LocalNeedleInference;

/// Needle 3 proposes slots only; the runtime and bridge own all commits.
final class NeedleAdapter implements IntelligenceAdapter {
  final LocalNeedleInference inference;
  final QualityGate qualityGate;
  @override
  final String id;
  @override
  final String version;
  NeedleAdapter(
      {required this.inference,
      QualityGate? qualityGate,
      this.id = 'needle3',
      this.version = '0.1.0'})
      : qualityGate = qualityGate ?? QualityGate();
  @override
  Future<IntelligenceResult> interpret(IntelligenceRequest request,
      {IntelligenceOptions? options}) async {
    final settings = options ?? const IntelligenceOptions();
    final cancellation = CancellationToken();
    final detach = settings.cancellation?.listen(cancellation.cancel);
    try {
      return await runIntelligence(() async {
        cancellation.throwIfCancelled();
        final output =
            await inference(formatNeedleRequest(request), cancellation);
        cancellation.throwIfCancelled();
        final envelope = needleEnvelope(output.text);
        final confidence = (envelope['confidence'] as num?)?.toDouble();
        final validated = FunctionGemmaToolCallValidator().validate(
            parseNeedleCalls(output.text), request.context,
            allowedActionTypes: request.allowedActionTypes);
        final proposed = [
          for (var i = 0; i < validated.calls.length; i++)
            ProposedAction(
                id: '${request.trace.requestId}/action/$i',
                action: mapFunctionGemmaCall(validated.calls[i]))
        ];
        // Suppressed calls are diagnostics, never promoted into proposals.
        final grounding = envelope['validation'];
        var ungrounded = false;
        if (grounding != null) {
          final g = jsonObject(grounding);
          if (g['ungrounded'] != null) {
            ungrounded = stringList(g['ungrounded']).isNotEmpty;
          }
        }
        final decision = qualityGate.evaluate(
            request, ungrounded ? const [] : proposed,
            confidence: confidence, rejectConflictingWrites: true);
        return IntelligenceResult(
            proposal: ActionProposal(
                id: '${request.trace.requestId}/needle3',
                baseRevision: request.context.revision,
                actions: decision.actions,
                confidence: confidence,
                provenance: ActionProvenance(
                    trace: request.trace,
                    adapterId: id,
                    adapterVersion: version)),
            quality: decision.outcome,
            qualityReason: ungrounded ? 'needle_ungrounded' : decision.reason);
      }, settings);
    } finally {
      cancellation.cancel();
      detach?.call();
    }
  }
}

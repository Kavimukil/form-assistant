library;

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/tools/validator.dart';
import 'package:form_assistant_function_gemma/src/tools/mapper.dart';
import 'src/native.dart';
export 'src/native.dart'
    show
        Qwen3VlInferenceRequest,
        Qwen3VlOutput,
        LocalQwen3VlInference,
        formatQwen3VlRequest,
        formatQwenChatPrompt,
        qwenStopToken,
        qwenEnvelope,
        qwenCallEnvelopes,
        parseQwenCalls;

/// Qwen3VL proposes slots only; the runtime and bridge own all commits.
final class Qwen3VlAdapter implements IntelligenceAdapter {
  final LocalQwen3VlInference inference;
  final QualityGate qualityGate;
  @override
  final String id;
  @override
  final String version;
  Qwen3VlAdapter(
      {required this.inference,
      QualityGate? qualityGate,
      this.id = 'qwen3vl',
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
            await inference(formatQwen3VlRequest(request), cancellation);
        cancellation.throwIfCancelled();
        final envelope = qwenEnvelope(output.text);
        final confidence = (envelope['confidence'] as num?)?.toDouble();
        final validated = FunctionGemmaToolCallValidator().validate(
            parseQwenCalls(output.text), request.context,
            allowedActionTypes: request.allowedActionTypes);
        final proposed = [
          for (var i = 0; i < validated.calls.length; i++)
            ProposedAction(
                id: '${request.trace.requestId}/action/$i',
                action: mapFunctionGemmaCall(validated.calls[i]))
        ];
        final decision = qualityGate.evaluate(request, proposed,
            confidence: confidence, rejectConflictingWrites: true);
        return IntelligenceResult(
            proposal: ActionProposal(
                id: '${request.trace.requestId}/qwen3vl',
                baseRevision: request.context.revision,
                actions: decision.actions,
                confidence: confidence,
                provenance: ActionProvenance(
                    trace: request.trace,
                    adapterId: id,
                    adapterVersion: version)),
            quality: decision.outcome,
            qualityReason: decision.reason);
      }, settings);
    } finally {
      cancellation.cancel();
      detach?.call();
    }
  }
}

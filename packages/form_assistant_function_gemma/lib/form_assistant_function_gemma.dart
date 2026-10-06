library;

import 'package:form_assistant_core/form_assistant_core.dart';
import 'src/backend.dart';
import 'src/format.dart';
export 'src/backend.dart' show FunctionGemmaOutput, LocalFunctionGemmaInference;

/// Zero-shot local adapter. The callback owns the local model runner.
final class FunctionGemmaAdapter implements IntelligenceAdapter {
  final InferenceBackend _backend;
  final QualityGate qualityGate;
  @override
  final String id;
  @override
  final String version;
  FunctionGemmaAdapter(
      {required LocalFunctionGemmaInference inference,
      QualityGate? qualityGate,
      this.id = 'function_gemma',
      this.version = '0.2.0'})
      : _backend = CallbackBackend(inference),
        qualityGate = qualityGate ?? QualityGate();

  /// JSON-safe application output; the model still uses native tool syntax.
  /// Canonical action JSON is unchanged and metadata stays in the envelope.
  Future<Map<String, Object?>> interpretJson(IntelligenceRequest request,
      {IntelligenceOptions? options}) async {
    final result = await interpret(request, options: options);
    final proposal = result.proposal;
    return jsonObject({
      'specVersion': protocolSpecVersion,
      'proposal': {
        'id': proposal.id,
        'baseRevision': proposal.baseRevision,
        'actions': [
          for (final action in proposal.actions)
            {
              'id': action.id,
              'action': action.action.toJson(),
              if (action.validation != null)
                'validation': action.validation!.toJson(),
            }
        ],
        'provenance': {
          'trace': proposal.provenance.trace.toJson(),
          'adapterId': proposal.provenance.adapterId,
          'adapterVersion': proposal.provenance.adapterVersion,
          'origin': proposal.provenance.origin.name,
        },
        if (proposal.confidence != null) 'confidence': proposal.confidence,
      },
      if (result.quality != null) 'quality': result.quality!.name,
      if (result.qualityReason != null) 'qualityReason': result.qualityReason,
    });
  }

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
            await _backend.generate(formatPrompt(request), cancellation);
        cancellation.throwIfCancelled();
        final decision = qualityGate.evaluate(
            request, parseOutput(output.text, request),
            confidence: output.confidence);
        return IntelligenceResult(
            proposal: ActionProposal(
                id: '${request.trace.requestId}/function-gemma',
                baseRevision: request.context.revision,
                actions: decision.actions,
                confidence: output.confidence,
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

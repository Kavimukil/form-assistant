import 'dart:convert';

import 'package:form_assistant_core/form_assistant_core.dart';

/// Host-owned cloud completion. This package does not open a socket.
final class CloudInferenceRequest {
  final IntelligenceRequest request;
  final String prompt;
  const CloudInferenceRequest({required this.request, required this.prompt});
}

final class CloudCompletionOutput {
  final String text;
  const CloudCompletionOutput(this.text);
}

typedef CloudCompletion = Future<CloudCompletionOutput> Function(
    CloudInferenceRequest request, CancellationToken cancellation);

/// Compact context plus the utterance. No FormIR and no live bridge state.
String formatCloudPrompt(IntelligenceRequest request) => jsonEncode({
      'utterance': request.input.text,
      'context': request.context.modelRelevantJson(),
      'allowedActionTypes': request.allowedActionTypes,
      'response': {
        'actions': 'canonical FormAction objects',
      },
    });

/// One JSON object: `{"actions":[...]}`. Optional `confidence`. No repair.
Map<String, Object?> decodeCloudEnvelope(String source) {
  final text = source.trim();
  if (text.length > 65536 || !text.startsWith('{') || !text.endsWith('}')) {
    throw const FormatException('Cloud output must be one JSON object');
  }
  final Object? decoded = jsonDecode(text);
  final object = jsonObject(decoded);
  const allowed = {'actions', 'confidence'};
  if (object.keys.any((key) => !allowed.contains(key)) ||
      !object.containsKey('actions')) {
    throw const FormatException('Cloud output must contain actions');
  }
  if (object['confidence'] != null) {
    final confidence = requireType<num>(object['confidence']);
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const FormatException('Invalid cloud confidence');
    }
  }
  requireType<List<Object?>>(object['actions']);
  return object;
}

/// Cloud proposals use the same canonical FormAction protocol as local adapters.
final class CloudLLMAdapter implements IntelligenceAdapter {
  final CloudCompletion complete;
  final QualityGate qualityGate;
  @override
  final String id;
  @override
  final String version;
  CloudLLMAdapter(
      {required this.complete,
      QualityGate? qualityGate,
      this.id = 'cloud_llm',
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
        final output = await complete(
            CloudInferenceRequest(
                request: request, prompt: formatCloudPrompt(request)),
            cancellation);
        cancellation.throwIfCancelled();
        final envelope = decodeCloudEnvelope(output.text);
        final confidence = (envelope['confidence'] as num?)?.toDouble();
        final decoded = requireType<List<Object?>>(envelope['actions']);
        final proposed = <ProposedAction>[
          for (var i = 0; i < decoded.length; i++)
            ProposedAction(
                id: '${request.trace.requestId}/cloud/action/$i',
                action: FormActionCodec.decode(decoded[i]))
        ];
        final decision = qualityGate.evaluate(request, proposed,
            confidence: confidence, rejectConflictingWrites: true);
        final proposalId = '${request.trace.requestId}/cloud';
        return IntelligenceResult(
            proposal: ActionProposal(
                id: proposalId,
                baseRevision: request.context.revision,
                actions: decision.actions,
                confidence: confidence,
                provenance: ActionProvenance(
                    trace: TraceContext(
                        interactionId: request.trace.interactionId,
                        requestId: request.trace.requestId,
                        operationId: request.trace.operationId,
                        proposalId: proposalId,
                        segmentId: request.trace.segmentId),
                    adapterId: id,
                    adapterVersion: version,
                    backendId: id)),
            quality: decision.outcome,
            qualityReason: decision.reason);
      }, settings);
    } finally {
      cancellation.cancel();
      detach?.call();
    }
  }
}

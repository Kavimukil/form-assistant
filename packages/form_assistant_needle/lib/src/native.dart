import 'dart:convert';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/format.dart'
    show FunctionGemmaContextFormatter, simpleNativeParameters;
import 'package:form_assistant_function_gemma/src/tools/schema.dart';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';
import 'strict_json.dart';

/// Local model-specific callback boundary; no form-state access or execution.
final class NeedleInferenceRequest {
  final String systemFacts;
  final String toolsJson;
  final String input;
  const NeedleInferenceRequest(
      {required this.systemFacts,
      required this.toolsJson,
      required this.input});
}

final class NeedleOutput {
  final String text;
  const NeedleOutput(this.text);
}

typedef LocalNeedleInference = Future<NeedleOutput> Function(
    NeedleInferenceRequest request, CancellationToken cancellation);
NeedleInferenceRequest formatNeedleRequest(IntelligenceRequest request) {
  final tools = FunctionGemmaToolSchemaBuilder()
      .build(request.context, allowedActionTypes: request.allowedActionTypes);
  return NeedleInferenceRequest(
      systemFacts:
          'Form context: ${const FunctionGemmaContextFormatter().format(request.context)}',
      toolsJson: jsonEncode([
        for (final d in tools.definitions)
          {
            'name': d.name,
            'description': d.name == 'clear_field'
                ? 'Clear the supplied field when explicitly requested.'
                : 'Extract the supplied typed field answer.',
            'parameters': simpleNativeParameters(d.parameters),
          }
      ]),
      input: request.input.text);
}

Map<String, Object?> needleEnvelope(String output) {
  final j = jsonObject(decodeStrictNeedleJson(output));
  if (j['success'] != true || j['error'] != null || j['error_code'] != null) {
    throw FormatException(
        'Needle engine failure: ${j['error_code'] ?? j['error']}');
  }
  if (j['type'] != 'call' && j['type'] != 'respond') {
    throw const FormatException('Unknown Needle response type');
  }
  final calls = requireType<List<Object?>>(j['function_calls']);
  if (calls.length > 64) throw const FormatException('Too many Needle calls');
  if (j['confidence'] != null) {
    final confidence = requireType<num>(j['confidence']);
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const FormatException('Invalid Needle confidence');
    }
  }
  return j;
}

List<Map<String, Object?>> needleCallEnvelopes(String output) =>
    requireType<List<Object?>>(needleEnvelope(output)['function_calls'])
        .map(jsonObject)
        .toList();
List<FunctionGemmaToolCall> parseNeedleCalls(String output) =>
    needleCallEnvelopes(output).map(FunctionGemmaToolCall.fromJson).toList();

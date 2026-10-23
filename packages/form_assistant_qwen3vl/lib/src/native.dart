import 'dart:convert';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/format.dart'
    show FunctionGemmaContextFormatter, simpleNativeParameters;
import 'package:form_assistant_function_gemma/src/tools/schema.dart';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';
import 'strict_json.dart';

/// Local model-specific callback boundary; no form-state access or execution.
final class Qwen3VlInferenceRequest {
  final String prompt;
  const Qwen3VlInferenceRequest({required this.prompt});
}

final class Qwen3VlOutput {
  final String text;
  const Qwen3VlOutput(this.text);
}

typedef LocalQwen3VlInference = Future<Qwen3VlOutput> Function(
    Qwen3VlInferenceRequest request, CancellationToken cancellation);

const qwenStopToken = '<|im_end|>';

String formatQwenChatPrompt({
  required String system,
  required String user,
}) =>
    '<|im_start|>system\n$system<|im_end|>\n'
    '<|im_start|>user\n$user<|im_end|>\n'
    '<|im_start|>assistant\n';

Qwen3VlInferenceRequest formatQwen3VlRequest(IntelligenceRequest request) {
  final tools = FunctionGemmaToolSchemaBuilder()
      .build(request.context, allowedActionTypes: request.allowedActionTypes);
  final toolsJson = jsonEncode([
    for (final d in tools.definitions)
      {
        'name': d.name,
        'description': d.name == 'clear_field'
            ? 'Clear the supplied field when explicitly requested.'
            : 'Extract the supplied typed field answer.',
        'parameters': simpleNativeParameters(d.parameters),
      }
  ]);
  final context = const FunctionGemmaContextFormatter().format(request.context);
  final system = [
    'You extract form field values from English user utterances.',
    'Use only the listed tools. Emit exactly one JSON object and nothing else.',
    'Schema: {"function_calls":[{"name":"<tool>","arguments":{...}}]}',
    'If nothing should change, emit {"function_calls":[]}.',
    'Do not invent fields, options, or prose. Do not wrap tools in markdown.',
    'Form context: $context',
    'Tools: $toolsJson',
  ].join('\n');
  return Qwen3VlInferenceRequest(
      prompt: formatQwenChatPrompt(system: system, user: request.input.text));
}

Map<String, Object?> qwenEnvelope(String output) {
  final j = jsonObject(decodeStrictQwenJson(output));
  if (!j.containsKey('function_calls')) {
    throw const FormatException('Missing function_calls');
  }
  final calls = requireType<List<Object?>>(j['function_calls']);
  if (calls.length > 64) {
    throw const FormatException('Too many Qwen function calls');
  }
  if (j['confidence'] != null) {
    final confidence = requireType<num>(j['confidence']);
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const FormatException('Invalid Qwen confidence');
    }
  }
  return j;
}

List<Map<String, Object?>> qwenCallEnvelopes(String output) =>
    requireType<List<Object?>>(qwenEnvelope(output)['function_calls'])
        .map(jsonObject)
        .toList();

List<FunctionGemmaToolCall> parseQwenCalls(String output) =>
    qwenCallEnvelopes(output).map(FunctionGemmaToolCall.fromJson).toList();

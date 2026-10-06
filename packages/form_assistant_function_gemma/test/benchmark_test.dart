import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/form_assistant_function_gemma.dart';
import 'package:form_assistant_function_gemma/src/format.dart';
import 'package:form_assistant_function_gemma/src/evaluation/benchmark.dart';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';
import 'package:test/test.dart';

void main() {
  final root = '../../benchmarks/function_gemma_phase6r';
  final fixtures = File('$root/corpus.v1.jsonl')
      .readAsLinesSync()
      .map((line) => jsonObject(jsonDecode(line)))
      .toList();
  final config =
      jsonObject(jsonDecode(File('$root/gate.v1.json').readAsStringSync()));
  for (final fixture in fixtures) {
    test('frozen expected extraction/runtime fixture: ${fixture['id']}',
        () async {
      final context = SemanticContext.fromJson(jsonDecode(
          File('$root/contexts/${fixture['contextFixture']}')
              .readAsStringSync()));
      final calls = requireType<List<Object?>>(fixture['expectedCalls'])
          .map(FunctionGemmaToolCall.fromJson)
          .toList();
      final output = calls
          .map((c) =>
              '<start_function_call>call:${c.name}${nativeWire(c.arguments)}<end_function_call>')
          .join();
      final result = await evaluateExtractionCase(
          fixture, context, (_, __) async => FunctionGemmaOutput(output));
      expect(result['passed'], true, reason: jsonEncode(result));
      expect(result['safetyViolations'], 0);
    });
  }
  test('benchmark expectations/categories and thresholds stay frozen', () {
    expect(fixtures, hasLength(31));
    expect(fixtures.map((c) => c['category']).toSet(), hasLength(17));
    expect(config['simpleExact'], .97);
    expect(config['booleanExact'], .98);
    expect(config['compoundExact'], .92);
    expect(config['malformedCallRateMax'], .02);
    expect(config['latencyBudgetMs'], isNull);
  });
  test(
      'wrong types, field/option hallucinations and prose cannot score as success',
      () async {
    for (final id in [
      'integer_age',
      'choice_alias',
      'option_truncated',
      'out_of_context'
    ]) {
      final fixture = fixtures.singleWhere((f) => f['id'] == id);
      final context = SemanticContext.fromJson(jsonDecode(
          File('$root/contexts/${fixture['contextFixture']}')
              .readAsStringSync()));
      final outputs = [
        'I cannot assist.',
        '<start_function_call>call:set_integer{field_id:<escape>age<escape>,value:<escape>32<escape>}<end_function_call>',
        '<start_function_call>call:set_string{field_id:<escape>source:country<escape>,value:<escape>India<escape>}<end_function_call>',
        '<start_function_call>call:set_choice{field_id:<escape>country<escape>,value:<escape>japan<escape>}<end_function_call>'
      ];
      for (final output in outputs) {
        final result = await evaluateExtractionCase(
            fixture, context, (_, __) async => FunctionGemmaOutput(output));
        expect(result['passed'], false);
        expect(result['safetyViolations'], 0);
        expect(result['failureCategory'], isIn(failureTaxonomy));
      }
    }
  });
}

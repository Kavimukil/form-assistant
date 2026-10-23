import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_qwen3vl/form_assistant_qwen3vl.dart';
import 'package:form_assistant_function_gemma/form_assistant_function_gemma.dart';
import 'package:form_assistant_qwen3vl/src/strict_json.dart';
import 'package:form_assistant_function_gemma/src/evaluation/benchmark.dart';
import 'package:test/test.dart';

String response(List<Object?> calls, {num? confidence}) => jsonEncode({
      'function_calls': calls,
      if (confidence != null) 'confidence': confidence,
    });
IntelligenceRequest request({bool writable = true}) => IntelligenceRequest(
    input: const UserInput(text: 'Age thirty two'),
    context: SemanticContext(formId: 'f', revision: 17, fields: [
      FormFieldContext(
          field: FormField(
              id: 'age',
              value: const IntegerDefinition(),
              semantics: FieldSemantics(label: 'Age')),
          writable: writable)
    ]),
    allowedActionTypes: ['set_value', 'clear_value'],
    trace: const TraceContext(
        interactionId: 'i', requestId: 'r', operationId: 'o'));
const validCall = {
  'name': 'set_integer',
  'arguments': {'field_id': 'age', 'value': 32}
};
void main() {
  final root = '../../benchmarks/function_gemma_phase6r';
  final fixtures = File('$root/corpus.v1.jsonl')
      .readAsLinesSync()
      .map((s) => jsonObject(jsonDecode(s)))
      .toList();
  for (final fixture in fixtures) {
    test('Qwen unchanged frozen fixture: ${fixture['id']}', () async {
      final context = SemanticContext.fromJson(jsonDecode(
          File('$root/contexts/${fixture['contextFixture']}')
              .readAsStringSync()));
      final raw = <String>[];
      final adapter = Qwen3VlAdapter(inference: (r, c) async {
        final text =
            response(requireType<List<Object?>>(fixture['expectedCalls']));
        raw.add(text);
        return Qwen3VlOutput(text);
      });
      final result = await evaluateAdapterCase(fixture, context,
          adapter: adapter,
          rawOutputs: raw,
          decodeEnvelopes: qwenCallEnvelopes);
      expect(result['passed'], true, reason: jsonEncode(result));
      expect(result['safetyViolations'], 0);
    });
  }
  test('shared harness preserves every recorded FunctionGemma score', () async {
    final recorded = jsonObject(jsonDecode(
        File('$root/reports/simple_native.v1.json').readAsStringSync()));
    for (final previous
        in requireType<List<Object?>>(recorded['cases']).map(jsonObject)) {
      final fixture = fixtures.singleWhere((f) => f['id'] == previous['id']);
      final context = SemanticContext.fromJson(jsonDecode(
          File('$root/contexts/${fixture['contextFixture']}')
              .readAsStringSync()));
      final replay = await evaluateExtractionCase(
          fixture,
          context,
          (_, __) async =>
              FunctionGemmaOutput(requiredString(previous, 'rawOutput')));
      for (final key in [
        'passed',
        'exactActionSet',
        'fieldIdentification',
        'stateCorrect',
        'clarificationCorrect',
        'malformedCall',
        'hallucinatedField',
        'hallucinatedOption',
        'safetyViolations',
        'failureCategory'
      ]) {
        expect(replay[key], previous[key], reason: '${previous['id']}/$key');
      }
      expect(replay['actualValues'], previous['actualValues']);
    }
  });
  test(
      'context and specialized eight-tool contract; no workflow or source extensions',
      () {
    final formatted = formatQwen3VlRequest(request());
    expect(formatted.prompt, contains('<|im_start|>system'));
    expect(formatted.prompt, contains('<|im_start|>user'));
    expect(formatted.prompt, contains('<|im_start|>assistant'));
    expect(formatted.prompt, contains('"label":"Age"'));
    expect(formatted.prompt, contains('set_integer'));
    expect(formatted.prompt, contains('clear_field'));
    expect(formatted.prompt, isNot(contains('fingerprint')));
    expect(formatted.prompt, endsWith('<|im_start|>assistant\n'));
    expect(formatQwen3VlRequest(request(writable: false)).prompt,
        contains('Tools: []'));
  });
  test('confidence/provenance/revision remain outside canonical actions',
      () async {
    final result = await Qwen3VlAdapter(
            inference: (_, __) async =>
                Qwen3VlOutput(response([validCall], confidence: .95)))
        .interpret(request());
    expect(result.proposal.baseRevision, 17);
    expect(result.proposal.provenance.adapterId, 'qwen3vl');
    expect(result.proposal.confidence, .95);
    expect(result.quality, QualityOutcome.accept);
    expect(result.proposal.actions.single.action,
        const SetValueAction(fieldId: 'age', value: IntegerValue(32)));
  });
  test('absent confidence still accepts via QualityGate defaults', () async {
    final result = await Qwen3VlAdapter(
            inference: (_, __) async => Qwen3VlOutput(response([validCall])))
        .interpret(request());
    expect(result.proposal.confidence, isNull);
    expect(result.quality, QualityOutcome.accept);
  });
  test('low confidence clarifies; no invented confidence', () async {
    final result = await Qwen3VlAdapter(
            inference: (_, __) async =>
                Qwen3VlOutput(response([validCall], confidence: .79)))
        .interpret(request());
    expect(result.quality, QualityOutcome.clarify);
    expect(result.proposal.actions.single.action,
        isA<RequestClarificationAction>());
  });
  test('no coercion, unknown tools/fields and conflicting writes rejected',
      () async {
    for (final calls in [
      [
        {
          'name': 'set_integer',
          'arguments': {'field_id': 'age', 'value': '32'}
        }
      ],
      [
        {
          'name': 'set_integer',
          'arguments': {'field_id': 'unknown', 'value': 32}
        }
      ],
      [
        {
          'name': 'navigate',
          'arguments': {'target': 'next'}
        }
      ],
      [
        {
          'name': 'clear_field',
          'arguments': {'field_id': 'age', 'value': null}
        }
      ],
      [
        validCall,
        {
          'name': 'set_integer',
          'arguments': {'field_id': 'age', 'value': 31}
        }
      ],
    ]) {
      await expectLater(
          Qwen3VlAdapter(
                  inference: (_, __) async => Qwen3VlOutput(response(calls)))
              .interpret(request()),
          throwsFormatException);
    }
  });
  test(
      'strict JSON rejects duplicate keys, prose-only, trailing data and nonfinite values',
      () {
    for (final text in [
      '{"function_calls":[],"function_calls":[]}',
      '{"a":{"x":1,"x":2}}',
      '{"a":1e999}',
      '{"a":01}',
      '{"function_calls":[]} trailing',
      'prose only'
    ]) {
      expect(() => decodeStrictQwenJson(text), throwsFormatException);
    }
    expect(
        decodeStrictQwenJson(
            'Here:\n```json\n{"function_calls":[{"name":"set_integer","arguments":{"field_id":"age","value":32}}]}\n```'),
        {
          'function_calls': [validCall]
        });
    expect(
        decodeStrictQwenJson(
            r'{"text":"escaped \" quote","value":[true,null,32]}'),
        {
          'text': 'escaped " quote',
          'value': [true, null, 32]
        });
  });
  test('missing function_calls and invalid confidence fail closed', () async {
    for (final text in [
      '{}',
      '{"calls":[]}',
      response([validCall], confidence: 2),
    ]) {
      await expectLater(
          Qwen3VlAdapter(inference: (_, __) async => Qwen3VlOutput(text))
              .interpret(request()),
          throwsFormatException);
    }
  });
  test('callback cancellation and late output ignored', () async {
    final held = Completer<Qwen3VlOutput>();
    CancellationToken? token;
    final adapter = Qwen3VlAdapter(inference: (_, c) {
      token = c;
      return held.future;
    });
    await expectLater(
        adapter.interpret(request(),
            options:
                const IntelligenceOptions(timeout: Duration(milliseconds: 10))),
        throwsA(isA<TimeoutException>()));
    expect(token!.isCancelled, true);
    held.complete(Qwen3VlOutput(response([validCall])));
  });
  for (final relevant in [true, false]) {
    test(
        'Qwen revision race ${relevant ? 'reruns relevant' : 'revalidates unrelated'}',
        () async {
      final form = FormIR(id: 'f', fields: [
        for (final id in ['age', 'other'])
          FormField(
              id: id,
              value: const IntegerDefinition(),
              semantics: FieldSemantics(label: id))
      ]);
      final bridge = LocalFormStateBridge(form: form, activeFieldId: 'age');
      final started = Completer<void>();
      final release = Completer<void>();
      var count = 0;
      final adapter = Qwen3VlAdapter(inference: (r, c) async {
        if (++count == 1) {
          started.complete();
          await release.future;
        }
        return Qwen3VlOutput(response([validCall]));
      });
      final runtime = FormAssistantRuntime(
          form: form,
          bridge: bridge,
          intelligence: adapter,
          contextBudget: ContextBudget(maxFields: 1));
      final pending = runtime.submit(const UserInput(text: 'Age thirty two'),
          trace: request().trace);
      await started.future;
      await bridge.apply(
          SetValueAction(
              fieldId: relevant ? 'age' : 'other',
              value: const IntegerValue(40)),
          context: const ApplyContext(
              expectedRevision: 0,
              interactionId: 'external',
              operationId: 'external',
              origin: ActionOrigin.user));
      release.complete();
      final result = await pending;
      expect(result.errorCode, isNull);
      expect(count, relevant ? 2 : 1);
      expect(result.snapshot.values['age'], const IntegerValue(32));
      await runtime.dispose();
      await bridge.dispose();
    });
  }
}

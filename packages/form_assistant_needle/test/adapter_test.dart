import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_needle/form_assistant_needle.dart';
import 'package:form_assistant_function_gemma/form_assistant_function_gemma.dart';
import 'package:form_assistant_needle/src/native.dart';
import 'package:form_assistant_needle/src/strict_json.dart';
import 'package:form_assistant_function_gemma/src/evaluation/benchmark.dart';
import 'package:test/test.dart';

String response(List<Object?> calls,
        {num confidence = .95,
        List<Object?> suppressed = const [],
        List<String> ungrounded = const []}) =>
    jsonEncode({
      'type': 'call',
      'success': true,
      'error': null,
      'error_code': null,
      'function_calls': calls,
      'suppressed_calls': suppressed,
      'confidence': confidence,
      'validation': {'ungrounded': ungrounded}
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
    test('Needle unchanged frozen fixture: ${fixture['id']}', () async {
      final context = SemanticContext.fromJson(jsonDecode(
          File('$root/contexts/${fixture['contextFixture']}')
              .readAsStringSync()));
      final raw = <String>[];
      final adapter = NeedleAdapter(inference: (r, c) async {
        final text =
            response(requireType<List<Object?>>(fixture['expectedCalls']));
        raw.add(text);
        return NeedleOutput(text);
      });
      final result = await evaluateAdapterCase(fixture, context,
          adapter: adapter,
          rawOutputs: raw,
          decodeEnvelopes: needleCallEnvelopes);
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
    final formatted = formatNeedleRequest(request());
    expect(formatted.systemFacts, contains('"label":"Age"'));
    expect(formatted.systemFacts, isNot(contains('fingerprint')));
    final tools = requireType<List<Object?>>(jsonDecode(formatted.toolsJson));
    expect(tools.map((t) => jsonObject(t)['name']),
        ['set_integer', 'clear_field']);
    expect(formatNeedleRequest(request(writable: false)).toolsJson, '[]');
    expect(formatted.input, 'Age thirty two');
  });
  test('confidence/provenance/revision remain outside canonical actions',
      () async {
    final result = await NeedleAdapter(
            inference: (_, __) async => NeedleOutput(response([validCall])))
        .interpret(request());
    expect(result.proposal.baseRevision, 17);
    expect(result.proposal.provenance.adapterId, 'needle3');
    expect(result.proposal.confidence, .95);
    expect(result.quality, QualityOutcome.accept);
    expect(result.proposal.actions.single.action,
        const SetValueAction(fieldId: 'age', value: IntegerValue(32)));
  });
  test(
      'suppressed or ungrounded calls never become mutations; confidence threshold unchanged',
      () async {
    for (final text in [
      response([], suppressed: [validCall], confidence: .05),
      response([validCall], confidence: .79),
      response([validCall], ungrounded: ['set_integer.value'])
    ]) {
      final result =
          await NeedleAdapter(inference: (_, __) async => NeedleOutput(text))
              .interpret(request());
      expect(result.quality, QualityOutcome.clarify);
      expect(result.proposal.actions.single.action,
          isA<RequestClarificationAction>());
    }
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
          NeedleAdapter(
                  inference: (_, __) async => NeedleOutput(response(calls)))
              .interpret(request()),
          throwsFormatException);
    }
  });
  test(
      'strict JSON rejects duplicate keys, prose, trailing data and nonfinite values',
      () {
    for (final text in [
      '{"value":32,"value":31}',
      '{"a":{"x":1,"x":2}}',
      '{"a":1e999}',
      '{"a":01}',
      '{"a":true} trailing',
      'prose {}'
    ]) {
      expect(() => decodeStrictNeedleJson(text), throwsFormatException);
    }
    expect(
        decodeStrictNeedleJson(
            r'{"text":"escaped \" quote","value":[true,null,32]}'),
        {
          'text': 'escaped " quote',
          'value': [true, null, 32]
        });
  });
  test(
      'engine errors/confidence range invalid; callback cancellation and late output ignored',
      () async {
    for (final text in [
      '{}',
      response([validCall], confidence: 2),
      jsonEncode({
        'type': 'error',
        'success': false,
        'error': 'unavailable',
        'function_calls': <Object?>[]
      })
    ]) {
      await expectLater(
          NeedleAdapter(inference: (_, __) async => NeedleOutput(text))
              .interpret(request()),
          throwsFormatException);
    }
    final held = Completer<NeedleOutput>();
    CancellationToken? token;
    final adapter = NeedleAdapter(inference: (_, c) {
      token = c;
      return held.future;
    });
    await expectLater(
        adapter.interpret(request(),
            options:
                const IntelligenceOptions(timeout: Duration(milliseconds: 10))),
        throwsA(isA<TimeoutException>()));
    expect(token!.isCancelled, true);
    held.complete(NeedleOutput(response([validCall])));
  });
  for (final relevant in [true, false]) {
    test(
        'Needle revision race ${relevant ? 'reruns relevant' : 'revalidates unrelated'}',
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
      final adapter = NeedleAdapter(inference: (r, c) async {
        if (++count == 1) {
          started.complete();
          await release.future;
        }
        return NeedleOutput(response([validCall]));
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

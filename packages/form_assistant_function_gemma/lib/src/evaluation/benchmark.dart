import 'package:form_assistant_core/form_assistant_core.dart';
import '../../form_assistant_function_gemma.dart';
import '../tools/parser.dart';
import '../tools/protocol.dart';
import '../tools/mapper.dart';
import '../tools/validator.dart';

const failureTaxonomy = [
  'CONTEXT_SELECTION',
  'CONTEXT_FORMATTING',
  'FIELD_SELECTION',
  'VALUE_EXTRACTION',
  'TYPE_ERROR',
  'OPTION_MAPPING',
  'MULTI_CHOICE_STATE',
  'NEGATION',
  'REFERENCE_RESOLUTION',
  'MODEL_HALLUCINATION',
  'TOOL_FORMAT',
  'AMBIGUITY_POLICY',
  'CONSTRAINT_REJECTION_EXPECTED',
  'RUNTIME_VALIDATION',
  'UNKNOWN'
];
List<Object?> normalizedCalls(List<FunctionGemmaToolCall> calls) {
  final result = calls
      .map((c) => <String, Object?>{
            'name': c.name,
            'arguments': {
              ...c.arguments,
              if (c.name == 'set_multi_choice')
                'value': canonicalStrings(stringList(c.arguments['value']))
            }
          })
      .toList();
  result
      .sort((a, b) => semanticFingerprint(a).compareTo(semanticFingerprint(b)));
  return result;
}

String primaryFailure(String category,
    {required bool malformed,
    required bool hallucinated,
    required bool fieldCorrect,
    required bool exact,
    required bool commitCorrect,
    required bool expectedConstraint}) {
  if (hallucinated) return 'MODEL_HALLUCINATION';
  if (malformed) return 'TOOL_FORMAT';
  if (!fieldCorrect) return 'FIELD_SELECTION';
  if (!exact) {
    return switch (category) {
      'negation' => 'NEGATION',
      'reference' || 'correction' => 'REFERENCE_RESOLUTION',
      'choice' => 'OPTION_MAPPING',
      'multi_choice' => 'MULTI_CHOICE_STATE',
      'ambiguity' ||
      'out_of_context' ||
      'option_truncation' =>
        'AMBIGUITY_POLICY',
      _ => 'VALUE_EXTRACTION',
    };
  }
  if (!commitCorrect) return 'RUNTIME_VALIDATION';
  return expectedConstraint ? 'CONSTRAINT_REJECTION_EXPECTED' : 'UNKNOWN';
}

Future<Map<String, Object?>> evaluateExtractionCase(
    Map<String, Object?> fixture,
    SemanticContext context,
    LocalFunctionGemmaInference inference) async {
  final raw = <String>[];
  final adapter = FunctionGemmaAdapter(inference: (prompt, cancel) async {
    final output = await inference(prompt, cancel);
    raw.add(output.text);
    return output;
  });
  return evaluateAdapterCase(fixture, context,
      adapter: adapter,
      rawOutputs: raw,
      decodeEnvelopes: FunctionGemmaToolCallParser().parseEnvelopes,
      diagnostics: () => {
            'hits': adapter.schemaCache.hits,
            'misses': adapter.schemaCache.misses,
            'specializationMicroseconds':
                adapter.schemaCache.specializationMicroseconds,
            'preparationMicroseconds':
                adapter.schemaCache.preparationMicroseconds,
          });
}

/// Same frozen scoring/runtime path for any IntelligenceAdapter. No expectations
/// or normalization policies change when a model-native decoder is supplied.
Future<Map<String, Object?>> evaluateAdapterCase(
    Map<String, Object?> fixture, SemanticContext context,
    {required IntelligenceAdapter adapter,
    required List<String> rawOutputs,
    required List<Map<String, Object?>> Function(String) decodeEnvelopes,
    Map<String, Object?> Function()? diagnostics}) async {
  final id = requiredString(fixture, 'id');
  final category = requiredString(fixture, 'category');
  final expected = requireType<List<Object?>>(fixture['expectedCalls'])
      .map(FunctionGemmaToolCall.fromJson)
      .toList();
  final input = UserInput(text: requiredString(fixture, 'input'));
  final trace = TraceContext(
      interactionId: id,
      requestId: '$id/request',
      operationId: '$id/operation');
  final request = IntelligenceRequest(
      input: input,
      context: context,
      allowedActionTypes: ['set_value', 'clear_value'],
      trace: trace);
  final form = FormIR(
      id: context.formId, fields: context.fields.map((f) => f.field).toList());
  final bridge = LocalFormStateBridge(
      form: form,
      initialValues: context.values,
      activeFieldId: context.activeFieldId);
  final raw = rawOutputs;
  final runtime =
      FormAssistantRuntime(form: form, bridge: bridge, intelligence: adapter);
  final initial = bridge.snapshot;
  IntelligenceResult? interpretation;
  RuntimeInteractionResult? applied;
  String? error;
  final watch = Stopwatch()..start();
  try {
    interpretation = await adapter.interpret(request,
        options: const IntelligenceOptions(timeout: Duration(minutes: 2)));
    applied = await runtime.executeProposal(interpretation.proposal,
        input: input,
        trace: trace,
        basedOn: initial,
        contextFieldIds: context.fields.map((f) => f.id));
  } catch (e) {
    error = e.toString();
  }
  List<FunctionGemmaToolCall> calls = [];
  List<Map<String, Object?>> envelopes = [];
  var malformed = false;
  String? decodingError;
  try {
    envelopes = decodeEnvelopes(raw.single);
    calls = envelopes.map(FunctionGemmaToolCall.fromJson).toList();
  } catch (e) {
    malformed = true;
    decodingError = e.toString();
  }
  final ids = context.fields.map((f) => f.id).toSet();
  var hallucinatedField = false;
  var hallucinatedOption = false;
  for (final envelope in envelopes) {
    final args = jsonObject(envelope['arguments']);
    final fid = args['field_id'];
    if (fid is String && !ids.contains(fid)) hallucinatedField = true;
    if (envelope['name'] == 'set_choice' ||
        envelope['name'] == 'set_multi_choice') {
      final field = context.fields.where((f) => f.id == fid).firstOrNull;
      if (field != null) {
        final candidates = field.options.map((o) => o.id).toSet();
        final v = args['value'];
        final values = v is List<Object?> ? v : [v];
        if (values.any((v) => v is String && !candidates.contains(v))) {
          hallucinatedOption = true;
        }
      }
    }
  }
  final exact = !malformed &&
      jsonEquals(normalizedCalls(calls), normalizedCalls(expected));
  List<String> fields(List<FunctionGemmaToolCall> values) =>
      values.map((c) => requiredString(c.arguments, 'field_id')).toList()
        ..sort();
  final fieldCorrect =
      !malformed && jsonEquals(fields(calls), fields(expected));
  final constraint = fixture['constraintRejectionExpected'] == true;
  final expectedState = Map<String, FormValue>.of(context.values);
  if (!constraint) {
    for (final call in expected) {
      final action = mapFunctionGemmaCall(call);
      if (action is SetValueAction) {
        expectedState[action.fieldId] = action.value;
      }
      if (action is ClearValueAction) expectedState.remove(action.fieldId);
    }
  }
  final state = bridge.snapshot;
  final stateCorrect = jsonEquals(
      state.values.map((k, v) => MapEntry(k, v.toJson())),
      expectedState.map((k, v) => MapEntry(k, v.toJson())));
  final clarificationCorrect =
      (runtime.state.phase == RuntimePhase.awaitingClarification) ==
          fixture['expectedClarification'];
  final commitCorrect = stateCorrect &&
      clarificationCorrect &&
      error == null &&
      applied?.errorCode == null;
  final passed = exact && commitCorrect;
  // Hard accepted-output checks are independent of raw extraction quality.
  var safetyViolations = 0;
  final mutations = interpretation?.proposal.actions
          .where((a) => a.action is FormMutationAction)
          .toList() ??
      [];
  for (final proposed in mutations) {
    final action = proposed.action as FormMutationAction;
    final field =
        context.fields.where((f) => f.id == action.fieldId).firstOrNull;
    if (field == null || !field.writable) {
      safetyViolations++;
      continue;
    }
    if (action is SetValueAction) {
      try {
        final name = extractionToolTypes.entries
            .singleWhere((e) => e.value == action.value.toJson()['type'])
            .key;
        FunctionGemmaToolCallValidator().validate([
          FunctionGemmaToolCall(name: name, arguments: {
            'field_id': action.fieldId,
            'value': action.value.rawValue
          })
        ], context);
      } catch (_) {
        safetyViolations++;
      }
    }
  }
  final result = <String, Object?>{
    'id': id,
    'category': category,
    'input': input.text,
    'contextFingerprint': context.fingerprint,
    'expectedCalls': expected.map((c) => c.toJson()).toList(),
    'rawOutput': raw.isEmpty ? null : raw.single,
    'parsedEnvelopes': envelopes,
    'parsedCalls': calls.map((c) => c.toJson()).toList(),
    'decodingError': decodingError,
    'validationError': error,
    'quality': interpretation?.quality?.name,
    'qualityReason': interpretation?.qualityReason,
    'canonicalActions': interpretation?.proposal.actions
            .map((a) => a.action.toJson())
            .toList() ??
        [],
    'baseRevision': interpretation?.proposal.baseRevision,
    'initialRevision': initial.revision,
    'finalRevision': state.revision,
    'expectedValues': expectedState.map((k, v) => MapEntry(k, v.toJson())),
    'actualValues': state.values.map((k, v) => MapEntry(k, v.toJson())),
    'exactActionSet': exact,
    'fieldIdentification': fieldCorrect,
    'typedValueExact': exact,
    'stateCorrect': stateCorrect,
    'clarificationCorrect': clarificationCorrect,
    'commitCorrect': commitCorrect,
    'passed': passed,
    'malformedCall': malformed,
    'hallucinatedField': hallucinatedField,
    'hallucinatedOption': hallucinatedOption,
    'safetyViolations': safetyViolations,
    'constraintRejectionExpected': constraint,
    'unnecessaryNoAnswer': expected.isNotEmpty && calls.isEmpty,
    'unnecessaryClarification': fixture['expectedClarification'] != true &&
        interpretation?.quality == QualityOutcome.clarify,
    'failureCategory': passed
        ? null
        : primaryFailure(category,
            malformed: malformed,
            hallucinated: hallucinatedField || hallucinatedOption,
            fieldCorrect: fieldCorrect,
            exact: exact,
            commitCorrect: commitCorrect,
            expectedConstraint: constraint),
    'durationMs': watch.elapsedMilliseconds,
    'cache': diagnostics?.call() ?? const <String, Object?>{},
  };
  await runtime.dispose();
  await bridge.dispose();
  return result;
}

double? accuracy(List<Map<String, Object?>> cases,
    bool Function(Map<String, Object?>) predicate, String metric) {
  final selected = cases.where(predicate).toList();
  return selected.isEmpty
      ? null
      : selected.where((c) => c[metric] == true).length / selected.length;
}

Map<String, Object?> summarizeBenchmark(
    List<Map<String, Object?>> cases, Map<String, Object?> config) {
  bool category(Map<String, Object?> c, List<String> names) =>
      names.contains(c['category']);
  final metrics = <String, Object?>{
    'exactActionSet': accuracy(cases, (_) => true, 'exactActionSet'),
    'completeCase': accuracy(cases, (_) => true, 'passed'),
    'fieldIdentification': accuracy(cases, (_) => true, 'fieldIdentification'),
    'typedValueExact': accuracy(cases, (_) => true, 'typedValueExact'),
    'simpleExact': accuracy(
        cases,
        (c) => category(c, [
              'integer',
              'number',
              'boolean',
              'string',
              'date',
              'choice',
              'multi_choice',
              'clear'
            ]),
        'exactActionSet'),
    'booleanExact': accuracy(
        cases,
        (c) =>
            category(c, ['boolean', 'negation']) &&
            (c['expectedCalls'] as List<Object?>)
                .any((e) => jsonObject(e)['name'] == 'set_boolean'),
        'exactActionSet'),
    'numericTyped': accuracy(
        cases, (c) => category(c, ['integer', 'number']), 'typedValueExact'),
    'choiceCanonical': accuracy(
        cases,
        (c) => (c['expectedCalls'] as List<Object?>)
            .any((e) => jsonObject(e)['name'] == 'set_choice'),
        'exactActionSet'),
    'multiChoiceExact': accuracy(
        cases,
        (c) => (c['expectedCalls'] as List<Object?>)
            .any((e) => jsonObject(e)['name'] == 'set_multi_choice'),
        'exactActionSet'),
    'compoundExact': accuracy(
        cases,
        (c) => (c['expectedCalls'] as List<Object?>).length >= 2,
        'exactActionSet'),
    'correctionReferenceExact': accuracy(cases,
        (c) => category(c, ['correction', 'reference']), 'exactActionSet'),
    'hallucinatedFieldRate': accuracy(cases, (_) => true, 'hallucinatedField'),
    'hallucinatedOptionRate':
        accuracy(cases, (_) => true, 'hallucinatedOption'),
    'malformedCallRate': accuracy(cases, (_) => true, 'malformedCall'),
    'unnecessaryNoAnswerRate': accuracy(
        cases,
        (c) => (c['expectedCalls'] as List<Object?>).isNotEmpty,
        'unnecessaryNoAnswer'),
    'unnecessaryClarificationRate': accuracy(
        cases,
        (c) =>
            c['constraintRejectionExpected'] != true &&
            (c['expectedCalls'] as List<Object?>).isNotEmpty,
        'unnecessaryClarification'),
    'constraintExtraction': accuracy(cases,
        (c) => c['constraintRejectionExpected'] == true, 'exactActionSet'),
    'constraintCommitRejection': accuracy(cases,
        (c) => c['constraintRejectionExpected'] == true, 'commitCorrect'),
  };
  final checks = <String, bool>{};
  for (final name in [
    'simpleExact',
    'booleanExact',
    'numericTyped',
    'choiceCanonical',
    'multiChoiceExact',
    'compoundExact',
    'correctionReferenceExact'
  ]) {
    checks[name] = metrics[name] != null &&
        (metrics[name] as double) >= (config[name] as num);
  }
  for (final name in [
    'hallucinatedFieldRate',
    'hallucinatedOptionRate',
    'malformedCallRate'
  ]) {
    checks[name] = metrics[name] != null &&
        (metrics[name] as double) <= (config['${name}Max'] as num);
  }
  checks['criticalRegression'] = cases
              .where((c) =>
                  (c['id'] as String).startsWith('compound_age_consent_'))
              .length ==
          3 &&
      cases
          .where((c) => (c['id'] as String).startsWith('compound_age_consent_'))
          .every((c) => c['passed'] == true);
  checks['hardCorrectness'] = cases.every((c) => c['safetyViolations'] == 0);
  return {
    'metrics': metrics,
    'checks': checks,
    'qualityThresholdsPassed': checks.values.every((v) => v),
    'passed': cases.where((c) => c['passed'] == true).length,
    'total': cases.length
  };
}

String benchmarkCsv(List<Map<String, Object?>> cases) {
  String cell(Object? value) =>
      '"${(value?.toString() ?? '').replaceAll('"', '""')}"';
  const columns = [
    'id',
    'category',
    'exactActionSet',
    'fieldIdentification',
    'commitCorrect',
    'passed',
    'failureCategory',
    'durationMs'
  ];
  return '${columns.join(',')}\n${cases.map((c) => columns.map((k) => cell(c[k])).join(',')).join('\n')}\n';
}

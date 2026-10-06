import 'dart:convert';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/form_assistant_function_gemma.dart';
import 'package:form_assistant_function_gemma/src/format.dart';
import 'package:test/test.dart';
import 'strict_extraction_test.dart' show native, strictContext;

IntelligenceRequest extractionRequest() => IntelligenceRequest(
    input: const UserInput(text: 'Age thirty two, consent yes'),
    context: strictContext(),
    allowedActionTypes: [
      'set_value',
      'clear_value',
      'navigate',
      'request_clarification'
    ],
    trace: const TraceContext(
        interactionId: 'i', requestId: 'r', operationId: 'o'));
void main() {
  test('compact prompt deterministic; no workflow tools or diagnostics', () {
    final r = extractionRequest();
    final prompt = formatPrompt(r);
    expect(prompt, formatPrompt(r));
    for (final name in [
      'navigate',
      'request_clarification',
      'submit',
      'undo',
      'redo',
      'clear_value'
    ]) {
      expect(prompt, isNot(contains('declaration:$name')));
    }
    expect(prompt, contains('declaration:clear_field'));
    expect(prompt, isNot(contains('fingerprint')));
    expect(prompt, isNot(contains('selectionReasons')));
    expect(prompt, contains('Age thirty two, consent yes'));
    expect(const FunctionGemmaContextFormatter().format(r.context).length,
        lessThanOrEqualTo(3072));
    expect(
        () => const FunctionGemmaContextFormatter(maxContextCharacters: 10)
            .format(r.context),
        throwsFormatException);
  });
  test('native compound extraction becomes canonical JSON proposal', () async {
    final adapter = FunctionGemmaAdapter(
        inference: (prompt, token) async => FunctionGemmaOutput(native(
                'set_integer', 'field_id:<escape>age<escape>,value:32') +
            native(
                'set_boolean', 'field_id:<escape>consent<escape>,value:true')));
    final output = await adapter.interpretJson(extractionRequest());
    final j = jsonDecode(jsonEncode(output)) as Map<String, dynamic>;
    final proposal = j['proposal'] as Map<String, dynamic>;
    expect(proposal['baseRevision'], 17);
    expect(proposal['actions'], hasLength(2));
    expect(j['quality'], 'accept');
  });
  test('workflow/prose/malformed output is not repaired or partially accepted',
      () async {
    for (final output in [
      native('navigate', 'target:<escape>next<escape>'),
      'I cannot assist.',
      native('set_integer', 'field_id:<escape>age<escape>,value:32') +
          ' trailing'
    ]) {
      final adapter = FunctionGemmaAdapter(
          inference: (_, __) async => FunctionGemmaOutput(output));
      await expectLater(
          adapter.interpret(extractionRequest()), throwsFormatException);
    }
  });
  test(
      'compact context includes current selections and canonical option aliases only',
      () {
    final c = SemanticContext(
        formId: 'f',
        revision: 0,
        activeFieldId: 'tech',
        recentFieldIds: [
          'tech'
        ],
        fields: [
          FormFieldContext(
              field: FormField(
                  id: 'tech',
                  value: const ChoiceDefinition(multiple: true),
                  semantics: FieldSemantics(
                      label: 'Technologies', aliases: ['languages']),
                  options: [
                    FormOption(
                        id: 'java',
                        label: 'Java',
                        aliases: ['JVM'],
                        extensions: {'raw:source': 'SECRET'})
                  ],
                  extensions: {
                    'raw:source': 'SECRET'
                  }),
              currentValue: MultiChoiceValue(['java']))
        ]);
    final text = const FunctionGemmaContextFormatter().format(c);
    expect(text, contains('"current":["java"]'));
    expect(text, contains('JVM'));
    expect(text, isNot(contains('SECRET')));
  });
}

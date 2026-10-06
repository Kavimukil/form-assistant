import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/schema_cache.dart';
import 'package:form_assistant_function_gemma/src/format.dart';
import 'package:test/test.dart';

SemanticContext cacheContext(
        {int revision = 0,
        int current = 31,
        String active = 'age',
        String label = 'Age',
        String option = 'fall',
        bool writable = true,
        String locale = 'en',
        bool truncated = false,
        bool extra = false,
        ValueDefinition type = const IntegerDefinition()}) =>
    SemanticContext(
        formId: 'f',
        revision: revision,
        activeFieldId: active,
        locale: locale,
        fields: [
          FormFieldContext(
              field: FormField(
                  id: 'age',
                  value: type,
                  semantics: FieldSemantics(label: label)),
              currentValue: IntegerValue(current),
              writable: writable),
          FormFieldContext(
              field: FormField(
                  id: 'promotion',
                  value: const ChoiceDefinition(multiple: false),
                  semantics: FieldSemantics(label: 'Promotion'),
                  options: [
                    FormOption(id: option, label: label, aliases: [label])
                  ]),
              optionsTruncated: truncated),
          if (extra)
            FormFieldContext(
                field: FormField(
                    id: 'name',
                    value: const StringDefinition(),
                    semantics: FieldSemantics(label: 'Name'))),
        ]);
void main() {
  test(
      'cache hits exclude state, labels and active field; prepared prompts remain exact',
      () {
    final cache = FunctionGemmaSchemaCache();
    final variants = [
      cacheContext(),
      cacheContext(revision: 1),
      cacheContext(current: 32),
      cacheContext(active: 'promotion'),
      cacheContext(label: 'Years'),
      cacheContext(truncated: true)
    ];
    for (final c in variants) {
      final prepared = cache.prepare(c, adapterVersion: '0.2.0');
      final r = IntelligenceRequest(
          input: const UserInput(text: 'hello'),
          context: c,
          allowedActionTypes: ['set_value', 'clear_value'],
          trace: const TraceContext(
              interactionId: 'i', requestId: 'r', operationId: 'o'));
      expect(
          formatPrompt(r,
              tools: prepared.tools,
              preparedDeclarations: prepared.declarations),
          formatPrompt(r));
    }
    expect(cache.hits, 5);
    expect(cache.misses, 1);
  });
  test(
      'cache misses track all schema/version/locale changes and LRU is bounded',
      () {
    final cache = FunctionGemmaSchemaCache(capacity: 2);
    for (final c in [
      cacheContext(),
      cacheContext(option: 'spring'),
      cacheContext(writable: false),
      cacheContext(locale: 'fr'),
      cacheContext(extra: true),
      cacheContext(type: const NumberDefinition())
    ]) {
      cache.prepare(c, adapterVersion: '0.2.0');
    }
    expect(cache.misses, 6);
    expect(cache.length, 2);
    cache.prepare(cacheContext(type: const NumberDefinition()),
        adapterVersion: '0.3.0');
    cache.prepare(cacheContext(type: const NumberDefinition()),
        adapterVersion: '0.3.0', protocolVersion: '2.0');
    cache.prepare(cacheContext(type: const NumberDefinition()),
        adapterVersion: '0.3.0', protocolVersion: '2.0', builderVersion: '2.0');
    expect(cache.misses, 9);
    expect(cache.length, 2);
    expect(cache.specializationMicroseconds, greaterThanOrEqualTo(0));
    expect(cache.preparationMicroseconds, greaterThanOrEqualTo(0));
    expect(() => FunctionGemmaSchemaCache(capacity: 0), throwsArgumentError);
  });
}

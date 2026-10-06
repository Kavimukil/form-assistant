import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/tools/parser.dart';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';
import 'package:form_assistant_function_gemma/src/tools/validator.dart';
import 'package:test/test.dart';

String native(String name, String args) =>
    '<start_function_call>call:$name{$args}<end_function_call>';
SemanticContext strictContext() =>
    SemanticContext(formId: 'f', revision: 17, fields: [
      for (final entry in {
        'age': const IntegerDefinition(),
        'weight': const NumberDefinition(),
        'consent': const BooleanDefinition(),
        'date': const DateDefinition(),
        'name': const StringDefinition(),
        'promotion': const ChoiceDefinition(multiple: false),
        'tech': const ChoiceDefinition(multiple: true),
        'locked': const StringDefinition()
      }.entries)
        FormFieldContext(
            field: FormField(
                id: entry.key,
                value: entry.value,
                semantics: FieldSemantics(label: entry.key),
                options: entry.value is ChoiceDefinition
                    ? [
                        FormOption(id: 'fall', label: 'Autumn'),
                        FormOption(id: 'java', label: 'Java')
                      ]
                    : null),
            writable: entry.key != 'locked'),
    ]);
void main() {
  final parser = FunctionGemmaToolCallParser();
  final validator = FunctionGemmaToolCallValidator();
  test('no-coercion malformed/context matrix', () {
    final bad = [
      native('set_integer',
          'field_id:<escape>age<escape>,value:<escape>32<escape>'),
      native('set_integer', 'field_id:<escape>age<escape>,value:32.5'),
      native('set_number',
          'field_id:<escape>weight<escape>,value:<escape>72.5<escape>'),
      native('set_number', 'field_id:<escape>weight<escape>,value:NaN'),
      native('set_number', 'field_id:<escape>weight<escape>,value:Infinity'),
      native('set_number', 'field_id:<escape>weight<escape>,value:1e999'),
      native('set_boolean',
          'field_id:<escape>consent<escape>,value:<escape>yes<escape>'),
      native('set_boolean', 'field_id:<escape>consent<escape>,value:1'),
      native('set_date',
          'field_id:<escape>date<escape>,value:<escape>05/10/2026<escape>'),
      native('set_date',
          'field_id:<escape>date<escape>,value:<escape>2026-02-30<escape>'),
      native('set_choice',
          'field_id:<escape>promotion<escape>,value:<escape>autumn<escape>'),
      native('set_multi_choice',
          'field_id:<escape>tech<escape>,value:<escape>java<escape>'),
      native('set_multi_choice',
          'field_id:<escape>tech<escape>,value:[<escape>java<escape>,<escape>java<escape>]'),
      native('set_multi_choice',
          'field_id:<escape>tech<escape>,value:[<escape>unknown<escape>]'),
      native('clear_field', 'field_id:<escape>age<escape>,value:1'),
      native('navigate', 'target:<escape>next<escape>'),
      native('set_integer', 'field_id:<escape>country<escape>,value:32'),
      native('set_string',
          'field_id:<escape>age<escape>,value:<escape>32<escape>'),
      native('set_string',
          'field_id:<escape>locked<escape>,value:<escape>x<escape>'),
      native('set_integer', 'field_id:<escape>age<escape>,value:32,extra:1'),
      native('set_integer', 'field_id:<escape>age<escape>'),
      native('set_integer', 'field_id:<escape>age<escape>,value:32,value:31'),
      'prose ' + native('clear_field', 'field_id:<escape>age<escape>'),
      native('clear_field', 'field_id:<escape>age<escape>') + ' trailing',
    ];
    for (final output in bad) {
      expect(() => validator.validate(parser.parse(output), strictContext()),
          throwsFormatException,
          reason: output);
    }
  });
  test('ordered independent calls, identical duplicates and conflicts', () {
    final first = FunctionGemmaToolCall(
        name: 'set_integer', arguments: {'field_id': 'age', 'value': 32});
    final second = FunctionGemmaToolCall(
        name: 'set_boolean', arguments: {'field_id': 'consent', 'value': true});
    final result = validator.validate([first, second, first], strictContext());
    expect(result.calls, [first, second]);
    expect(result.identicalDuplicates, 1);
    expect(
        () => validator.validate([
              first,
              FunctionGemmaToolCall(
                  name: 'set_integer',
                  arguments: {'field_id': 'age', 'value': 31})
            ], strictContext()),
        throwsFormatException);
    expect(
        () => validator.validate([first], strictContext(),
            allowedActionTypes: ['clear_value']),
        throwsFormatException);
  });
}

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/format.dart';
import 'package:form_assistant_function_gemma/src/tools/schema.dart';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';
import 'package:form_assistant_function_gemma/src/tools/validator.dart';
import 'package:test/test.dart';

void main() {
  test(
      'flat native enums retain candidates while strict validation correlates fields',
      () {
    final context = SemanticContext(formId: 'f', revision: 0, fields: [
      for (final e in {'promotion': 'fall', 'country': 'india'}.entries)
        FormFieldContext(
            field: FormField(
                id: e.key,
                value: const ChoiceDefinition(multiple: false),
                semantics: FieldSemantics(label: e.key),
                options: [FormOption(id: e.value, label: e.value)]))
    ]);
    final tools = FunctionGemmaToolSchemaBuilder().build(context);
    final choice = tools.definitions.singleWhere((d) => d.name == 'set_choice');
    final simple = simpleNativeParameters(choice.parameters);
    expect(simple.containsKey('oneOf'), false);
    expect(jsonObject(jsonObject(simple['properties'])['value'])['enum'],
        ['fall', 'india']);
    expect(choice.parameters.containsKey('oneOf'), true);
    expect(encodeNativeDeclarations(tools), isNot(contains('oneOf')));
    expect(encodeNativeDeclarations(tools, simpleChoiceSchema: false),
        contains('oneOf'));
    expect(
        () => FunctionGemmaToolCallValidator().validate([
              FunctionGemmaToolCall(
                  name: 'set_choice',
                  arguments: {'field_id': 'country', 'value': 'fall'})
            ], context),
        throwsFormatException);
  });
}

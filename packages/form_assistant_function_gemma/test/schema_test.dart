import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/tools/schema.dart';
import 'package:test/test.dart';

SemanticContext schemaContext(
        {bool writable = true,
        bool truncated = false,
        String option = 'fall',
        int revision = 1}) =>
    SemanticContext(formId: 'f', revision: revision, fields: [
      FormFieldContext(
          field: FormField(
              id: 'age',
              value: const IntegerDefinition(),
              semantics: FieldSemantics(label: 'Age')),
          writable: writable),
      FormFieldContext(
          field: FormField(
              id: 'promotion',
              value: const ChoiceDefinition(multiple: false),
              semantics: FieldSemantics(label: 'Promotion'),
              options: [FormOption(id: option, label: 'Autumn')]),
          optionsTruncated: truncated),
    ]);
void main() {
  final builder = FunctionGemmaToolSchemaBuilder();
  test('specialized schema matches production golden and omits absent types',
      () {
    final tools = builder.build(schemaContext());
    expect(
        tools.toJson(),
        jsonDecode(File('test/fixtures/specialized_schema.v1.json')
            .readAsStringSync()));
    expect(tools.definitions.map((t) => t.name),
        ['set_integer', 'set_choice', 'clear_field']);
    expect(
        builder
            .build(schemaContext(writable: false))
            .definitions
            .map((t) => t.name),
        ['set_choice', 'clear_field']);
  });
  test(
      'schema identity excludes revision/labels and includes permitted option IDs',
      () {
    expect(builder.build(schemaContext()).fingerprint,
        builder.build(schemaContext(revision: 99)).fingerprint);
    expect(builder.build(schemaContext()).fingerprint,
        isNot(builder.build(schemaContext(option: 'spring')).fingerprint));
    expect(builder.build(schemaContext()).fingerprint,
        builder.build(schemaContext(truncated: true)).fingerprint);
    expect(
        builder.build(schemaContext(),
            allowedActionTypes: ['navigate']).definitions,
        isEmpty);
  });
  test('disjoint choice branches and truncated candidates stay correlated', () {
    final fields = schemaContext(truncated: true).fields;
    final context = SemanticContext(formId: 'f', revision: 0, fields: [
      ...fields,
      FormFieldContext(
          field: FormField(
              id: 'country',
              value: const ChoiceDefinition(multiple: false),
              semantics: FieldSemantics(label: 'Country'),
              options: [FormOption(id: 'india', label: 'India')]))
    ]);
    final choice = builder
        .build(context)
        .definitions
        .singleWhere((d) => d.name == 'set_choice');
    final branches = choice.parameters['oneOf'] as List<Object?>;
    expect(branches, hasLength(2));
    expect(jsonEncode(branches), contains('india'));
    expect(jsonEncode(branches), contains('fall'));
    expect(builder.build(context).canonicalJson,
        builder.build(context).canonicalJson);
  });
}

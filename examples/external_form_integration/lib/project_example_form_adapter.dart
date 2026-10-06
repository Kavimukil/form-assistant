import 'package:form_assistant_core/form_assistant_core.dart';

import 'existing_form_store.dart';

/// Only compiles schema; no live state is read or owned by this adapter.
final class ProjectExampleFormAdapter
    implements FormAdapter<ExistingFormSchema> {
  @override
  String get id => 'project_example';
  @override
  String get version => '0.1.0';
  @override
  Future<FormIR> compile(ExistingFormSchema schema) async {
    if (schema.fields.map((f) => f.storageKey).toSet().length !=
            schema.fields.length ||
        schema.fields.map((f) => f.canonicalId).toSet().length !=
            schema.fields.length ||
        schema.fields
            .any((f) => f.canonicalId.isEmpty || f.storageKey.isEmpty)) {
      throw ArgumentError(
          'Source/canonical field IDs must be unique and nonempty');
    }
    for (final field in schema.fields) {
      if (field.options.map((o) => o.key).toSet().length !=
              field.options.length ||
          field.options.map((o) => o.canonicalId).toSet().length !=
              field.options.length ||
          field.options.any((o) => o.key.isEmpty || o.canonicalId.isEmpty)) {
        throw ArgumentError('Invalid source/canonical option IDs');
      }
    }
    return FormIR(id: schema.canonicalId, fields: [
      for (final field in schema.fields)
        FormField(
            id: field.canonicalId,
            value: switch (field.type) {
              ExistingFieldType.text => const StringDefinition(),
              ExistingFieldType.integer => const IntegerDefinition(),
              ExistingFieldType.decimal => const NumberDefinition(),
              ExistingFieldType.yesNo => const BooleanDefinition(),
              ExistingFieldType.date => const DateDefinition(),
              ExistingFieldType.select =>
                const ChoiceDefinition(multiple: false),
              ExistingFieldType.multiSelect =>
                const ChoiceDefinition(multiple: true),
            },
            semantics: FieldSemantics(label: field.label),
            constraints: FieldConstraints(
                required: field.required,
                min: field.min,
                max: field.max,
                minLength: field.minLength,
                maxLength: field.maxLength,
                pattern: field.pattern),
            options: field.options.isEmpty
                ? null
                : [
                    for (final option in field.options)
                      FormOption(id: option.canonicalId, label: option.label)
                  ])
    ]);
  }
}

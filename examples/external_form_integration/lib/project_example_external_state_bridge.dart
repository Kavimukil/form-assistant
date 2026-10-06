import 'package:form_assistant_core/form_assistant_core.dart';

import 'existing_form_store.dart';

/// Project-specific schema/state encodings stop at this external integration.
final class ProjectExampleExternalStateBridge
    extends ExternalStateBridge<ExistingFormState, ExistingMutation> {
  ProjectExampleExternalStateBridge(
      {required FormIR form,
      required ExistingFormSchema schema,
      required ExistingFormStore store,
      Duration acknowledgementTimeout = const Duration(seconds: 5),
      FormStateBridgeCapabilities? capabilities})
      : super(
            form: form,
            source: store,
            mapSnapshot: (state, revision) =>
                mapExistingSnapshot(schema, state, revision),
            mapMutation: (action, planned) =>
                mapExistingMutation(schema, action, planned),
            acknowledgementTimeout: acknowledgementTimeout,
            capabilities: capabilities,
            id: 'project_example_external');
}

FormStateSnapshot mapExistingSnapshot(
    ExistingFormSchema schema, ExistingFormState state, Revision revision) {
  final values = <FieldId, FormValue>{};
  for (final field in schema.fields) {
    if (!state.answers.containsKey(field.storageKey)) continue;
    final raw = state.answers[field.storageKey];
    String optionId(Object? key) => field.options
        .firstWhere((o) => o.key == requireType<String>(key),
            orElse: () =>
                throw const FormatException('Unknown source option key'))
        .canonicalId;
    values[field.canonicalId] = switch (field.type) {
      ExistingFieldType.text => StringValue(requireType<String>(raw)),
      ExistingFieldType.integer => IntegerValue(requireType<int>(raw)),
      ExistingFieldType.decimal =>
        NumberValue(requireType<num>(raw).toDouble()),
      ExistingFieldType.yesNo => switch (raw) {
          'Y' => const BooleanValue(true),
          'N' => const BooleanValue(false),
          _ => throw const FormatException('Expected Y/N source boolean')
        },
      ExistingFieldType.date => DateValue(requireType<String>(raw)),
      ExistingFieldType.select => ChoiceValue(optionId(raw)),
      ExistingFieldType.multiSelect =>
        MultiChoiceValue(requireType<List<Object?>>(raw).map(optionId)),
    };
  }
  final focused = state.focusedStorageKey;
  final active = focused == null
      ? null
      : schema.fields
          .firstWhere((f) => f.storageKey == focused,
              orElse: () =>
                  throw const FormatException('Unknown focused source key'))
          .canonicalId;
  return FormStateSnapshot(
      formId: schema.canonicalId,
      revision: revision,
      values: values,
      activeFieldId: active,
      lifecycle: state.lifecycle);
}

ExistingMutation mapExistingMutation(
    ExistingFormSchema schema, FormAction action, FormStateSnapshot planned) {
  ExistingField fieldFor(FieldId id) => schema.fields.firstWhere(
      (f) => f.canonicalId == id,
      orElse: () => throw const FormatException('Unknown canonical field ID'));
  if (action is NavigateAction) {
    return ExistingFocusMutation(planned.activeFieldId == null
        ? null
        : fieldFor(planned.activeFieldId!).storageKey);
  }
  if (action is ClearValueAction) {
    return ExistingAnswerMutation(
        storageKey: fieldFor(action.fieldId).storageKey, clear: true);
  }
  if (action is! SetValueAction) {
    throw const FormatException('Unsupported source mutation');
  }
  final field = fieldFor(action.fieldId);
  String sourceKey(String id) => field.options
      .firstWhere((o) => o.canonicalId == id,
          orElse: () =>
              throw const FormatException('Unknown canonical option ID'))
      .key;
  final raw = switch (action.value) {
    StringValue(:final value) => value,
    IntegerValue(:final value) => value,
    NumberValue(:final value) => value,
    BooleanValue(:final value) => value ? 'Y' : 'N',
    DateValue(:final value) => value,
    ChoiceValue(:final optionId) => sourceKey(optionId),
    MultiChoiceValue(:final optionIds) => optionIds.map(sourceKey).toList(),
  };
  return ExistingAnswerMutation(storageKey: field.storageKey, value: raw);
}

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_external_example/existing_form_store.dart';
import 'package:form_assistant_external_example/project_example_form_adapter.dart';
import 'package:form_assistant_external_example/project_example_external_state_bridge.dart';

Future<void> main() async {
  final schema = ExistingFormSchema(canonicalId: 'profile', fields: [
    ExistingField(
        storageKey: 'AGE',
        canonicalId: 'age',
        label: 'Age',
        type: ExistingFieldType.integer,
        min: 0),
    ExistingField(
        storageKey: 'CONSENT_YN',
        canonicalId: 'consent',
        label: 'Consent',
        type: ExistingFieldType.yesNo),
  ]);
  final store =
      ExistingFormStore(initialState: ExistingFormState(answers: {'AGE': 30}));
  final form = await ProjectExampleFormAdapter().compile(schema);
  final bridge = ProjectExampleExternalStateBridge(
      form: form, schema: schema, store: store);
  final subscription = bridge.events.listen((event) {
    if (event is StateChanged) {
      print('revision ${event.revision}: ${event.origin.name}');
    }
  });
  await bridge.apply(
      const SetValueAction(fieldId: 'consent', value: BooleanValue(true)),
      context: ApplyContext(
          expectedRevision: bridge.snapshot.revision,
          interactionId: 'interaction-1',
          operationId: 'operation-1',
          origin: ActionOrigin.user));
  print('Existing store: ${store.snapshot.state.answers}'); // CONSENT_YN: Y
  store.manualSet('AGE', 31); // Existing manual form remains authoritative.
  print(
      'Canonical projection: ${FormStateSnapshotCodec.encode(bridge.snapshot)}');
  await bridge.dispose();
  await subscription.cancel();
  store.manualSet(
      'AGE', 32); // Store remains usable after removing the assistant.
  await store.dispose();
}

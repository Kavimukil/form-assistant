import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

FormIR _form() => FormIR(id: 'form', fields: [
      FormField(
          id: 'consent',
          value: const BooleanDefinition(),
          semantics: FieldSemantics(label: 'Consent'),
          constraints: FieldConstraints(required: true)),
      FormField(
          id: 'age',
          value: const IntegerDefinition(),
          semantics: FieldSemantics(label: 'Age'),
          constraints: FieldConstraints(required: true)),
    ]);

NativeForm _native() => NativeForm(
    form: _form(),
    rules: const [
      FieldVisibilityRule(
          fieldId: 'age', whenFieldId: 'consent', equals: BooleanValue(true))
    ],
    workflow: FormWorkflow(const [
      ['consent'],
      ['age']
    ]));

TraceContext _trace(String id) => TraceContext(
    interactionId: 'interaction',
    requestId: 'request-$id',
    operationId: 'operation-$id');

void main() {
  test('workflow and visibility rules reject an incomplete definition', () {
    expect(
        () => NativeForm(
            form: _form(),
            workflow: FormWorkflow(const [
              ['consent']
            ])),
        throwsArgumentError);
    expect(
        () => NativeForm(form: _form(), rules: const [
              FieldVisibilityRule(
                  fieldId: 'age', whenFieldId: 'age', equals: IntegerValue(1))
            ]),
        throwsArgumentError);
  });

  test('projection hides a field until its rule matches, then advances', () {
    final native = _native();
    final hidden = native.project(FormStateSnapshot(
        formId: 'form',
        revision: 0,
        lifecycle: FormLifecycle.active,
        values: const {}));
    expect(hidden.stepIndex, 0);
    expect(hidden.currentFields.map((field) => field.id), ['consent']);

    final shown = native.project(FormStateSnapshot(
        formId: 'form',
        revision: 1,
        lifecycle: FormLifecycle.active,
        values: const {'consent': BooleanValue(true)}));
    expect(shown.stepIndex, 1);
    expect(shown.currentFields.map((field) => field.id), ['age']);
    expect(
        shown.fields.firstWhere((field) => field.id == 'age').visible, isTrue);
  });

  test('manual edit and speech share the action path and skip the model',
      () async {
    final native = _native();
    final bridge =
        LocalFormStateBridge(form: native.form, activeFieldId: 'consent');
    var calls = 0;
    final runtime = FormAssistantRuntime(
        form: native.form,
        bridge: bridge,
        visibilityRules: native.rules,
        intelligence: MockIntelligenceAdapter(handler: (_) {
          calls++;
          throw StateError('model');
        }));
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });

    final blocked = await runtime.commitNative(
        const SetValueAction(fieldId: 'age', value: IntegerValue(32)),
        trace: _trace('hidden'));
    expect(blocked.status, BatchStatus.rejected);
    expect(blocked.actions.single.validation.issues.single.code,
        'rule.field_hidden');
    expect(bridge.snapshot.revision, 0);
    expect(calls, 0);

    final spoken = await runtime.submit(const UserInput(text: 'yes'),
        trace: _trace('speech'));
    expect(spoken.status, BatchStatus.applied);
    expect(bridge.snapshot.values['consent'], const BooleanValue(true));
    expect(native.project(bridge.snapshot).stepIndex, 1);
    expect(calls, 0);

    final typed = await runtime.commitNative(
        const SetValueAction(fieldId: 'age', value: IntegerValue(32)),
        trace: _trace('typed'));
    expect(typed.status, BatchStatus.applied);
    expect(bridge.snapshot.values['age'], const IntegerValue(32));
    expect(bridge.snapshot.revision, 2);
    expect(calls, 0);

    final asked = await runtime.submit(
        const UserInput(text: 'please set age to forty'),
        trace: _trace('model'));
    expect(asked.errorCode, 'runtime.interpretation_failed');
    expect(calls, 1);
    expect(bridge.snapshot.values['age'], const IntegerValue(32));
  });
}

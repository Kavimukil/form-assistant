import 'package:flutter/material.dart' hide FormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_flutter/form_assistant_flutter.dart';

void main() {
  testWidgets('renderer follows the workflow and writes through the runtime',
      (tester) async {
    final form = FormIR(id: 'form', fields: [
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
    final native = NativeForm(
        form: form,
        rules: const [
          FieldVisibilityRule(
              fieldId: 'age',
              whenFieldId: 'consent',
              equals: BooleanValue(true))
        ],
        workflow: FormWorkflow(const [
          ['consent'],
          ['age']
        ]));
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'consent');
    var calls = 0;
    final runtime = FormAssistantRuntime(
        form: form,
        bridge: bridge,
        visibilityRules: native.rules,
        intelligence: MockIntelligenceAdapter(handler: (_) {
          calls++;
          throw StateError('model');
        }));
    addTearDown(() async {
      await _settle(runtime.dispose());
      await _settle(bridge.dispose());
    });

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NativeFormRenderer(
                form: native,
                bridge: bridge,
                onAction: (action) => runtime.commitNative(action,
                    trace: TraceContext(
                        interactionId: 'interaction',
                        requestId: 'request-${bridge.snapshot.revision}',
                        operationId:
                            'operation-${bridge.snapshot.revision}'))))));
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byKey(const Key('native_field_age')), findsNothing);
    expect(find.text('Step 1 of 2'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.byKey(const Key('native_field_age')), findsOneWidget);
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(calls, 0);

    await tester.enterText(find.byKey(const Key('native_field_age')), '32');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(bridge.snapshot.values['age'], const IntegerValue(32));
    expect(bridge.snapshot.revision, 2);
    expect(calls, 0);
  });
}

Future<void> _settle(Future<void> pending) async {
  final binding = WidgetsBinding.instance;
  if (binding is TestWidgetsFlutterBinding && binding.inTest) {
    binding.asyncBarrier();
  }
  await pending;
}

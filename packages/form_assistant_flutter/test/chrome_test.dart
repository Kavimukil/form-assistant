import 'package:flutter/material.dart' hide FormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_flutter/form_assistant_flutter.dart';

const trace = TraceContext(
    interactionId: 'interaction',
    requestId: 'request',
    operationId: 'operation');

FormStateSnapshot snapshot(int revision, int? age) => FormStateSnapshot(
    formId: 'form',
    revision: revision,
    lifecycle: FormLifecycle.active,
    values: {if (age != null) 'age': IntegerValue(age)});

FormAssistantController controllerFor() {
  final form = FormIR(id: 'form', fields: [
    FormField(
        id: 'age',
        value: const IntegerDefinition(),
        semantics: FieldSemantics(label: 'Age'))
  ]);
  final bridge = LocalFormStateBridge(form: form, activeFieldId: 'age');
  final runtime = FormAssistantRuntime(
      form: form,
      bridge: bridge,
      intelligence:
          MockIntelligenceAdapter(handler: (_) => throw StateError('unused')));
  final controller = FormAssistantController(runtime: runtime);
  addTearDown(() async {
    controller.dispose();
    await _settle(runtime.dispose());
    await _settle(bridge.dispose());
  });
  return controller;
}

/// Widget-test tearDown runs after the fake-async flush, so dispose futures
/// would otherwise never complete.
Future<void> _settle(Future<void> pending) async {
  final binding = WidgetsBinding.instance;
  if (binding is TestWidgetsFlutterBinding && binding.inTest) {
    binding.asyncBarrier();
  }
  await pending;
}

void main() {
  test('proposal is provisional until the bridge accepts it', () {
    final controller = controllerFor();
    const action = SetValueAction(fieldId: 'age', value: IntegerValue(32));
    final proposal = ActionProposal(
        id: 'proposal',
        baseRevision: 0,
        actions: const [ProposedAction(id: 'action', action: action)],
        provenance: ActionProvenance(
            trace: trace, adapterId: 'mock', adapterVersion: '0.1.0'));
    controller
        .handleRuntimeEvent(ProposalReceived(proposal: proposal, trace: trace));
    expect(controller.highlightFor('age'), FieldHighlight.provisional);
    expect(controller.accentFor('age'), const Color(0xFFE65100));
    final committed = snapshot(1, 32);
    controller.handleRuntimeEvent(InteractionCompleted(RuntimeInteractionResult(
        proposal: proposal,
        trace: trace,
        actions: [
          RuntimeActionResult(
              proposedAction: proposal.actions.single,
              trace: trace,
              validation:
                  ActionValidationMetadata(status: ValidationStatus.valid),
              bridgeResult: ActionApplied(
                  action: action,
                  previousRevision: 0,
                  revision: 1,
                  snapshot: committed))
        ],
        snapshot: committed,
        status: BatchStatus.applied)));
    expect(controller.highlightFor('age'), FieldHighlight.accepted);
    expect(controller.accentFor('other'), isNull);
  });

  test('dismissing a clarification does not invent a form value', () {
    final controller = controllerFor();
    controller.handleRuntimeEvent(RuntimeStateChanged(
        state: RuntimeState(
            phase: RuntimePhase.awaitingClarification,
            clarifications: [
              RequestClarificationAction(
                  reason: ClarificationReason.ambiguous, detail: 'Which age?')
            ]),
        trace: trace));
    expect(controller.clarificationText, 'Which age?');
    controller.dismissClarification();
    expect(controller.clarificationText, isNull);
    expect(controller.highlightFor('age'), FieldHighlight.none);
  });

  testWidgets('chrome keeps the host field and does not add another',
      (tester) async {
    final controller = controllerFor();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssistantChrome(
                controller: controller,
                buildForm: (_) => const TextField(key: Key('host_field'))))));
    expect(find.byKey(VoiceControlBar.listenKey), findsOneWidget);
    expect(find.byKey(const Key('host_field')), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(ClarificationBanner.bannerKey), findsNothing);
  });

  testWidgets('partial transcript is presentation only', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: VoiceControlBar(
                listening: true, partialTranscript: 'five', onStop: () {}))));
    expect(find.byKey(VoiceControlBar.partialKey), findsOneWidget);
    expect(find.text('five'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}

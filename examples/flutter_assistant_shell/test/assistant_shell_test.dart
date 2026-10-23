import 'package:flutter/material.dart' hide FormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_assistant_shell/assistant_shell.dart';
import 'package:flutter_existing_form/existing_age_form.dart';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_external_example/existing_form_store.dart';
import 'package:form_assistant_flutter/form_assistant_flutter.dart';
import 'package:form_assistant_stt/form_assistant_stt.dart';

void main() {
  testWidgets('assistant chrome leaves manual editing on the existing field',
      (tester) async {
    final store = ExistingFormStore();
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
        intelligence: MockIntelligenceAdapter(
            handler: (_) => throw StateError('unused')));
    final voice = VoiceOrchestrator(
        runtime: runtime, stt: HostSTTAdapter(), interactionId: 'interaction');
    final controller = FormAssistantController(
        runtime: runtime,
        voice: voice,
        voiceConfig: (segmentId) =>
            STTSessionConfig(segmentId: segmentId, sampleRateHz: 16000));
    addTearDown(() async {
      controller.dispose();
      await _settle(voice.dispose());
      await _settle(runtime.dispose());
      await _settle(bridge.dispose());
      await _settle(store.dispose());
    });

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssistantShell(store: store, controller: controller))));
    await tester.tap(find.byKey(VoiceControlBar.listenKey));
    await tester.pump();
    final session = controller.activeSession! as HostSTTSession;
    session.emit(STTPartial(session.config.segmentId, text: 'five'));
    await tester.pump();
    expect(find.byKey(VoiceControlBar.partialKey), findsOneWidget);
    expect(find.text('five'), findsOneWidget);
    expect(store.snapshot.state.answers, isEmpty);

    await tester.enterText(find.byKey(ExistingAgeForm.fieldKey), '41');
    expect(store.snapshot.state.answers['AGE'], '41');
    expect(find.byType(TextFormField), findsOneWidget);
  });
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

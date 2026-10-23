import 'dart:async';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

FormField _age() => FormField(
    id: 'age',
    value: const IntegerDefinition(),
    semantics:
        FieldSemantics(label: 'Age', localizedLabels: const {'es': 'Edad'}),
    constraints: FieldConstraints(required: true));

FormField _consent() => FormField(
    id: 'consent',
    value: const BooleanDefinition(),
    semantics: FieldSemantics(label: 'Consent'));

FormField _tier() => FormField(
        id: 'tier',
        value: const ChoiceDefinition(multiple: false),
        semantics: FieldSemantics(label: 'Tier'),
        options: [
          FormOption(
              id: 'tier_basic',
              label: 'Basic',
              localizedLabels: const {'es': 'Básico'})
        ]);

FormIR _form() => FormIR(id: 'form', fields: [_consent(), _age(), _tier()]);

TraceContext _trace(String id) => TraceContext(
    interactionId: 'interaction',
    requestId: 'request-$id',
    operationId: 'operation-$id');

void main() {
  test('localized labels are optional and are not field identity', () {
    expect(FieldSemantics(label: 'Age').toJson().containsKey('localizedLabels'),
        isFalse);
    final semantics =
        FieldSemantics(label: 'Age', localizedLabels: const {'es_MX': 'Edad'});
    expect(semantics.labelFor('es-MX'), 'Edad');
    expect(semantics.labelFor('fr'), 'Age');
    expect(semantics.toJson()['localizedLabels'], {'es-mx': 'Edad'});
    final decoded = FieldSemantics.fromJson(semantics.toJson());
    expect(decoded, semantics);

    final form = FormIR(id: 'form', fields: [_age()]);
    final view = NativeForm(
            form: form,
            workflow: FormWorkflow(const [
              ['age']
            ]))
        .project(
            FormStateSnapshot(
                formId: 'form',
                revision: 0,
                lifecycle: FormLifecycle.active,
                values: const {}),
            locale: 'es');
    expect(view.fields.single.id, 'age');
    expect(view.fields.single.label, 'Edad');
    expect(
        NativeForm(
                form: form,
                workflow: FormWorkflow(const [
                  ['age']
                ]))
            .project(FormStateSnapshot(
                formId: 'form',
                revision: 0,
                lifecycle: FormLifecycle.active,
                values: const {}))
            .fields
            .single
            .label,
        'Age');
  });

  test('code-switch evaluation keeps the canonical action', () {
    final mixed = evaluateCodeSwitch('thirty dos', activeField: _age());
    expect(mixed.mixed, isTrue);
    expect(mixed.locales, ['en', 'es']);
    final action = mixed.result.actions.single as SetValueAction;
    expect(action.fieldId, 'age');
    expect(action.value, const IntegerValue(32));
    expect(action.toJson().containsKey('locale'), isFalse);

    final spanish = evaluateCodeSwitch('treinta y dos', activeField: _age());
    expect(spanish.mixed, isFalse);
    expect(spanish.locales, ['es']);
    expect((spanish.result.actions.single as SetValueAction).value,
        const IntegerValue(32));

    final yes = evaluateCodeSwitch('sí', activeField: _consent());
    expect(yes.mixed, isFalse);
    expect(yes.locales, ['es']);
    expect((yes.result.actions.single as SetValueAction).value,
        const BooleanValue(true));

    final english = evaluateCodeSwitch('thirty and two', activeField: _age());
    expect(english.result.route, InputRoute.needsIntelligence);
    expect(evaluateCodeSwitch('siguiente').result.actions.single,
        const NavigateAction(target: NextNavigationTarget()));
  });

  test('spanish and mixed speech commit the same actions as english', () async {
    final adapter = MockIntelligenceAdapter(handler: (_) {
      throw StateError('model');
    });
    final bridge = LocalFormStateBridge(form: _form(), activeFieldId: 'age');
    final runtime = FormAssistantRuntime(
        form: _form(), bridge: bridge, locale: 'es', intelligence: adapter);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });

    final five = await runtime.submit(const UserInput(text: 'five'),
        trace: _trace('five'));
    expect(five.status, BatchStatus.applied);
    expect(bridge.snapshot.values['age'], const IntegerValue(5));
    expect(adapter.requests, isEmpty);

    final seis = await runtime.submit(const UserInput(text: 'seis'),
        trace: _trace('seis'));
    expect(seis.status, BatchStatus.applied);
    expect(bridge.snapshot.values['age'], const IntegerValue(6));
    expect(adapter.requests, isEmpty);

    final mixed = await runtime.submit(const UserInput(text: 'thirty dos'),
        trace: _trace('mixed'));
    expect(mixed.status, BatchStatus.applied);
    expect(bridge.snapshot.values['age'], const IntegerValue(32));
    expect(
        mixed.actions.single.proposedAction.action
            .toJson()
            .containsKey('locale'),
        isFalse);
    expect(adapter.requests, isEmpty);

    final englishOnly = await runtime.submit(
        const UserInput(text: 'thirty and two'),
        trace: _trace('english-only'));
    expect(englishOnly.errorCode, 'runtime.interpretation_failed');
    expect(adapter.requests, hasLength(1));
    expect(bridge.snapshot.values['age'], const IntegerValue(32));
  });

  test('a localized option label writes the option id', () async {
    final adapter = MockIntelligenceAdapter(handler: (_) {
      throw StateError('model');
    });
    final bridge = LocalFormStateBridge(form: _form(), activeFieldId: 'tier');
    final runtime = FormAssistantRuntime(
        form: _form(), bridge: bridge, locale: 'es', intelligence: adapter);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });

    final spanish = await runtime.submit(const UserInput(text: 'básico'),
        trace: _trace('basic-es'));
    expect(spanish.status, BatchStatus.applied);
    expect(bridge.snapshot.values['tier'], ChoiceValue('tier_basic'));
    expect(adapter.requests, isEmpty);

    final englishLabel = await runtime.submit(const UserInput(text: 'basic'),
        trace: _trace('basic-en'));
    expect(englishLabel.errorCode, 'runtime.interpretation_failed');
    expect(adapter.requests, hasLength(1));
    expect(bridge.snapshot.values['tier'], ChoiceValue('tier_basic'));
  });

  test('locale is on the model context and a localized label can select it',
      () async {
    final adapter = MockIntelligenceAdapter(handler: (_) {
      throw StateError('model');
    });
    final bridge =
        LocalFormStateBridge(form: _form(), activeFieldId: 'consent');
    final runtime = FormAssistantRuntime(
        form: _form(), bridge: bridge, locale: 'en_IN', intelligence: adapter);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });

    final spoken =
        await runtime.submit(const UserInput(text: 'sí'), trace: _trace('si'));
    expect(spoken.status, BatchStatus.applied);
    expect(bridge.snapshot.values['consent'], const BooleanValue(true));
    expect(adapter.requests, isEmpty);

    final referred = await runtime.submit(const UserInput(text: 'edad'),
        trace: _trace('edad'), locale: 'es');
    expect(referred.errorCode, 'runtime.interpretation_failed');
    expect(adapter.requests.single.context.locale, 'es');
    expect(adapter.requests.single.context.fields.map((field) => field.id),
        contains('age'));
    expect(
        adapter.requests.single.context.toJson().toString(), contains('Edad'));
  });

  test('a final transcript uses the stt locale and a partial does not commit',
      () async {
    final adapter = MockIntelligenceAdapter(handler: (_) {
      throw StateError('model');
    });
    final bridge = LocalFormStateBridge(form: _form(), activeFieldId: 'age');
    final runtime = FormAssistantRuntime(
        form: _form(), bridge: bridge, intelligence: adapter);
    final voice = VoiceOrchestrator(
        runtime: runtime, stt: _FakeStt(), interactionId: 'interaction');
    addTearDown(() async {
      await voice.dispose();
      await runtime.dispose();
      await bridge.dispose();
    });

    final session = await voice.start(
        STTSessionConfig(segmentId: 's1', sampleRateHz: 16000, locale: 'es_MX'),
        trace: _trace('voice'));
    (session as _FakeSession).add(STTPartial('s1', text: 'cinco'));
    await Future<void>.value();
    expect(bridge.snapshot.revision, 0);

    final settled =
        voice.events.firstWhere((event) => event is VoiceFinalSettled);
    session.add(STTFinal('s1', text: 'cinco'));
    final first = await settled as VoiceFinalSettled;
    expect(first.result.status, BatchStatus.applied);
    expect(bridge.snapshot.values['age'], const IntegerValue(5));
    expect(adapter.requests, isEmpty);

    final again = await voice.start(
        STTSessionConfig(segmentId: 's2', sampleRateHz: 16000, locale: 'es_MX'),
        trace: TraceContext(
            interactionId: 'interaction',
            requestId: 'request-voice-2',
            operationId: 'operation-voice-2'));
    final second = voice.events.firstWhere(
        (event) => event is VoiceFinalSettled && event.segmentId == 's2');
    (again as _FakeSession)
        .add(STTFinal('s2', text: 'please set age to forty'));
    await second;
    expect(adapter.requests.single.context.locale, 'es-mx');
    expect(bridge.snapshot.values['age'], const IntegerValue(5));
  });
}

final class _FakeSession implements STTSession {
  _FakeSession(this.config);
  final _events = StreamController<STTEvent>.broadcast(sync: true);
  @override
  final STTSessionConfig config;
  @override
  Stream<STTEvent> get events => _events.stream;
  void add(STTEvent event) => _events.add(event);
  @override
  Future<void> pushAudio(AudioChunk chunk) async {}
  @override
  Future<void> finish() async {}
  @override
  Future<void> cancel() async {}
}

final class _FakeStt implements STTAdapter {
  @override
  String get id => 'fake_stt';
  @override
  String get version => '0.1.0';
  @override
  STTCapabilities get capabilities => const STTCapabilities();
  @override
  Future<STTSession> createSession(STTSessionConfig config) async =>
      _FakeSession(config);
}

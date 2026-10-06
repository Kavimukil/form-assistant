import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

FormField field(ValueDefinition type,
        {List<FormOption>? options, FieldConstraints? constraints}) =>
    FormField(
        id: 'answer',
        value: type,
        semantics: FieldSemantics(label: 'Answer'),
        options: options,
        constraints: constraints);
InputRouterResult route(String text, FormField? active) =>
    const InputRouter().route(UserInput(text: text), activeField: active);
FormValue parsed(String text, FormField active) {
  final result = route(text, active);
  expect(result.route, InputRoute.deterministic, reason: text);
  return (result.actions.single as SetValueAction).value;
}

const trace = TraceContext(
    interactionId: 'i', requestId: 'r', operationId: 'o', segmentId: 's');
void main() {
  test('English boolean variants and explicit corrections', () {
    final f = field(const BooleanDefinition());
    for (final text in [
      'yes',
      ' Yes! ',
      'yeah',
      'yep',
      'true',
      'actually yes'
    ]) {
      expect(parsed(text, f), const BooleanValue(true));
    }
    for (final text in [
      'no',
      'NO?',
      'nope',
      'false',
      'correction no',
      'change my answer to no'
    ]) {
      expect(parsed(text, f), const BooleanValue(false));
    }
  });
  test('whole numeric digits and bounded English word grammar', () {
    final f = field(const IntegerDefinition());
    final cases = {
      '0': 0,
      '+12': 12,
      '-42': -42,
      'zero': 0,
      'nineteen': 19,
      'twenty-one': 21,
      'ninety nine': 99,
      'minus five': -5,
      'negative eleven': -11,
      'actually twenty two': 22,
      'change my answer to 40': 40
    };
    for (final entry in cases.entries) {
      expect(parsed(entry.key, f), IntegerValue(entry.value));
    }
    final n = field(const NumberDefinition());
    for (final text in ['1.25', 'one point two five']) {
      expect(parsed(text, n), NumberValue(1.25));
    }
    expect(parsed('minus zero point five', n), NumberValue(-0.5));
    expect(parsed('two point zero', f), const IntegerValue(2));
  });
  test('exact canonical choice ID, label and aliases; no label used as value',
      () {
    final f = field(const ChoiceDefinition(multiple: false), options: [
      FormOption(id: 'r', label: 'Red', aliases: ['scarlet']),
      FormOption(id: 'b', label: 'Blue')
    ]);
    for (final text in ['r', 'RED', 'scarlet', 'actually red']) {
      expect(parsed(text, f), ChoiceValue('r'));
    }
    final multi =
        field(const ChoiceDefinition(multiple: true), options: f.options);
    expect(parsed('blue', multi), MultiChoiceValue(['b']));
    expect(route('red and blue', multi).route, InputRoute.needsIntelligence);
  });
  test('fuzzy accepts only isolated long single-edit matches with margin', () {
    final f = field(const ChoiceDefinition(multiple: false), options: [
      FormOption(id: 'orange-id', label: 'Orange'),
      FormOption(id: 'purple-id', label: 'Purple')
    ]);
    expect(parsed('orang', f), ChoiceValue('orange-id'));
    expect(parsed('purplle', f), ChoiceValue('purple-id'));
    expect(route('oragne', f).route, InputRoute.needsIntelligence);
    expect(route('or', f).route, InputRoute.needsIntelligence);
    final near = field(const ChoiceDefinition(multiple: false), options: [
      FormOption(id: 'a', label: 'Stone'),
      FormOption(id: 'b', label: 'Stove')
    ]);
    expect(route('store', near).route, InputRoute.needsClarification);
    expect(route('stone', near).route, InputRoute.deterministic);
  });
  test(
      'colliding aliases and command/choice collisions clarify without mutations',
      () {
    final f = field(const ChoiceDefinition(multiple: false), options: [
      FormOption(id: 'a', label: 'One', aliases: ['same']),
      FormOption(id: 'b', label: 'Two', aliases: ['same'])
    ]);
    expect(route('same', f).route, InputRoute.needsClarification);
    expect(route('same', f).actions, isEmpty);
    for (final text in ['next', 'clear']) {
      final conflict = field(const ChoiceDefinition(multiple: false),
          options: [FormOption(id: 'x', label: text)]);
      expect(route(text, conflict).route, InputRoute.needsClarification);
    }
  });
  test('clear and navigation produce canonical actions only', () {
    final f = field(const BooleanDefinition());
    for (final text in [
      'clear',
      'clear this field',
      'erase my answer',
      'clear my answer'
    ]) {
      expect(route(text, f).actions.single,
          const ClearValueAction(fieldId: 'answer'));
    }
    for (final text in ['next', 'next field']) {
      expect(route(text, null).actions.single,
          const NavigateAction(target: NextNavigationTarget()));
    }
    for (final text in ['previous', 'previous field', 'go back']) {
      expect(route(text, f).actions.single,
          const NavigateAction(target: PreviousNavigationTarget()));
    }
    expect(route('yes', null).route, InputRoute.needsIntelligence);
  });
  test('invalid required/bounds and integer fractions never resolve', () {
    final f = field(const IntegerDefinition(),
        constraints: FieldConstraints(required: true, min: 0, max: 10));
    for (final text in ['11', 'minus one', 'clear']) {
      expect(route(text, f).route, InputRoute.needsClarification);
      expect(route(text, f).actions, isEmpty);
    }
    for (final text in [
      '1.5',
      'one point five',
      '9007199254740992',
      '1e3',
      'NaN',
      'Infinity'
    ]) {
      expect(route(text, f).route, InputRoute.needsIntelligence);
    }
  });
  test('adversarial utterances do not resolve across field types', () {
    final fields = [
      field(const BooleanDefinition()),
      field(const IntegerDefinition()),
      field(const NumberDefinition()),
      field(const StringDefinition()),
      field(const DateDefinition()),
      field(const ChoiceDefinition(multiple: false), options: [
        FormOption(id: 'r', label: 'Red'),
        FormOption(id: 'p', label: 'Purple')
      ])
    ];
    final inputs = [
      'yes or no',
      'yes and no',
      'not yes',
      'no, actually yes',
      'maybe',
      'I think yes',
      'do not clear',
      'next or previous',
      'clear and next',
      'red or purple',
      'purple and age twenty',
      'not purple',
      'one or two',
      'one two',
      'twenty ten',
      'one hundred',
      'about 12',
      '12 kg',
      '12/13',
      '1,000',
      '',
      'change the previous answer',
      'actually',
      'change my answer to yes or no',
      '2026-10-05'
    ];
    for (final f in fields) {
      for (final text in inputs) {
        final decision = route(text, f);
        expect(decision.route, isNot(InputRoute.deterministic),
            reason: '$text / ${f.value}');
        expect(decision.actions, isEmpty);
        expect(decision.reason, isNotEmpty);
      }
    }
  });
  test('result collections immutable', () {
    expect(() => route('yes', field(const BooleanDefinition())).actions.clear(),
        throwsUnsupportedError);
  });
  test(
      'runtime trivial answer bypasses intelligence and preserves trace/origin',
      () async {
    final form = FormIR(id: 'form', fields: [field(const IntegerDefinition())]);
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'answer');
    final mock = MockIntelligenceAdapter(
        handler: (_) => throw StateError('must not call'));
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: mock);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    final events = <RuntimeEvent>[];
    runtime.events.listen(events.add);
    final result =
        await runtime.submit(const UserInput(text: 'twenty'), trace: trace);
    expect(result.snapshot.values['answer'], const IntegerValue(20));
    expect(mock.requests, isEmpty);
    expect(result.proposal!.provenance.origin, ActionOrigin.deterministic);
    expect(events.whereType<InputRouted>().single.result.route,
        InputRoute.deterministic);
    final commit = events
        .whereType<RuntimeBridgeEvent>()
        .where((e) => e.event is StateChanged)
        .single;
    expect(commit.trace!.segmentId, 's');
    expect(commit.trace!.requestId, 'r');
    expect((commit.event as StateChanged).origin, ChangeOrigin.deterministic);
  });
  test('runtime ambiguous input clarifies without mutation or intelligence',
      () async {
    final form = FormIR(id: 'form', fields: [
      field(const ChoiceDefinition(multiple: false), options: [
        FormOption(id: 'a', label: 'Stone'),
        FormOption(id: 'b', label: 'Stove')
      ])
    ]);
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'answer');
    final mock = MockIntelligenceAdapter(
        handler: (_) => throw StateError('must not call'));
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: mock);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    await runtime.submit(const UserInput(text: 'store'), trace: trace);
    expect(bridge.snapshot.revision, 0);
    expect(bridge.snapshot.values, isEmpty);
    expect(mock.requests, isEmpty);
    expect(runtime.state.phase, RuntimePhase.awaitingClarification);
  });
  test('unsupported input falls through with no router mutation', () async {
    final form = FormIR(id: 'form', fields: [field(const BooleanDefinition())]);
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'answer');
    final mock = MockIntelligenceAdapter(
        handler: (request) => IntelligenceResult(
            proposal: ActionProposal(
                id: 'p',
                baseRevision: request.context.revision,
                actions: [],
                provenance: ActionProvenance(
                    trace: request.trace,
                    adapterId: 'mock',
                    adapterVersion: '0.1.0'))));
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: mock);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    await runtime.submit(const UserInput(text: 'yes or no'), trace: trace);
    expect(mock.requests, hasLength(1));
    expect(bridge.snapshot.revision, 0);
    expect(bridge.snapshot.values, isEmpty);
  });
  test('deterministic commit race reroutes original input without intelligence',
      () async {
    final form = FormIR(id: 'form', fields: [field(const IntegerDefinition())]);
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'answer');
    final mock = MockIntelligenceAdapter(
        handler: (_) => throw StateError('must not call'));
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: mock);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    var routes = 0;
    Future<ActionResult>? manual;
    runtime.events.listen((event) {
      if (event is InputRouted && ++routes == 1) {
        manual = bridge.apply(
            const SetValueAction(fieldId: 'answer', value: IntegerValue(5)),
            context: const ApplyContext(
                expectedRevision: 0,
                interactionId: 'manual',
                operationId: 'manual',
                origin: ActionOrigin.user));
      }
    });
    final result =
        await runtime.submit(const UserInput(text: 'twenty'), trace: trace);
    expect(await manual, isA<ActionApplied>());
    expect(routes, 2);
    expect(mock.requests, isEmpty);
    expect(result.snapshot.values['answer'], const IntegerValue(20));
    expect(result.snapshot.revision, 2);
    expect(result.trace.requestId, 'r/reinterpret/1');
  });
  test(
      'constraint-invalid deterministic answer requests invalid-value clarification',
      () async {
    final form = FormIR(id: 'form', fields: [
      field(const IntegerDefinition(), constraints: FieldConstraints(max: 10))
    ]);
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'answer');
    final mock = MockIntelligenceAdapter(
        handler: (_) => throw StateError('must not call'));
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: mock);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    await runtime.submit(const UserInput(text: 'twenty'), trace: trace);
    expect(bridge.snapshot.values, isEmpty);
    expect(bridge.snapshot.revision, 0);
    expect(mock.requests, isEmpty);
    expect(runtime.state.clarifications.single.reason,
        ClarificationReason.invalidValue);
  });
}

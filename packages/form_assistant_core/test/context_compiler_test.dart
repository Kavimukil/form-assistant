import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_core/src/runtime/context_compiler.dart';
import 'package:test/test.dart';

FormField field(String id,
        {String? label, String? description, List<FormOption>? options}) =>
    FormField(
        id: id,
        value: options == null
            ? const StringDefinition()
            : const ChoiceDefinition(multiple: false),
        semantics: FieldSemantics(label: label ?? id, description: description),
        options: options,
        extensions: {'source:raw': 'secret source store'});
FormIR form([int count = 20]) =>
    FormIR(id: 'form', fields: List.generate(count, (i) => field('f$i')));
FormStateSnapshot snapshot(FormIR f,
        {String? active = 'f19', Map<String, FormValue> values = const {}}) =>
    FormStateSnapshot(
        formId: f.id,
        revision: 0,
        activeFieldId: active,
        values: values,
        lifecycle: FormLifecycle.active);
CompiledContext compile(ContextCompiler c, FormStateSnapshot s,
        {String text = 'unrecognized',
        List<String> candidates = const [],
        List<String> deps = const [],
        List<String> recent = const [],
        List<InteractionHistoryEntry> history = const []}) =>
    c.compile(
        snapshot: s,
        input: UserInput(text: text),
        candidates: candidates,
        explicitDependencies: deps,
        recent: recent,
        history: history);
const trace =
    TraceContext(interactionId: 'i', requestId: 'r', operationId: 'o');
IntelligenceResult empty(IntelligenceRequest r) => IntelligenceResult(
    proposal: ActionProposal(
        id: 'p',
        baseRevision: r.context.revision,
        actions: [],
        provenance: ActionProvenance(
            trace: r.trace, adapterId: 'mock', adapterVersion: '0.1.0')));
void main() {
  test('5000 fields bounded; active retained; semantic extensions never leak',
      () {
    final f = form(5000);
    final c = ContextCompiler(
        form: f,
        budget: ContextBudget(
            maxFields: 7, maxChars: 4000, maxEstimatedTokens: 1000));
    final result = compile(c, snapshot(f, active: 'f4999'));
    expect(result.context.fields.length, 7);
    expect(result.context.fields.first.field.id, 'f4999');
    expect(result.diagnostics.chars, contextChars(result.context));
    expect(result.diagnostics.chars, lessThanOrEqualTo(4000));
    expect(result.diagnostics.estimatedTokens, lessThanOrEqualTo(1000));
    expect(
        result.context.fields.every((f) => f.field.extensions.isEmpty), isTrue);
    expect(
        jsonEncode(result.context.fields.map((f) => f.field.toJson()).toList()),
        isNot(contains('secret source')));
  });
  test(
      'dependencies transitive cyclic and exact references survive priority selection',
      () {
    final f = FormIR(id: 'form', fields: [
      field('current'),
      field('income', label: 'Annual income'),
      field('tax'),
      field('rate'),
      field('other')
    ]);
    final c = ContextCompiler(
        form: f,
        budget: ContextBudget(maxFields: 4),
        dependencies: {
          'income': ['tax'],
          'tax': ['rate'],
          'rate': ['tax']
        });
    final result = compile(c, snapshot(f, active: 'current'),
        text: 'use annual income to calculate', candidates: ['income']);
    expect(result.context.fields.map((f) => f.field.id),
        ['current', 'tax', 'rate', 'income']);
    expect(result.diagnostics.selectedReasons['tax'], 'dependency');
    expect(result.diagnostics.omittedReasons['other'], 'field_budget');
  });
  test(
      'previous reference picks accepted history field before recent and unanswered',
      () {
    final f = form();
    final result = compile(
        ContextCompiler(form: f, budget: ContextBudget(maxFields: 2)),
        snapshot(f),
        text: 'use the previous answer',
        recent: [
          'f3'
        ],
        history: [
          InteractionHistoryEntry(
              interactionId: 'old', text: 'hello', fieldIds: ['f8'])
        ]);
    expect(result.context.fields.map((f) => f.field.id), ['f19', 'f8']);
    expect(result.diagnostics.selectedReasons['f8'], 'previous_reference');
  });
  test(
      'recent fields precede unanswered and values are only selected canonical values',
      () {
    final f = form();
    final result = compile(
        ContextCompiler(form: f, budget: ContextBudget(maxFields: 3)),
        snapshot(f, values: {
          'f3': const StringValue('live'),
          'f4': const StringValue('hidden')
        }),
        recent: ['f3']);
    expect(result.context.fields.map((f) => f.field.id), ['f19', 'f3', 'f0']);
    expect(result.context.values, {'f3': const StringValue('live')});
  });
  test(
      'selection deterministic under duplicate/permuted hints and immutable diagnostics',
      () {
    final f = form();
    final c = ContextCompiler(form: f, budget: ContextBudget(maxFields: 4));
    final a = compile(c, snapshot(f), candidates: ['f2', 'f1', 'f2']);
    final b = compile(c, snapshot(f), candidates: ['f1', 'f2']);
    expect(a.context.fields.map((f) => f.field.id),
        b.context.fields.map((f) => f.field.id));
    expect(a.diagnostics.selectedReasons, b.diagnostics.selectedReasons);
    expect(a.diagnostics.chars, b.diagnostics.chars);
    expect(a.diagnostics.selectedReasons.clear, throwsUnsupportedError);
    expect(a.context.history.clear, throwsUnsupportedError);
  });
  test('hard token/char budgets include escaped values, options and history',
      () {
    final f = form();
    final s = snapshot(f, values: {'f0': StringValue('"\\\n' * 2000)});
    final result = compile(
        ContextCompiler(
            form: f,
            budget: ContextBudget(
                maxFields: 10, maxChars: 10000, maxEstimatedTokens: 180)),
        s,
        candidates: ['f0'],
        history: List.generate(
            10,
            (i) => InteractionHistoryEntry(
                interactionId: 'h$i', text: 'history' * 1000)));
    expect(result.diagnostics.chars, lessThanOrEqualTo(720));
    expect(result.context.fields.first.field.id, 'f19');
    expect(result.context.values.containsKey('f0'), isFalse);
    expect(result.diagnostics.omittedReasons['f0'], 'size_budget');
  });
  test(
      'oversized active or mandatory dependency fails closed; no silent truncation',
      () {
    final f = FormIR(
        id: 'form',
        fields: [field('active', description: 'large' * 1000), field('dep')]);
    final c = ContextCompiler(form: f, budget: ContextBudget(maxChars: 500));
    expect(() => compile(c, snapshot(f, active: 'active')),
        throwsA(isA<ContextBudgetExceeded>()));
    final small = form();
    final d = ContextCompiler(form: small, budget: ContextBudget(maxFields: 1));
    expect(() => compile(d, snapshot(small), deps: ['f1']),
        throwsA(isA<ContextBudgetExceeded>()));
  });
  test(
      'option extension metadata stripped; complete canonical options retained',
      () {
    final f = FormIR(id: 'form', fields: [
      field('choice', options: [
        FormOption(
            id: 'canonical',
            label: 'Visible',
            extensions: {'source:raw': 'SECRET'})
      ])
    ]);
    final result = compile(ContextCompiler(form: f, budget: ContextBudget()),
        snapshot(f, active: 'choice'));
    expect(result.context.fields.single.field.options!.single.id, 'canonical');
    expect(
        result.context.fields.single.field.options!.single.extensions, isEmpty);
  });
  test('history latest entries bounded by count/text and projected field IDs',
      () {
    final f = form();
    final result = compile(
        ContextCompiler(
            form: f,
            budget: ContextBudget(
                maxFields: 1, maxHistoryEntries: 2, maxHistoryEntryChars: 4)),
        snapshot(f),
        history: List.generate(
            4,
            (i) => InteractionHistoryEntry(
                interactionId: 'h$i',
                text: 'abcdefgh',
                fieldIds: ['f19', 'f8'])));
    expect(result.context.history.map((h) => h.interactionId), ['h2', 'h3']);
    expect(
        result.context.history
            .every((h) => h.text == 'abcd' && h.fieldIds.length == 1),
        isTrue);
  });
  test('invalid budgets/hints fail and algorithm stays out of barrel', () {
    expect(() => ContextBudget(maxFields: 0), throwsArgumentError);
    expect(() => ContextBudget(maxRecentFields: -1), throwsArgumentError);
    final f = form();
    expect(
        () => ContextCompiler(form: f, budget: ContextBudget(), dependencies: {
              'f0': ['missing']
            }),
        throwsArgumentError);
    expect(
        () => compile(
            ContextCompiler(form: f, budget: ContextBudget()), snapshot(f),
            candidates: ['missing']),
        throwsArgumentError);
    expect(File('lib/form_assistant_core.dart').readAsStringSync(),
        isNot(contains("export 'src/runtime/context_compiler.dart'")));
  });
  test('runtime history bounded and previous-field reference reaches mock',
      () async {
    final f = FormIR(id: 'form', fields: [
      FormField(
          id: 'age',
          value: const IntegerDefinition(),
          semantics: FieldSemantics(label: 'Age')),
      field('notes')
    ]);
    final bridge = LocalFormStateBridge(form: f, activeFieldId: 'age');
    final mock = MockIntelligenceAdapter(handler: empty);
    final runtime = FormAssistantRuntime(
        form: f,
        bridge: bridge,
        intelligence: mock,
        contextBudget: ContextBudget(maxHistoryEntries: 2));
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    await runtime.submit(const UserInput(text: 'twenty'), trace: trace);
    await bridge.apply(
        const NavigateAction(target: FieldNavigationTarget(fieldId: 'notes')),
        context: ApplyContext(
            expectedRevision: 1,
            interactionId: 'manual',
            operationId: 'manual',
            origin: ActionOrigin.user));
    await runtime.submit(const UserInput(text: 'use the previous answer'),
        trace: trace);
    final context = mock.requests.single.context;
    expect(context.values['age'], const IntegerValue(20));
    expect(context.history.single.text, 'twenty');
    expect(context.history.single.fieldIds, ['age']);
  });
  test('runtime budget failure prevents model invocation and mutation',
      () async {
    final f = FormIR(
        id: 'form', fields: [field('active', description: 'large' * 1000)]);
    final bridge = LocalFormStateBridge(form: f, activeFieldId: 'active');
    final mock = MockIntelligenceAdapter(handler: empty);
    final runtime = FormAssistantRuntime(
        form: f,
        bridge: bridge,
        intelligence: mock,
        contextBudget: ContextBudget(maxChars: 500));
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    final result = await runtime.submit(const UserInput(text: 'unsupported'),
        trace: trace);
    expect(result.errorCode, 'runtime.context_budget_exceeded');
    expect(mock.requests, isEmpty);
    expect(bridge.snapshot.revision, 0);
  });
  test(
      'selected dependency changing during inference recompiles fresh canonical context',
      () async {
    final f = form();
    final bridge = LocalFormStateBridge(form: f, activeFieldId: 'f19');
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final mock = MockIntelligenceAdapter(handler: (r) async {
      if (++calls == 1) {
        started.complete();
        await release.future;
      }
      return empty(r);
    });
    final runtime = FormAssistantRuntime(
        form: f,
        bridge: bridge,
        intelligence: mock,
        dependenciesByField: {
          'f19': ['f7']
        },
        contextBudget: ContextBudget(maxFields: 2));
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    final pending =
        runtime.submit(const UserInput(text: 'unsupported'), trace: trace);
    await started.future;
    await bridge.apply(
        const SetValueAction(fieldId: 'f7', value: StringValue('new')),
        context: const ApplyContext(
            expectedRevision: 0,
            interactionId: 'external',
            operationId: 'external',
            origin: ActionOrigin.user));
    release.complete();
    await pending;
    expect(calls, 2);
    expect(mock.requests.last.context.values['f7'], const StringValue('new'));
  });
  test('5000-field runtime passes only bounded compiled context to mock',
      () async {
    final f = form(5000);
    final bridge = LocalFormStateBridge(form: f, activeFieldId: 'f4999');
    final mock = MockIntelligenceAdapter(handler: empty);
    final runtime = FormAssistantRuntime(
        form: f,
        bridge: bridge,
        intelligence: mock,
        contextBudget: ContextBudget(maxFields: 5, maxChars: 2500));
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    final events = <ContextCompiled>[];
    runtime.events
        .where((e) => e is ContextCompiled)
        .cast<ContextCompiled>()
        .listen(events.add);
    await runtime.submit(const UserInput(text: 'unsupported'), trace: trace);
    final context = mock.requests.single.context;
    expect(context.fields, hasLength(5));
    expect(context.fields.first.field.id, 'f4999');
    expect(contextChars(context), lessThanOrEqualTo(2500));
    expect(events.single.diagnostics.chars, contextChars(context));
    expect(context.fields.every((f) => f.field.extensions.isEmpty), isTrue);
  });
}

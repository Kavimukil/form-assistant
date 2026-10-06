import 'dart:async';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

import 'external_integration_test.dart' as fixture;

const trace = TraceContext(
    interactionId: 'external-interaction',
    requestId: 'external-request',
    operationId: 'external-operation',
    segmentId: 'external-segment');

IntelligenceResult answer(IntelligenceRequest request, int value) =>
    IntelligenceResult(
        proposal: ActionProposal(
            id: 'external-proposal',
            baseRevision: request.context.revision,
            actions: [
              ProposedAction(id: 'age-action', action: fixture.age(value)),
              ProposedAction(
                  id: 'clarify-action',
                  action: RequestClarificationAction(
                      fieldIds: ['consent'],
                      reason: ClarificationReason.ambiguous))
            ],
            provenance: ActionProvenance(
                trace: request.trace,
                adapterId: 'mock',
                adapterVersion: '0.1.0')));

void main() {
  test('same headless runtime commits through external authoritative store',
      () async {
    final h = await fixture.harness();
    final runtime = FormAssistantRuntime(
        form: h.form,
        bridge: h.bridge,
        intelligence: MockIntelligenceAdapter(handler: (r) => answer(r, 30)));
    addTearDown(runtime.dispose);
    final events = <RuntimeEvent>[];
    runtime.events.listen(events.add);
    final result = await runtime.submit(
        const UserInput(text: 'age thirty; consent unclear'),
        trace: trace,
        contextFieldIds: ['age']);
    expect(result.status, BatchStatus.applied);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(30));
    expect(h.bridge.snapshot.revision, 1);
    expect(runtime.state.phase, RuntimePhase.awaitingClarification);
    final commits = events
        .whereType<RuntimeBridgeEvent>()
        .where((e) => e.event is StateChanged);
    expect(commits, hasLength(1));
    expect(commits.single.trace,
        trace.withProposal('external-proposal', actionId: 'age-action'));
    h.store.echoLatest();
    await fixture.pump();
    expect(h.bridge.snapshot.revision, 1);
    await runtime.dispose();
    h.store.manualSet('AGE', 40);
    await fixture.pump();
    expect(h.bridge.snapshot.values['age'], const IntegerValue(40));
  });

  test('manual external update during mock inference reinterprets fresh state',
      () async {
    final h = await fixture.harness();
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final mock = MockIntelligenceAdapter(handler: (request) async {
      calls++;
      if (calls == 1) {
        started.complete();
        await release.future;
        return answer(request, 20);
      }
      expect(request.context.values['age'], const IntegerValue(45));
      return answer(request, 46);
    });
    final runtime = FormAssistantRuntime(
        form: h.form, bridge: h.bridge, intelligence: mock);
    addTearDown(runtime.dispose);
    final result = runtime.submit(const UserInput(text: 'increase age'),
        trace: trace, contextFieldIds: ['age']);
    await started.future;
    h.store.manualSet('AGE', 45);
    await fixture.pump();
    release.complete();
    expect((await result).status, BatchStatus.applied);
    expect(calls, 2);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(46));
    expect(h.bridge.snapshot.revision, 2);
    expect(h.events.whereType<StateChanged>().map((e) => e.origin),
        [ChangeOrigin.external, ChangeOrigin.intelligence]);
  });
  test('deterministic answer bypasses mock and commits to external store',
      () async {
    final h = await fixture.harness();
    h.store.manualFocus('AGE');
    await fixture.pump();
    final mock = MockIntelligenceAdapter(
        handler: (_) => throw StateError('must not call'));
    final runtime = FormAssistantRuntime(
        form: h.form, bridge: h.bridge, intelligence: mock);
    addTearDown(runtime.dispose);
    final result =
        await runtime.submit(const UserInput(text: 'thirty'), trace: trace);
    expect(result.status, BatchStatus.applied);
    expect(mock.requests, isEmpty);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(30));
    expect(h.bridge.snapshot.revision, 1);
    expect(h.events.whereType<StateChanged>().single.origin,
        ChangeOrigin.deterministic);
    h.store.echoLatest();
    await fixture.pump();
    expect(h.bridge.snapshot.revision, 1);
  });
}

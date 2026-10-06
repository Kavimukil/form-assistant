import 'dart:async';
import 'dart:io';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

const trace = TraceContext(
    interactionId: 'interaction',
    requestId: 'request',
    operationId: 'operation',
    segmentId: 'segment');
const input = UserInput(text: 'original utterance', segmentId: 'segment');
FormIR runtimeForm() => FormIR(id: 'form', fields: [
      for (final id in ['a', 'b', 'c', 'd'])
        FormField(
            id: id,
            value: const IntegerDefinition(),
            semantics: FieldSemantics(label: id),
            constraints: FieldConstraints(min: 0, max: 10))
    ]);
ProposedAction set(String id, int value) => ProposedAction(
    id: 'set-$id',
    action: SetValueAction(fieldId: id, value: IntegerValue(value)));
IntelligenceResult response(
        IntelligenceRequest request, List<ProposedAction> actions,
        {String id = 'proposal'}) =>
    IntelligenceResult(
        proposal: ActionProposal(
            id: id,
            baseRevision: request.context.revision,
            actions: actions,
            provenance: ActionProvenance(
                trace: request.trace.withProposal(id),
                adapterId: 'mock',
                adapterVersion: '0.1.0')));

final class SpyBridge implements FormStateBridge {
  final FormStateBridge delegate;
  final FormStateBridgeCapabilities? overrideCapabilities;
  int applies = 0;
  int batches = 0;
  Future<void> Function()? beforeApply;
  SpyBridge(this.delegate, {this.overrideCapabilities});
  @override
  String get id => delegate.id;
  @override
  String get version => delegate.version;
  @override
  FormStateBridgeCapabilities get capabilities =>
      overrideCapabilities ?? delegate.capabilities;
  @override
  FormStateSnapshot get snapshot => delegate.snapshot;
  @override
  Stream<FormStateBridgeEvent> get events => delegate.events;
  @override
  Future<ActionResult> apply(FormAction action,
      {required ApplyContext context}) async {
    applies++;
    if (beforeApply != null) await beforeApply!();
    return delegate.apply(action, context: context);
  }

  @override
  Future<BatchActionResult> applyBatch(List<FormAction> actions,
      {required ApplyContext context,
      BatchApplyMode mode = BatchApplyMode.bestEffort}) {
    batches++;
    return delegate.applyBatch(actions, context: context, mode: mode);
  }

  @override
  Future<ActionResult> undo({required ApplyContext context}) =>
      delegate.undo(context: context);
  @override
  Future<ActionResult> redo({required ApplyContext context}) =>
      delegate.redo(context: context);
  @override
  Future<void> dispose() => delegate.dispose();
  Future<ActionResult> manual(FormAction action) => delegate.apply(action,
      context: ApplyContext(
          expectedRevision: snapshot.revision,
          interactionId: 'manual',
          operationId: 'manual-${snapshot.revision}',
          origin: ActionOrigin.user));
}

final class Harness {
  final SpyBridge bridge;
  final MockIntelligenceAdapter mock;
  final FormAssistantRuntime runtime;
  final List<RuntimeEvent> events = [];
  Harness(this.bridge, this.mock, this.runtime) {
    runtime.events.listen(events.add);
  }
}

Harness harness(
    FutureOr<IntelligenceResult> Function(IntelligenceRequest) handler,
    {FormStateBridgeCapabilities? caps,
    int retries = 2,
    int contextFields = 2}) {
  final form = runtimeForm();
  final bridge = SpyBridge(LocalFormStateBridge(form: form, activeFieldId: 'a'),
      overrideCapabilities: caps);
  final mock = MockIntelligenceAdapter(handler: handler);
  final runtime = FormAssistantRuntime(
      form: form,
      bridge: bridge,
      intelligence: mock,
      maxStaleRetries: retries,
      contextBudget: ContextBudget(maxFields: contextFields));
  addTearDown(() async {
    await runtime.dispose();
    await bridge.dispose();
  });
  return Harness(bridge, mock, runtime);
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  test(
      'mutation/navigation/control route correctly; state is separate and full trace reaches commits',
      () async {
    final clarification = RequestClarificationAction(
        fieldIds: ['c'], reason: ClarificationReason.ambiguous);
    final h = harness((request) => response(request, [
          set('a', 2),
          const ProposedAction(
              id: 'nav',
              action:
                  NavigateAction(target: FieldNavigationTarget(fieldId: 'b'))),
          ProposedAction(id: 'clarify', action: clarification)
        ]));
    final result = await h.runtime
        .submit(input, trace: trace, contextFieldIds: ['a', 'b', 'c']);
    expect(result.status, BatchStatus.applied);
    expect(result.snapshot.revision, 1);
    expect(result.snapshot.values['a'], const IntegerValue(2));
    expect(result.snapshot.activeFieldId, 'b');
    expect(h.bridge.applies, 2);
    expect(h.bridge.batches, 0);
    expect(h.runtime.state.phase, RuntimePhase.awaitingClarification);
    expect(h.runtime.state.clarifications, [clarification]);
    expect(
        () => h.runtime.state.clarifications.clear(), throwsUnsupportedError);
    expect(h.events.whereType<ClarificationRequested>().single.action,
        clarification);
    final commits = h.events
        .whereType<RuntimeBridgeEvent>()
        .where((e) => e.event is ActionCompleted)
        .toList();
    expect(commits.length, 2);
    expect(commits.map((e) => e.trace!.actionId), ['set-a', 'nav']);
    for (final event in commits) {
      expect(event.trace!.interactionId, 'interaction');
      expect(event.trace!.requestId, 'request');
      expect(event.trace!.operationId, 'operation');
      expect(event.trace!.proposalId, 'proposal');
      expect(event.trace!.segmentId, 'segment');
      final bridgeEvent = event.event as ActionCompleted;
      expect(bridgeEvent.operationId, event.trace!.operationId);
      expect(bridgeEvent.proposalId, 'proposal');
    }
    expect(
        h.events
            .whereType<RuntimeBridgeEvent>()
            .where((e) => e.event is StateChanged)
            .single
            .trace!
            .requestId,
        'request');
    expect(result.actions.clear, throwsUnsupportedError);
  });
  test(
      'mock multi-action utterance partially applies and requests clarification; supplied validation is not trusted',
      () async {
    final fakeValidation = ActionValidationMetadata(
        status: ValidationStatus.valid, validatedAgainstRevision: 999);
    final h = harness((request) => response(request, [
          set('a', 2),
          ProposedAction(
              id: 'bad',
              action:
                  const SetValueAction(fieldId: 'b', value: StringValue('bad')),
              validation: fakeValidation),
          ProposedAction(
              id: 'clarify',
              action: RequestClarificationAction(
                  fieldIds: ['b'], reason: ClarificationReason.invalidValue))
        ]));
    final result = await h.runtime.submit(input, trace: trace);
    expect(result.status, BatchStatus.partiallyApplied);
    expect(result.snapshot.values, {'a': const IntegerValue(2)});
    expect(result.snapshot.revision, 1);
    expect(result.actions[1].validation.status, ValidationStatus.invalid);
    expect(result.actions[1].validation.validatedAgainstRevision, 1);
    expect((result.actions[1].bridgeResult as ActionRejected).rejection.code,
        ActionRejectionCode.invalidValue);
    expect(h.bridge.applies, 1);
    expect(h.runtime.state.phase, RuntimePhase.awaitingClarification);
  });
  test(
      'capabilities reject writes/navigation before calling the bridge while clarification stays usable',
      () async {
    const caps = FormStateBridgeCapabilities(
        writable: false,
        supportsBatch: false,
        supportsAtomicBatch: false,
        supportsUndo: false,
        supportsRedo: false,
        supportsExternalChanges: false,
        supportsActiveField: true,
        supportsNavigation: false);
    final h = harness(
        (request) => response(request, [
              set('a', 2),
              const ProposedAction(
                  id: 'nav',
                  action: NavigateAction(target: NextNavigationTarget())),
              ProposedAction(
                  id: 'clarify',
                  action: RequestClarificationAction(
                      reason: ClarificationReason.ambiguous))
            ]),
        caps: caps);
    final result = await h.runtime.submit(input, trace: trace);
    expect(result.status, BatchStatus.partiallyApplied);
    expect((result.actions[0].bridgeResult as ActionRejected).rejection.code,
        ActionRejectionCode.readOnly);
    expect((result.actions[1].bridgeResult as ActionRejected).rejection.code,
        ActionRejectionCode.capabilityUnavailable);
    expect(h.bridge.applies, 0);
    expect(h.bridge.batches, 0);
    expect(h.bridge.snapshot.revision, 0);
  });
  test(
      'unknown mutation/navigation/clarification fields rejected by runtime validation',
      () async {
    final h = harness((request) => response(request, [
          set('missing', 2),
          const ProposedAction(
              id: 'nav',
              action: NavigateAction(
                  target: FieldNavigationTarget(fieldId: 'missing'))),
          ProposedAction(
              id: 'clarify',
              action: RequestClarificationAction(
                  fieldIds: ['missing'], reason: ClarificationReason.ambiguous))
        ]));
    final result = await h.runtime.submit(input, trace: trace);
    expect(result.status, BatchStatus.rejected);
    expect(h.bridge.applies, 0);
    expect(h.events.whereType<ClarificationRequested>(), isEmpty);
    for (final r in result.actions) {
      expect((r.bridgeResult as ActionRejected).rejection.code,
          ActionRejectionCode.unknownField);
    }
  });
  test(
      'atomic proposal uses one bridge transaction and preserves action trace ordering',
      () async {
    final h = harness((request) => response(request, [
          set('a', 2),
          set('b', 3),
          ProposedAction(
              id: 'clarify',
              action: RequestClarificationAction(
                  reason: ClarificationReason.ambiguous))
        ]));
    final result = await h.runtime
        .submit(input, trace: trace, mode: BatchApplyMode.atomic);
    expect(result.status, BatchStatus.applied);
    expect(result.snapshot.revision, 1);
    expect(h.bridge.applies, 0);
    expect(h.bridge.batches, 1);
    for (final r in result.actions.take(2)) {
      expect((r.bridgeResult as ActionApplied).revision, 1);
      expect(r.validation.validatedAgainstRevision, 0);
    }
    expect(
        h.events
            .whereType<RuntimeBridgeEvent>()
            .where((e) => e.event is ActionCompleted)
            .map((e) => e.trace!.actionId),
        ['set-a', 'set-b']);
    expect(
        h.events
            .whereType<RuntimeBridgeEvent>()
            .where((e) => e.event is BatchCompleted)
            .single
            .trace!
            .operationId,
        'operation');
  });
  test(
      'atomic validation failure rolls back all routing including clarification',
      () async {
    final h = harness((request) => response(request, [
          set('a', 2),
          set('b', 99),
          ProposedAction(
              id: 'clarify',
              action: RequestClarificationAction(
                  reason: ClarificationReason.ambiguous))
        ]));
    final result = await h.runtime
        .submit(input, trace: trace, mode: BatchApplyMode.atomic);
    expect(result.status, BatchStatus.rejected);
    expect(result.snapshot.revision, 0);
    expect(result.snapshot.values, isEmpty);
    expect(h.bridge.batches, 0);
    expect(h.events.whereType<ClarificationRequested>(), isEmpty);
    expect((result.actions.first.bridgeResult as ActionRejected).rejection.code,
        ActionRejectionCode.atomicBatchAborted);
  });
  test('atomic capability failure never silently downgrades', () async {
    const caps = FormStateBridgeCapabilities(
        writable: true,
        supportsBatch: true,
        supportsAtomicBatch: false,
        supportsUndo: false,
        supportsRedo: false,
        supportsExternalChanges: false,
        supportsActiveField: true,
        supportsNavigation: true);
    final h = harness(
        (request) => response(request, [set('a', 2), set('b', 3)]),
        caps: caps);
    final result = await h.runtime
        .submit(input, trace: trace, mode: BatchApplyMode.atomic);
    expect(result.status, BatchStatus.rejected);
    expect(h.bridge.batches, 0);
    expect(h.bridge.applies, 0);
    expect(h.bridge.snapshot.revision, 0);
  });
  test(
      'unrelated stale change revalidates against latest revision without reinterpreting',
      () async {
    final release = Completer<void>();
    final h = harness((request) async {
      await release.future;
      return response(request, [set('a', 2)]);
    });
    final pending = h.runtime.submit(input, trace: trace);
    await pump();
    await h.bridge
        .manual(const SetValueAction(fieldId: 'c', value: IntegerValue(7)));
    release.complete();
    final result = await pending;
    expect(result.status, BatchStatus.applied);
    expect(result.snapshot.revision, 2);
    expect(result.snapshot.values,
        {'a': const IntegerValue(2), 'c': const IntegerValue(7)});
    expect(h.mock.requests.length, 1);
    expect(h.events.whereType<ProposalRevalidated>().single.revision, 1);
    expect(result.actions.single.validation.validatedAgainstRevision, 1);
  });
  for (final changed in ['a', 'b', 'd']) {
    test(
        'relevant $changed change discards and reinterprets original input with latest values',
        () async {
      final release = Completer<void>();
      var calls = 0;
      final h = harness((request) async {
        if (calls++ == 0) await release.future;
        return response(request, [set('a', 5)], id: 'p-$calls');
      }, contextFields: 3);
      final pending = h.runtime.submit(input,
          trace: trace, contextFieldIds: ['b'], dependencyFieldIds: ['d']);
      await pump();
      await h.bridge.manual(
          SetValueAction(fieldId: changed, value: const IntegerValue(7)));
      release.complete();
      final result = await pending;
      expect(result.status, BatchStatus.applied);
      expect(h.mock.requests.length, 2);
      expect(h.events.whereType<ProposalDiscarded>().length, 1);
      expect(h.mock.requests.last.input, same(input));
      expect(
          h.mock.requests.last.context.values[changed], const IntegerValue(7));
      expect(h.mock.requests.last.trace.requestId, 'request/reinterpret/1');
      expect(result.trace.interactionId, 'interaction');
      expect(result.trace.segmentId, 'segment');
      expect(result.snapshot.values['a'], const IntegerValue(5));
    });
  }
  test(
      'focus-only context change triggers reinterpretation even with the same revision',
      () async {
    final release = Completer<void>();
    var calls = 0;
    final h = harness((request) async {
      if (calls++ == 0) await release.future;
      return response(request, [set('a', 2)], id: 'p-$calls');
    });
    final pending = h.runtime.submit(input, trace: trace);
    await pump();
    await h.bridge.manual(
        const NavigateAction(target: FieldNavigationTarget(fieldId: 'b')));
    expect(h.bridge.snapshot.revision, 0);
    release.complete();
    await pending;
    expect(h.mock.requests.length, 2);
    expect(h.mock.requests.last.context.activeFieldId, 'b');
  });
  test(
      'bridge catches race after runtime validation; bounded retry never force-writes',
      () async {
    final h =
        harness((request) => response(request, [set('a', 2)]), retries: 0);
    h.bridge.beforeApply = () async {
      h.bridge.beforeApply = null;
      await h.bridge
          .manual(const SetValueAction(fieldId: 'a', value: IntegerValue(7)));
    };
    final result = await h.runtime.submit(input, trace: trace);
    expect(result.status, BatchStatus.rejected);
    expect(result.errorCode, 'runtime.stale_retry_limit');
    expect(h.bridge.snapshot.values['a'], const IntegerValue(7));
    expect(
        (h.events.whereType<RuntimeActionCompleted>().single.result.bridgeResult
                as ActionRejected)
            .rejection
            .code,
        ActionRejectionCode.staleRevision);
  });
  test('commit race before any success safely reinterprets original input',
      () async {
    var calls = 0;
    final h = harness(
        (request) => response(request, [set('a', 2)], id: 'p-${++calls}'));
    h.bridge.beforeApply = () async {
      h.bridge.beforeApply = null;
      await h.bridge
          .manual(const SetValueAction(fieldId: 'a', value: IntegerValue(7)));
    };
    final result = await h.runtime.submit(input, trace: trace);
    expect(result.status, BatchStatus.applied);
    expect(calls, 2);
    expect(
        h.events.whereType<ProposalDiscarded>().single.reason, 'commit_race');
    expect(h.bridge.snapshot.values['a'], const IntegerValue(2));
  });
  test(
      'partial commit race stops remaining edits and clarifies without replaying completed actions',
      () async {
    final h =
        harness((request) => response(request, [set('a', 2), set('b', 3)]));
    h.runtime.events.listen((event) {
      if (event is RuntimeActionCompleted &&
          event.result.proposedAction.id == 'set-a') {
        h.bridge.beforeApply = () async {
          h.bridge.beforeApply = null;
          await h.bridge.manual(
              const SetValueAction(fieldId: 'b', value: IntegerValue(7)));
        };
      }
    });
    final result = await h.runtime.submit(input, trace: trace);
    expect(result.status, BatchStatus.partiallyApplied);
    expect(result.errorCode, 'runtime.partial_stale');
    expect(h.mock.requests.length, 1);
    expect(h.bridge.snapshot.values,
        {'a': const IntegerValue(2), 'b': const IntegerValue(7)});
    expect(h.runtime.state.phase, RuntimePhase.awaitingClarification);
  });
  test(
      'continuous relevant changes hit retry bound and leave external values intact',
      () async {
    late Harness h;
    var calls = 0;
    h = harness((request) async {
      await h.bridge
          .manual(SetValueAction(fieldId: 'a', value: IntegerValue(++calls)));
      return response(request, [set('a', 9)], id: 'p-$calls');
    });
    final result = await h.runtime.submit(input, trace: trace);
    expect(result.errorCode, 'runtime.stale_retry_limit');
    expect(calls, 3);
    expect(h.bridge.applies, 0);
    expect(h.bridge.snapshot.values['a'], const IntegerValue(3));
    expect(h.runtime.state.phase, RuntimePhase.error);
  });
  test('forged base revision or provenance rejected without writes', () async {
    for (final wrongTrace in [false, true]) {
      final h = harness((request) => IntelligenceResult(
          proposal: ActionProposal(
              id: 'p',
              baseRevision: request.context.revision + (wrongTrace ? 0 : 1),
              actions: [set('a', 2)],
              provenance: ActionProvenance(
                  trace: wrongTrace
                      ? const TraceContext(
                          interactionId: 'other',
                          requestId: 'request',
                          operationId: 'operation')
                      : request.trace,
                  adapterId: 'mock',
                  adapterVersion: '0.1.0'))));
      final result = await h.runtime.submit(input, trace: trace);
      expect(result.errorCode, 'runtime.proposal_invalid');
      expect(h.bridge.applies, 0);
    }
  });
  test(
      'explicit executeProposal uses its original snapshot for stale revalidation',
      () async {
    final h = harness((request) => response(request, [set('a', 9)]),
        contextFields: 1);
    final original = h.bridge.snapshot;
    final proposal = ActionProposal(
        id: 'p',
        baseRevision: 0,
        actions: [set('a', 2)],
        provenance: const ActionProvenance(
            trace: trace,
            adapterId: 'mock',
            adapterVersion: '0.1.0',
            origin: ActionOrigin.deterministic));
    await h.bridge
        .manual(const SetValueAction(fieldId: 'c', value: IntegerValue(7)));
    final result = await h.runtime.executeProposal(proposal,
        input: input, trace: trace, basedOn: original);
    expect(result.snapshot.values['a'], const IntegerValue(2));
    expect(h.mock.requests, isEmpty);
    expect(h.events.whereType<ProposalRevalidated>().length, 1);
    expect(
        h.events
            .whereType<RuntimeBridgeEvent>()
            .map((e) => e.event)
            .whereType<StateChanged>()
            .last
            .origin,
        ChangeOrigin.deterministic);
  });
  test('default context is compact and does not pass full FormIR', () async {
    final h = harness((request) => response(request, []));
    await h.runtime.submit(input, trace: trace);
    expect(h.mock.requests.single.context.fields.map((f) => f.field.id),
        ['a', 'b']);
    expect(h.mock.requests.single.context.values, isEmpty);
    expect(() => h.mock.requests.single.context.fields.clear(),
        throwsUnsupportedError);
    expect(() => h.mock.requests.clear(), throwsUnsupportedError);
    expect(h.mock.requests.single.allowedActionTypes,
        ['clear_value', 'navigate', 'request_clarification', 'set_value']);
  });
  test(
      'runtime state is published before state events and interpretation failure does not mutate forms',
      () async {
    final h = harness((request) => throw StateError('Mock failed'));
    h.runtime.events.listen((event) {
      if (event is RuntimeStateChanged) {
        expect(h.runtime.state, same(event.state));
      }
    });
    final result = await h.runtime.submit(input, trace: trace);
    expect(result.errorCode, 'runtime.interpretation_failed');
    expect(h.bridge.applies, 0);
    expect(h.runtime.state.phase, RuntimePhase.error);
    expect(h.bridge.snapshot.revision, 0);
  });
  test(
      'runtime disposal releases pending interpretation and never disposes caller-owned bridge',
      () async {
    final held = Completer<IntelligenceResult>();
    final h = harness((request) => held.future);
    final pending = h.runtime.submit(input, trace: trace);
    await pump();
    await h.runtime.dispose();
    expect((await pending).errorCode, 'runtime.disposed');
    expect(h.runtime.state.phase, RuntimePhase.disposed);
    held.complete(response(h.mock.requests.single, [set('a', 2)]));
    await pump();
    expect(h.bridge.applies, 0);
    expect(
        await h.bridge
            .manual(const SetValueAction(fieldId: 'a', value: IntegerValue(7))),
        isA<ActionApplied>());
  });
  test(
      'bridge disposal while interpretation is pending prevents subsequent writes',
      () async {
    final held = Completer<IntelligenceResult>();
    final h = harness((request) => held.future);
    final pending = h.runtime.submit(input, trace: trace);
    await pump();
    await h.bridge.dispose();
    expect((await pending).errorCode, 'runtime.disposed');
    expect(h.bridge.applies, 0);
    held.complete(response(h.mock.requests.single, [set('a', 2)]));
  });
  test('concurrent runtime submissions serialize interpretation/execution',
      () async {
    final release = Completer<void>();
    var calls = 0;
    final h = harness((request) async {
      if (++calls == 1) await release.future;
      return response(request, [set(calls == 1 ? 'a' : 'b', calls)],
          id: 'p-$calls');
    });
    final first = h.runtime.submit(input, trace: trace);
    final second = h.runtime.submit(input,
        trace: const TraceContext(
            interactionId: 'second',
            requestId: 'second',
            operationId: 'second',
            segmentId: 'segment'));
    await pump();
    expect(h.mock.requests.length, 1);
    release.complete();
    await first;
    await second;
    expect(h.mock.requests.last.context.revision, 1);
    expect(h.bridge.snapshot.values,
        {'a': const IntegerValue(1), 'b': const IntegerValue(2)});
  });
  test('runtime imports no concrete bridge or source project classes', () {
    for (final file
        in Directory('lib/src/runtime').listSync().whereType<File>()) {
      final code = file.readAsStringSync();
      expect(code, isNot(contains('LocalFormStateBridge')));
      expect(code, isNot(contains('ExternalStateBridge')));
      expect(code, isNot(contains('ExistingFormStore')));
      expect(code, isNot(contains('package:flutter')));
    }
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

const trace = TraceContext(
    interactionId: 'interaction',
    requestId: 'request',
    operationId: 'operation');

void main() {
  test('default telemetry drops utterances, values, and audio', () {
    final memory = MemoryTelemetrySink();
    final sink = RedactingTelemetrySink(memory);
    sink.record(TelemetryRecord(
        name: TelemetryName.interactionCompleted,
        path: ResolutionPath.deterministic,
        attributes: {
          'fieldId': 'age',
          'utterance': 'age is thirty two',
          'value': 32,
          'audio': [1, 2, 3],
          'nested': {
            'transcript': 'secret transcript',
            'action': 'set_value',
          },
        },
        latencyMs: const {
          TelemetryStage.commit: 4
        }));
    final record = memory.records.single;
    final encoded = jsonEncode(record.toJson());
    expect(encoded, isNot(contains('thirty two')));
    expect(encoded, isNot(contains('secret transcript')));
    expect(record.attributes.containsKey('audio'), isFalse);
    expect(record.attributes['fieldId'], 'age');
    final nested = record.attributes['nested'] as Map<String, Object?>;
    expect(nested['action'], 'set_value');
    expect(record.latencyMs[TelemetryStage.commit], 4);
  });

  test('explicit policy keeps text and values, never audio', () {
    final memory = MemoryTelemetrySink();
    final sink = RedactingTelemetrySink(memory,
        policy: const TelemetryPolicy(
            includeUtterance: true, includeFieldValues: true));
    sink.record(
        TelemetryRecord(name: TelemetryName.interactionCompleted, attributes: {
      'utterance': 'age is thirty two',
      'value': 32,
      'audio': [9],
      'raw': 'pcm',
    }));
    final attributes = memory.records.single.attributes;
    expect(attributes['utterance'], 'age is thirty two');
    expect(attributes['value'], 32);
    expect(attributes.containsKey('audio'), isFalse);
    expect(attributes.containsKey('raw'), isFalse);
  });

  test('eval traces persist only under an explicit policy', () {
    final refused = EvalTraceStore();
    final secret = EvalTrace(
        interactionId: 'interaction',
        outcome: 'accept',
        fieldIds: const ['age'],
        utterance: 'thirty two',
        fieldValues: const {'age': 32});
    expect(refused.persist(secret), isFalse);
    expect(refused.traces, isEmpty);

    final redacted =
        EvalTraceStore(policy: const TelemetryPolicy(persistEvalTraces: true));
    expect(redacted.persist(secret), isTrue);
    expect(redacted.traces.single.utterance, isNull);
    expect(redacted.traces.single.fieldValues, isNull);
    expect(redacted.traces.single.fieldIds, ['age']);
    expect(redacted.traces.single.outcome, 'accept');

    final raw = EvalTraceStore(
        policy: const TelemetryPolicy(
            persistEvalTraces: true,
            includeUtterance: true,
            includeFieldValues: true));
    expect(raw.persist(secret), isTrue);
    expect(raw.traces.single.utterance, 'thirty two');
    expect(raw.traces.single.fieldValues, {'age': 32});
  });

  test('latency summary uses nearest-rank p50 and p95', () {
    expect(latencyPercentile(const [10, 20, 30, 40], 0.5), 20);
    expect(latencyPercentile(const [10, 20, 30, 40], 0.95), 40);
    var clock = 0;
    final timer = StageTimer(nowMs: () => clock);
    timer.start(TelemetryStage.model);
    clock = 15;
    timer.stop(TelemetryStage.model);
    expect(timer.milliseconds[TelemetryStage.model], 15);
  });

  test('metrics report resolution, accuracy, failures, and stage latency', () {
    final metrics = ProductionMetrics.from([
      observeInteraction(
          route: InputRoute.deterministic,
          correction: true,
          stateMatched: true,
          latencyMs: const {TelemetryStage.commit: 10, TelemetryStage.stt: 5}),
      observeInteraction(
          route: InputRoute.needsIntelligence,
          stateMatched: true,
          latencyMs: const {TelemetryStage.commit: 20}),
      observeInteraction(
          usedFallback: true,
          stateMatched: true,
          latencyMs: const {TelemetryStage.commit: 30}),
      observeInteraction(
          route: InputRoute.needsClarification,
          stateMatched: true,
          latencyMs: const {TelemetryStage.commit: 40}),
      observeInteraction(
          result: _failed('stt.recognizer_down'),
          stateMatched: false,
          latencyMs: const {TelemetryStage.commit: 50, TelemetryStage.stt: 15}),
    ]);
    expect(metrics.interactions, 5);
    expect(metrics.deterministicRate, 1 / 5);
    expect(metrics.localModelRate, 1 / 5);
    expect(metrics.fallbackRate, 1 / 5);
    expect(metrics.clarificationRate, 1 / 5);
    expect(metrics.correctionRate, 1 / 5);
    expect(metrics.stateAccuracy, 4 / 5);
    expect(metrics.errorContribution(FailureClass.stt), 1);
    expect(metrics.errorContribution(FailureClass.model), 0);
    expect(metrics.latency[TelemetryStage.commit]!.p50Ms, 30);
    expect(metrics.latency[TelemetryStage.commit]!.p95Ms, 50);
    expect(metrics.latency[TelemetryStage.stt]!.p50Ms, 5);
    expect(metrics.latency[TelemetryStage.stt]!.p95Ms, 15);
    expect(
        ProductionMetrics.from(const <InteractionObservation>[])
            .deterministicRate,
        0);
  });

  test('context-budget failures are context selection, not model failures', () {
    final observation = observeInteraction(
        result: _failed('runtime.context_budget_exceeded'),
        stateMatched: false);
    expect(observation.path, ResolutionPath.unresolved);
    expect(observation.failure, FailureClass.contextSelection);
  });

  test('recovery resumes the committed snapshot and abandons proposals', () {
    final committed = FormStateSnapshot(
        formId: 'form',
        revision: 1,
        lifecycle: FormLifecycle.active,
        values: {'age': IntegerValue(32)});
    final checkpoint = RecoveryCheckpoint.capture(committed,
        inFlightProposalIds: const ['proposal-b', 'proposal-a']);
    expect(checkpoint.abandonedProposalIds, ['proposal-a', 'proposal-b']);
    const recovery = CrashRecovery();
    expect(recovery.resume(committed, checkpoint), isTrue);
    final replayed = FormStateSnapshot(
        formId: 'form',
        revision: 2,
        lifecycle: FormLifecycle.active,
        values: {'age': IntegerValue(41)});
    expect(recovery.resume(replayed, checkpoint), isFalse);
  });

  test('protocol 1.0 fixture round-trips and rejects unknown actions', () {
    final raw = jsonObject(
        jsonDecode(File('test/fixtures/protocol_1_0.json').readAsStringSync()));
    final protocol = ProtocolDocument.decode(raw);
    expect(protocol.specVersion, protocolSpecVersion);
    expect(protocol.actions, hasLength(12));
    for (final action in protocol.actions) {
      final again =
          FormActionCodec.decode(jsonDecode(jsonEncode(action.toJson())));
      expect(again, action);
    }
    final unknown = requireType<List<Object?>>(raw['unknownActions']).single;
    expect(() => FormActionCodec.decode(unknown), throwsFormatException);
    expect(
        () => ProtocolDocument.decode(
            <String, Object?>{'specVersion': '2.0', 'actions': <Object?>[]}),
        throwsFormatException);
  });

  test('soak replays a seeded mix without duplicate commits', () async {
    final first = await _soak(7);
    final second = await _soak(7);
    expect(second.revisions, first.revisions);
    expect(second.values, first.values);
    expect(first.revisions.last, first.finalRevision);
  });
}

RuntimeInteractionResult _failed(String code) => RuntimeInteractionResult(
    trace: trace,
    actions: const [],
    snapshot: FormStateSnapshot(
        formId: 'form',
        revision: 0,
        lifecycle: FormLifecycle.active,
        values: const {}),
    status: BatchStatus.rejected,
    errorCode: code);

final class _SoakResult {
  final List<int> revisions;
  final Map<String, FormValue> values;
  final int finalRevision;
  const _SoakResult(this.revisions, this.values, this.finalRevision);
}

Future<_SoakResult> _soak(int seed) async {
  final random = Random(seed);
  final bridge = LocalFormStateBridge(
      form: FormIR(id: 'test', fields: [
    FormField(
        id: 'a',
        value: const IntegerDefinition(),
        semantics: FieldSemantics(label: 'A')),
    FormField(
        id: 'b',
        value: const IntegerDefinition(),
        semantics: FieldSemantics(label: 'B')),
  ]));
  addTearDown(bridge.dispose);
  var expected = <String, FormValue>{};
  var revision = 0;
  final undo = <Map<String, FormValue>>[];
  final redo = <Map<String, FormValue>>[];
  var eventRevision = 0;
  bridge.events.listen((event) {
    if (event is! StateChanged) return;
    expect(event.previousRevision, eventRevision);
    expect(event.revision, eventRevision + 1);
    eventRevision = event.revision;
    expect(bridge.snapshot.revision, eventRevision);
  });
  SetValueAction set(String id, int value) =>
      SetValueAction(fieldId: id, value: IntegerValue(value));
  FormAction randomAction() => random.nextBool()
      ? set(random.nextBool() ? 'a' : 'b', random.nextInt(5))
      : ClearValueAction(fieldId: random.nextBool() ? 'a' : 'b');
  Map<String, FormValue> project(
      Map<String, FormValue> values, FormAction action) {
    final next = Map<String, FormValue>.of(values);
    if (action is SetValueAction) {
      next[action.fieldId] = action.value;
    } else if (action is ClearValueAction) {
      next.remove(action.fieldId);
    }
    return next;
  }

  void commit(Map<String, FormValue> next) {
    if (!jsonEquals(expected, next)) {
      undo.add(Map.of(expected));
      redo.clear();
      expected = next;
      revision++;
    }
  }

  ApplyContext context(int expectedRevision) => ApplyContext(
      expectedRevision: expectedRevision,
      interactionId: 'interaction',
      operationId: 'op-$revision',
      origin: ActionOrigin.user);
  final revisions = <int>[];
  for (var i = 0; i < 250; i++) {
    switch (random.nextInt(8)) {
      case 0:
      case 1:
        final action = randomAction();
        commit(project(expected, action));
        await bridge.apply(action, context: context(bridge.snapshot.revision));
      case 2:
        final actions = List<FormAction>.generate(3, (_) => randomAction());
        var candidate = Map<String, FormValue>.of(expected);
        for (final action in actions) {
          candidate = project(candidate, action);
        }
        commit(candidate);
        await bridge.applyBatch(actions,
            context: context(bridge.snapshot.revision),
            mode: BatchApplyMode.atomic);
      case 3:
        final actions = List<FormAction>.generate(3, (_) => randomAction());
        final base = bridge.snapshot.revision;
        for (final action in actions) {
          commit(project(expected, action));
        }
        await bridge.applyBatch(actions, context: context(base));
      case 4:
        final result =
            await bridge.undo(context: context(bridge.snapshot.revision));
        if (undo.isEmpty) {
          expect(result, isA<ActionRejected>());
        } else {
          redo.add(Map.of(expected));
          expected = undo.removeLast();
          revision++;
          expect(result, isA<ActionApplied>());
        }
      case 5:
        final result =
            await bridge.redo(context: context(bridge.snapshot.revision));
        if (redo.isEmpty) {
          expect(result, isA<ActionRejected>());
        } else {
          undo.add(Map.of(expected));
          expected = redo.removeLast();
          revision++;
          expect(result, isA<ActionApplied>());
        }
      case 6:
        final result = await bridge.apply(randomAction(),
            context: context(bridge.snapshot.revision - 1));
        expect(result, isA<ActionRejected>());
      case 7:
        final result = await bridge.applyBatch(
            [randomAction(), set('missing', 1)],
            context: context(bridge.snapshot.revision),
            mode: BatchApplyMode.atomic);
        expect(result.status, BatchStatus.rejected);
    }
    expect(bridge.snapshot.values, expected, reason: 'operation $i');
    expect(bridge.snapshot.revision, revision, reason: 'operation $i');
    expect(eventRevision, revision, reason: 'operation $i');
    revisions.add(revision);
  }
  return _SoakResult(
      revisions, Map<String, FormValue>.of(bridge.snapshot.values), revision);
}

import 'dart:async';
import 'dart:typed_data';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_stt/form_assistant_stt.dart';
import 'package:test/test.dart';

TraceContext traceFor(String segment) => TraceContext(
  interactionId: 'interaction',
  requestId: 'request-$segment',
  operationId: 'operation-$segment',
  segmentId: segment,
);

STTSessionConfig configFor(String segment, {bool retainAudio = false}) =>
    STTSessionConfig(
      segmentId: segment,
      sampleRateHz: 16000,
      channels: 1,
      retainAudio: retainAudio,
    );

IntelligenceResult proposal(IntelligenceRequest request) => IntelligenceResult(
  proposal: ActionProposal(
    id: 'proposal',
    baseRevision: request.context.revision,
    actions: const [
      ProposedAction(
        id: 'action',
        action: SetValueAction(fieldId: 'age', value: IntegerValue(32)),
      ),
    ],
    provenance: ActionProvenance(
      trace: request.trace.withProposal('proposal'),
      adapterId: 'mock',
      adapterVersion: '0.1.0',
    ),
  ),
);

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 50 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue);
}

class Rig {
  final FormStateBridge bridge;
  final FormAssistantRuntime runtime;
  final VoiceOrchestrator voice;
  final MockIntelligenceAdapter mock;
  final List<VoiceEvent> events = [];
  Rig(this.bridge, this.runtime, this.voice, this.mock) {
    voice.events.listen(events.add);
  }
}

Rig rig(FutureOr<IntelligenceResult> Function(IntelligenceRequest) handler) {
  final form = FormIR(
    id: 'form',
    fields: [
      FormField(
        id: 'age',
        value: const IntegerDefinition(),
        semantics: FieldSemantics(label: 'Age'),
        constraints: FieldConstraints(min: 0, max: 120),
      ),
    ],
  );
  final bridge = LocalFormStateBridge(form: form, activeFieldId: 'age');
  final mock = MockIntelligenceAdapter(handler: handler);
  final runtime = FormAssistantRuntime(
    form: form,
    bridge: bridge,
    intelligence: mock,
  );
  final voice = VoiceOrchestrator(
    runtime: runtime,
    stt: HostSTTAdapter(),
    interactionId: 'interaction',
  );
  addTearDown(() async {
    await voice.dispose();
    await runtime.dispose();
    await bridge.dispose();
  });
  return Rig(bridge, runtime, voice, mock);
}

void main() {
  test(
    'partial transcript cannot mutate state while a final is in flight',
    () async {
      final release = Completer<void>();
      var calls = 0;
      final harness = rig((request) async {
        calls++;
        await release.future;
        return proposal(request);
      });
      final session =
          await harness.voice.start(configFor('seg'), trace: traceFor('seg'))
              as HostSTTSession;
      final bytes = Uint8List.fromList([0, 1, 2, 3]);
      await session.pushAudio(
        AudioChunk(sampleRateHz: 16000, channels: 1, pcm16le: bytes),
      );
      bytes.fillRange(0, bytes.length, 9);
      expect(session.retainedAudio, isNull);
      session.emit(
        STTFinal(
          'seg',
          text: 'please set age to thirty two',
          transcriptConfidence: 0.42,
        ),
      );
      await until(() => calls == 1);
      session.emit(STTPartial('seg', text: '5', transcriptConfidence: 0.15));
      session.emit(STTFinal('seg', text: '5', transcriptConfidence: 0.9));
      expect(harness.bridge.snapshot.values, isEmpty);
      expect(
        harness.events.whereType<VoicePartialPresented>().single.input.text,
        '5',
      );
      expect(
        harness.events.whereType<VoicePartialPresented>().single.input.partial,
        isTrue,
      );
      expect(
        harness.events.whereType<VoiceSegmentIgnored>().single.reason,
        'duplicate_final',
      );
      release.complete();
      await until(
        () => harness.events.whereType<VoiceFinalSettled>().isNotEmpty,
      );
      expect(harness.bridge.snapshot.values['age'], const IntegerValue(32));
      expect(harness.bridge.snapshot.revision, 1);
      expect(calls, 1);
      final settled = harness.events.whereType<VoiceFinalSettled>().single;
      expect(settled.input.transcriptConfidence, 0.42);
      expect(settled.input.partial, isFalse);
      expect(settled.result.proposal!.confidence, isNull);
      expect(settled.result.trace.segmentId, 'seg');
    },
  );

  test('final numeric transcript enters the router once', () async {
    final harness = rig((_) => throw StateError('model must not run'));
    final session =
        await harness.voice.start(configFor('seg'), trace: traceFor('seg'))
            as HostSTTSession;
    session.emit(STTPartial('seg', text: '5', transcriptConfidence: 0.2));
    expect(harness.bridge.snapshot.values, isEmpty);
    session.emit(STTFinal('seg', text: '5', transcriptConfidence: 0.8));
    await until(() => harness.events.whereType<VoiceFinalSettled>().isNotEmpty);
    session.emit(STTFinal('seg', text: '9', transcriptConfidence: 0.8));
    await Future<void>.delayed(Duration.zero);
    expect(harness.bridge.snapshot.values['age'], const IntegerValue(5));
    expect(harness.bridge.snapshot.revision, 1);
    expect(harness.mock.requests, isEmpty);
    expect(
      harness.events
          .whereType<VoiceFinalSettled>()
          .single
          .result
          .trace
          .segmentId,
      'seg',
    );
    expect(
      harness.events.whereType<VoiceSegmentIgnored>().single.reason,
      'duplicate_final',
    );
  });

  test('cancelled segment cannot commit later or in flight', () async {
    final release = Completer<void>();
    var calls = 0;
    final harness = rig((request) async {
      calls++;
      await release.future;
      return proposal(request);
    });
    final live =
        await harness.voice.start(configFor('live'), trace: traceFor('live'))
            as HostSTTSession;
    live.emit(STTFinal('live', text: 'please set age to thirty two'));
    await until(() => calls == 1);
    await harness.voice.interrupt('live');
    release.complete();
    await Future<void>.delayed(Duration.zero);
    live.emit(STTFinal('live', text: '5'));
    final late =
        await harness.voice.start(configFor('late'), trace: traceFor('late'))
            as HostSTTSession;
    await harness.voice.interrupt('late');
    late.emit(STTFinal('late', text: '5', transcriptConfidence: 0.99));
    expect(harness.bridge.snapshot.values, isEmpty);
    expect(harness.events.whereType<VoiceFinalSettled>(), isEmpty);
    expect(
      harness.events.whereType<VoiceSegmentIgnored>().map(
        (event) => event.segmentId,
      ),
      ['live', 'late'],
    );
    expect(calls, 1);
  });

  test('STT error leaves the manual form usable', () async {
    final harness = rig((_) => throw StateError('model must not run'));
    final session =
        await harness.voice.start(configFor('seg'), trace: traceFor('seg'))
            as HostSTTSession;
    session.emit(
      STTError('seg', code: 'recognizer_down', message: 'unavailable'),
    );
    expect(harness.voice.state.phase, VoicePhase.failed);
    expect(harness.bridge.snapshot.values, isEmpty);
    final manual = await harness.runtime.submit(
      const UserInput(text: '5'),
      trace: const TraceContext(
        interactionId: 'interaction',
        requestId: 'manual',
        operationId: 'manual',
      ),
    );
    expect(manual.errorCode, isNull);
    expect(harness.bridge.snapshot.values['age'], const IntegerValue(5));
    expect(harness.voice.state.phase, VoicePhase.failed);
  });

  test('audio is not retained unless the session explicitly opts in', () async {
    final dropped = HostSTTSession(configFor('seg'));
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await dropped.pushAudio(
      AudioChunk(sampleRateHz: 16000, channels: 1, pcm16le: bytes),
    );
    bytes.fillRange(0, bytes.length, 7);
    expect(dropped.retainedAudio, isNull);
    expect(dropped.observedBytes, 4);

    final kept = HostSTTSession(configFor('keep', retainAudio: true));
    final original = Uint8List.fromList([1, 2, 3, 4]);
    await kept.pushAudio(
      AudioChunk(sampleRateHz: 16000, channels: 1, pcm16le: original),
    );
    original[0] = 9;
    expect(kept.retainedAudio, isNotNull);
    expect(kept.retainedAudio![0], 1);
    await kept.cancel();
    expect(kept.retainedAudio, isNull);

    expect(
      () => AudioChunk(sampleRateHz: 16000, channels: 1, pcm16le: Uint8List(1)),
      throwsArgumentError,
    );
    expect(
      () => dropped.pushAudio(
        AudioChunk(
          sampleRateHz: 8000,
          channels: 1,
          pcm16le: Uint8List.fromList([0, 1]),
        ),
      ),
      throwsArgumentError,
    );
  });
}

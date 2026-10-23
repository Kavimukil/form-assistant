import 'dart:async';

import '../contracts/intelligence.dart';
import '../contracts/stt.dart';
import '../contracts/trace.dart';
import 'form_assistant_runtime.dart';
import 'runtime_events.dart';

enum VoicePhase { idle, listening, interpreting, failed, cancelled }

/// Presentation and session state. It is not authoritative form state.
final class VoiceState {
  final VoicePhase phase;
  final String? segmentId;
  final String? partialText;
  final double? transcriptConfidence;
  final String? errorCode;
  const VoiceState(
      {required this.phase,
      this.segmentId,
      this.partialText,
      this.transcriptConfidence,
      this.errorCode});

  VoiceState copy(
          {VoicePhase? phase,
          String? segmentId,
          String? partialText,
          double? transcriptConfidence,
          String? errorCode,
          bool clearPartial = false,
          bool clearError = false}) =>
      VoiceState(
          phase: phase ?? this.phase,
          segmentId: segmentId ?? this.segmentId,
          partialText: clearPartial ? null : partialText ?? this.partialText,
          transcriptConfidence: clearPartial
              ? null
              : transcriptConfidence ?? this.transcriptConfidence,
          errorCode: clearError ? null : errorCode ?? this.errorCode);
}

sealed class VoiceEvent {
  final String segmentId;
  const VoiceEvent(this.segmentId);
}

final class VoicePartialPresented extends VoiceEvent {
  final VoiceInput input;
  VoicePartialPresented(this.input) : super(input.segmentId);
}

final class VoiceFinalSettled extends VoiceEvent {
  final VoiceInput input;
  final RuntimeInteractionResult result;
  VoiceFinalSettled(this.input, this.result) : super(input.segmentId);
}

final class VoiceSegmentIgnored extends VoiceEvent {
  final String reason;
  const VoiceSegmentIgnored(super.segmentId, this.reason);
}

final class VoiceRecognitionFailed extends VoiceEvent {
  final String code;
  final String message;
  const VoiceRecognitionFailed(super.segmentId,
      {required this.code, required this.message});
}

/// Final transcripts enter the existing runtime once. Partials are presented
/// and never submitted. Audio bytes are not accepted by this type.
final class VoiceOrchestrator {
  final FormAssistantRuntime runtime;
  final STTAdapter stt;
  final String interactionId;
  VoiceState _state = const VoiceState(phase: VoicePhase.idle);
  final _events = StreamController<VoiceEvent>.broadcast(sync: true);
  final _sessions = <String, STTSession>{};
  final _subscriptions = <String, StreamSubscription<STTEvent>>{};
  final _tokens = <String, CancellationToken>{};
  final _cancelled = <String>{};
  final _submitted = <String>{};
  var _disposed = false;

  VoiceOrchestrator(
      {required this.runtime, required this.stt, required this.interactionId}) {
    if (interactionId.isEmpty) throw ArgumentError('Invalid interaction id');
  }

  VoiceState get state => _state;
  Stream<VoiceEvent> get events => _events.stream;

  Future<STTSession> start(STTSessionConfig config,
      {required TraceContext trace}) async {
    _ensureOpen();
    if (trace.interactionId != interactionId ||
        trace.requestId.isEmpty ||
        trace.operationId.isEmpty ||
        (trace.segmentId != null && trace.segmentId != config.segmentId)) {
      throw ArgumentError('Voice trace does not match this interaction');
    }
    if (_sessions.containsKey(config.segmentId)) {
      throw StateError('Segment ${config.segmentId} is already open');
    }
    if (config.channels > stt.capabilities.maxChannels) {
      throw ArgumentError('Session exceeds STT channel capability');
    }
    final session = await stt.createSession(config);
    _sessions[config.segmentId] = session;
    _state =
        VoiceState(phase: VoicePhase.listening, segmentId: config.segmentId);
    _subscriptions[config.segmentId] = session.events.listen((event) {
      if (event.segmentId != config.segmentId) {
        _emit(VoiceSegmentIgnored(event.segmentId, 'segment_mismatch'));
        return;
      }
      _onEvent(event, trace);
    });
    return session;
  }

  Future<void> interrupt(String segmentId) async {
    _cancelled.add(segmentId);
    _tokens.remove(segmentId)?.cancel();
    final session = _sessions[segmentId];
    if (session != null) await session.cancel();
    if (_state.segmentId == segmentId) {
      _state = _state.copy(phase: VoicePhase.cancelled, clearPartial: true);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    for (final session in _sessions.values) {
      await session.cancel();
    }
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _sessions.clear();
    _subscriptions.clear();
    await _events.close();
  }

  void _onEvent(STTEvent event, TraceContext trace) {
    if (_disposed) return;
    if (_cancelled.contains(event.segmentId)) {
      _emit(VoiceSegmentIgnored(event.segmentId, 'cancelled'));
      return;
    }
    switch (event) {
      case STTPartial():
        final input = VoiceInput(
            text: event.text,
            segmentId: event.segmentId,
            transcriptConfidence: event.transcriptConfidence,
            partial: true);
        _state = _state.copy(
            partialText: input.text,
            transcriptConfidence: input.transcriptConfidence);
        _emit(VoicePartialPresented(input));
      case STTFinal():
        if (!_submitted.add(event.segmentId)) {
          _emit(VoiceSegmentIgnored(event.segmentId, 'duplicate_final'));
          return;
        }
        unawaited(_submit(event, trace));
      case STTError():
        _state = _state.copy(
            phase: VoicePhase.failed,
            segmentId: event.segmentId,
            errorCode: event.code);
        _emit(VoiceRecognitionFailed(event.segmentId,
            code: event.code, message: event.message));
      case STTEnd():
        if (_state.phase == VoicePhase.listening &&
            _state.segmentId == event.segmentId) {
          _state = _state.copy(phase: VoicePhase.idle, clearPartial: true);
        }
    }
  }

  Future<void> _submit(STTFinal event, TraceContext trace) async {
    final token = CancellationToken();
    _tokens[event.segmentId] = token;
    _state = _state.copy(
        phase: VoicePhase.interpreting,
        segmentId: event.segmentId,
        clearPartial: true,
        clearError: true);
    final input = VoiceInput(
        text: event.text,
        segmentId: event.segmentId,
        transcriptConfidence: event.transcriptConfidence,
        partial: false);
    try {
      final result = await runtime.submit(
          UserInput(text: input.text, segmentId: input.segmentId),
          locale: _sessions[event.segmentId]?.config.locale,
          trace: TraceContext(
              interactionId: trace.interactionId,
              requestId: trace.requestId,
              operationId: trace.operationId,
              segmentId: event.segmentId),
          options: IntelligenceOptions(cancellation: token));
      if (_disposed || _cancelled.contains(event.segmentId)) return;
      _state = VoiceState(
          phase: VoicePhase.idle,
          segmentId: event.segmentId,
          transcriptConfidence: input.transcriptConfidence);
      _emit(VoiceFinalSettled(input, result));
    } finally {
      _tokens.remove(event.segmentId);
    }
  }

  void _emit(VoiceEvent event) {
    if (_disposed || _events.isClosed) return;
    _events.add(event);
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('Voice orchestrator is disposed');
  }
}

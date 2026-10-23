import 'dart:async';
import 'dart:typed_data';

import 'package:form_assistant_core/form_assistant_core.dart';

/// Recognizer-facing session. Audio is measured and then dropped unless
/// [STTSessionConfig.retainAudio] is set. Recognition events are injected by
/// the host; this type does not record the microphone.
final class HostSTTSession implements STTSession {
  @override
  final STTSessionConfig config;
  final _events = StreamController<STTEvent>.broadcast(sync: true);
  var _audioClosed = false;
  var _streamClosed = false;
  var observedBytes = 0;
  Uint8List? _retainedAudio;
  Uint8List? get retainedAudio => _retainedAudio;

  HostSTTSession(this.config);

  @override
  Stream<STTEvent> get events => _events.stream;

  @override
  Future<void> pushAudio(AudioChunk chunk) async {
    if (_audioClosed) throw StateError('STT session is closed');
    if (chunk.sampleRateHz != config.sampleRateHz ||
        chunk.channels != config.channels) {
      throw ArgumentError('Audio format does not match the session');
    }
    observedBytes += chunk.pcm16le.length;
    if (config.retainAudio) {
      _retainedAudio = Uint8List.fromList(chunk.pcm16le);
    }
  }

  void emit(STTEvent event) {
    if (_streamClosed) throw StateError('STT session is closed');
    if (event.segmentId != config.segmentId) {
      throw ArgumentError('Event segment does not match the session');
    }
    _events.add(event);
  }

  @override
  Future<void> finish() async {
    if (_streamClosed) return;
    _audioClosed = true;
    _streamClosed = true;
    if (!_events.isClosed) {
      _events.add(STTEnd(config.segmentId));
      await _events.close();
    }
  }

  @override
  Future<void> cancel() async {
    _audioClosed = true;
    _retainedAudio = null;
  }
}

final class HostSTTAdapter implements STTAdapter {
  @override
  final String id;
  @override
  final String version;
  @override
  final STTCapabilities capabilities;
  HostSTTAdapter({
    this.id = 'host_stt',
    this.version = '0.1.0',
    this.capabilities = const STTCapabilities(),
  });

  @override
  Future<STTSession> createSession(STTSessionConfig config) async {
    if (!capabilities.streaming) {
      throw StateError('Adapter is not streaming');
    }
    if (config.channels > capabilities.maxChannels) {
      throw ArgumentError('Too many audio channels');
    }
    return HostSTTSession(config);
  }
}

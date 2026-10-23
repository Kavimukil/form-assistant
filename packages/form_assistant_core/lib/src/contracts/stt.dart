import 'dart:async';
import 'dart:typed_data';

/// PCM16 little-endian audio. The runtime must not keep these bytes.
final class AudioChunk {
  final int sampleRateHz;
  final int channels;
  final Uint8List pcm16le;
  AudioChunk(
      {required this.sampleRateHz,
      required this.channels,
      required this.pcm16le}) {
    if (sampleRateHz <= 0 || channels <= 0 || channels > 2) {
      throw ArgumentError('Invalid PCM16 rate or channel count');
    }
    if (pcm16le.isEmpty || pcm16le.length.isOdd) {
      throw ArgumentError('PCM16 payload must be a non-empty even byte length');
    }
  }
}

final class STTCapabilities {
  final bool streaming;
  final int maxChannels;
  const STTCapabilities({this.streaming = true, this.maxChannels = 2});
}

final class STTSessionConfig {
  final String segmentId;
  final int sampleRateHz;
  final int channels;
  final String locale;

  /// Default false. Audio bytes are dropped after the session reads them.
  final bool retainAudio;
  STTSessionConfig(
      {required this.segmentId,
      required this.sampleRateHz,
      this.channels = 1,
      this.locale = 'en',
      this.retainAudio = false}) {
    if (segmentId.isEmpty ||
        locale.trim().isEmpty ||
        sampleRateHz <= 0 ||
        channels <= 0 ||
        channels > 2) {
      throw ArgumentError('Invalid STT session config');
    }
  }
}

sealed class STTEvent {
  final String segmentId;
  const STTEvent(this.segmentId);
}

final class STTPartial extends STTEvent {
  final String text;
  final double? transcriptConfidence;
  STTPartial(super.segmentId, {required this.text, this.transcriptConfidence}) {
    _checkConfidence(transcriptConfidence);
  }
}

final class STTFinal extends STTEvent {
  final String text;
  final double? transcriptConfidence;
  STTFinal(super.segmentId, {required this.text, this.transcriptConfidence}) {
    _checkConfidence(transcriptConfidence);
  }
}

final class STTError extends STTEvent {
  final String code;
  final String message;
  STTError(super.segmentId, {required this.code, required this.message}) {
    if (code.isEmpty) throw ArgumentError('STT error code is empty');
  }
}

final class STTEnd extends STTEvent {
  const STTEnd(super.segmentId);
}

void _checkConfidence(double? confidence) {
  if (confidence != null &&
      (!confidence.isFinite || confidence < 0 || confidence > 1)) {
    throw ArgumentError('Invalid transcript confidence');
  }
}

abstract interface class STTSession {
  STTSessionConfig get config;
  Stream<STTEvent> get events;
  Future<void> pushAudio(AudioChunk chunk);
  Future<void> finish();
  Future<void> cancel();
}

abstract interface class STTAdapter {
  String get id;
  String get version;
  STTCapabilities get capabilities;
  Future<STTSession> createSession(STTSessionConfig config);
}

/// Transcript boundary. [transcriptConfidence] is not model confidence.
final class VoiceInput {
  final String text;
  final String segmentId;
  final double? transcriptConfidence;
  final bool partial;
  const VoiceInput(
      {required this.text,
      required this.segmentId,
      this.transcriptConfidence,
      required this.partial});
}

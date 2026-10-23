import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:form_assistant_core/form_assistant_core.dart';

enum FieldHighlight { none, provisional, accepted }

/// Listens to runtime and voice events. It does not own form widgets or the store.
final class FormAssistantController extends ChangeNotifier {
  final FormAssistantRuntime runtime;
  final VoiceOrchestrator? voice;
  final STTSessionConfig Function(String segmentId)? voiceConfig;
  final List<StreamSubscription<Object>> _subscriptions = [];
  var _disposed = false;
  var _segmentSerial = 0;
  var _clarificationDismissed = false;
  String? _activeSegment;
  RuntimePhase _phase = RuntimePhase.idle;
  List<RequestClarificationAction> _clarifications = const [];
  final Map<String, FieldHighlight> _highlights = {};
  String? _partialTranscript;
  String? _voiceError;
  STTSession? activeSession;

  FormAssistantController(
      {required this.runtime, this.voice, this.voiceConfig}) {
    _subscriptions.add(runtime.events.listen(handleRuntimeEvent));
    final voiceEvents = voice?.events;
    if (voiceEvents != null) {
      _subscriptions.add(voiceEvents.listen(handleVoiceEvent));
    }
  }

  RuntimePhase get phase => _phase;
  String? get partialTranscript => _partialTranscript;
  String? get voiceError => _voiceError;
  bool get listening => _activeSegment != null && activeSession != null;

  FieldHighlight highlightFor(String fieldId) =>
      _highlights[fieldId] ?? FieldHighlight.none;

  /// Optional accent for an existing field. Null means the form's own decoration.
  Color? accentFor(String fieldId) => switch (highlightFor(fieldId)) {
        FieldHighlight.none => null,
        FieldHighlight.provisional => const Color(0xFFE65100),
        FieldHighlight.accepted => const Color(0xFF2E7D32),
      };

  String? get clarificationText {
    if (_clarificationDismissed || _clarifications.isEmpty) return null;
    final action = _clarifications.first;
    return action.detail ??
        switch (action.reason) {
          ClarificationReason.ambiguous => 'That answer is ambiguous.',
          ClarificationReason.missingInformation =>
            'More information is needed.',
          ClarificationReason.invalidValue => 'That value cannot be used.',
          ClarificationReason.lowConfidence => 'Please confirm that answer.',
        };
  }

  void dismissClarification() {
    _clarificationDismissed = true;
    _notify();
  }

  Future<void> submitText(String text, {required TraceContext trace}) {
    return runtime.submit(UserInput(text: text, segmentId: trace.segmentId),
        trace: trace);
  }

  void beginListening() {
    startListening();
  }

  void stopListening() {
    interrupt();
  }

  Future<STTSession> startListening() async {
    final orchestrator = voice;
    final configFor = voiceConfig;
    if (orchestrator == null || configFor == null) {
      throw StateError('Voice is not configured');
    }
    final segmentId = 'voice-${_segmentSerial++}';
    _activeSegment = segmentId;
    _voiceError = null;
    final session = await orchestrator.start(configFor(segmentId),
        trace: TraceContext(
            interactionId: orchestrator.interactionId,
            requestId: 'request-$segmentId',
            operationId: 'operation-$segmentId',
            segmentId: segmentId));
    activeSession = session;
    _notify();
    return session;
  }

  Future<void> interrupt() async {
    final segmentId = _activeSegment;
    _activeSegment = null;
    activeSession = null;
    _partialTranscript = null;
    _notify();
    if (segmentId != null) await voice?.interrupt(segmentId);
  }

  void handleRuntimeEvent(RuntimeEvent event) {
    switch (event) {
      case RuntimeStateChanged(:final state):
        _phase = state.phase;
        if (state.clarifications.length != _clarifications.length) {
          _clarificationDismissed = false;
        }
        _clarifications = state.clarifications;
      case ProposalReceived(:final proposal):
        for (final proposed in proposal.actions) {
          final action = proposed.action;
          if (action is FormMutationAction) {
            _highlights[action.fieldId] = FieldHighlight.provisional;
          }
        }
      case InteractionCompleted(:final result):
        for (final actionResult in result.actions) {
          final action = actionResult.proposedAction.action;
          if (action is! FormMutationAction) continue;
          if (actionResult.bridgeResult is ActionApplied) {
            _highlights[action.fieldId] = FieldHighlight.accepted;
          } else if (_highlights[action.fieldId] ==
              FieldHighlight.provisional) {
            _highlights.remove(action.fieldId);
          }
        }
      case ClarificationRequested():
      case RuntimeEvent():
        break;
    }
    _notify();
  }

  void handleVoiceEvent(VoiceEvent event) {
    switch (event) {
      case VoicePartialPresented(:final input):
        _partialTranscript = input.text;
      case VoiceFinalSettled():
        _partialTranscript = null;
        _activeSegment = null;
        activeSession = null;
      case VoiceRecognitionFailed(:final message):
        _voiceError = message;
        _partialTranscript = null;
        _activeSegment = null;
        activeSession = null;
      case VoiceSegmentIgnored():
        break;
    }
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

import 'package:flutter/material.dart';

import 'controller.dart';

/// Microphone controls and the live partial transcript. Not a form field.
class VoiceControlBar extends StatelessWidget {
  final bool listening;
  final String? partialTranscript;
  final String? voiceError;
  final VoidCallback? onListen;
  final VoidCallback? onStop;
  const VoiceControlBar(
      {super.key,
      required this.listening,
      this.partialTranscript,
      this.voiceError,
      this.onListen,
      this.onStop});

  static const listenKey = Key('voice_listen');
  static const stopKey = Key('voice_stop');
  static const partialKey = Key('voice_partial');

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        TextButton(
            key: listenKey,
            onPressed: listening ? null : onListen,
            child: const Text('Listen')),
        TextButton(
            key: stopKey,
            onPressed: listening ? onStop : null,
            child: const Text('Stop')),
      ]),
      if (partialTranscript != null) Text(partialTranscript!, key: partialKey),
      if (voiceError != null) Text(voiceError!),
    ]);
  }
}

/// Shows a runtime clarification. Dismiss does not edit form values.
class ClarificationBanner extends StatelessWidget {
  final String? message;
  final VoidCallback? onDismiss;
  const ClarificationBanner({super.key, this.message, this.onDismiss});

  static const bannerKey = Key('clarification_banner');
  static const dismissKey = Key('clarification_dismiss');

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Row(key: bannerKey, children: [
      Expanded(child: Text(message!)),
      TextButton(
          key: dismissKey, onPressed: onDismiss, child: const Text('Dismiss')),
    ]);
  }
}

/// Assistant chrome around a form the caller builds. This widget has no fields.
class AssistantChrome extends StatelessWidget {
  final FormAssistantController controller;
  final Widget Function(BuildContext context) buildForm;
  const AssistantChrome(
      {super.key, required this.controller, required this.buildForm});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: controller,
        builder: (context, _) =>
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              VoiceControlBar(
                  listening: controller.listening,
                  partialTranscript: controller.partialTranscript,
                  voiceError: controller.voiceError,
                  onListen: controller.beginListening,
                  onStop: controller.stopListening),
              ClarificationBanner(
                  message: controller.clarificationText,
                  onDismiss: controller.dismissClarification),
              buildForm(context),
            ]));
  }
}

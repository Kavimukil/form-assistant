# Phase 9 — Thin Flutter integration

Started 2026-10-22. The assistant package is chrome around a form it does not own.

## Package

`packages/form_assistant_flutter` depends on Flutter and `form_assistant_core`.
It does not depend on the STT package or on any example form.

`FormAssistantController` listens to runtime events and, when a host provides
one, voice events. It does not dispose the runtime or the voice orchestrator.

- A proposal marks mutated fields provisional. `ActionApplied` marks those
  fields accepted. `accentFor` returns an optional color the host can paint
  on its own field.
- A clarification is text. Dismissing it does not write form state.
- `submitText` calls the existing runtime. The input router still decides
  whether the text is deterministic or needs a model.
- A partial transcript is display text. It is not submitted.
- Listen and stop call the host voice orchestrator. This package does not
  open a microphone.

`AssistantChrome` lays out `VoiceControlBar`, `ClarificationBanner`, and the
widget returned by the host's `buildForm`. It builds no text fields.

## Existing form

`examples/flutter_existing_form` is the source form. Its pubspec does not
depend on `form_assistant_flutter`. `ExistingAgeForm` writes
`ExistingFormStore.manualSet('AGE', ...)` from its own `TextFormField`.
An optional `Color` accent is ordinary decoration.

`examples/flutter_assistant_shell` is the optional host. It passes
`ExistingAgeForm` into `AssistantChrome.buildForm`. Removing that shell
leaves the existing form package unchanged.

Core does not import Flutter.

Gate: `flutter test` in `packages/form_assistant_flutter`,
`examples/flutter_existing_form`, and `examples/flutter_assistant_shell`.

Phase 10 production hardening has started. See [Phase 10](../phase10/README.md).

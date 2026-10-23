# Phase 8 — Streaming STT and voice orchestration

Started 2026-10-22. The recognizer and microphone stay with the host.

## Contract

Core exports `STTAdapter`, `STTSession`, PCM16 `AudioChunk`, and the events
partial, final, error, and end. `VoiceInput` carries the transcript and a
transcript confidence. That confidence is not proposal or model confidence.

## Orchestration

`VoiceOrchestrator` listens to a session and submits one final per `segmentId`
through `FormAssistantRuntime`, so the existing input router still decides
whether the text is deterministic or needs the model. The submit trace keeps
the same `segmentId`.

- A partial updates voice state and is not submitted, including while a final
  is already in flight.
- A second final for the same segment is ignored.
- `interrupt` cancels the in-flight interpretation. A final that arrives after
  that cannot commit.
- An STT error marks the voice phase failed and leaves the runtime and bridge
  usable for a manual submit.

## Package

`packages/form_assistant_stt` provides `HostSTTAdapter`. The host pushes PCM16
and injects recognition events. Bytes are counted and dropped unless
`STTSessionConfig.retainAudio` is true. Cancel clears any retained copy.
Nothing in this package opens a microphone.

Gate: `dart test` in `packages/form_assistant_stt`.

Phase 9 thin Flutter chrome has started. See [Phase 9](../phase9/README.md).

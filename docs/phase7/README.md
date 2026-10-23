# Phase 7 — Hybrid/cloud fallback

Started 2026-10-22. The frozen Phase 6R category gate is unchanged and still
fails for Qwen3.8-27B. Phase 7 is permitted because that model passes the
separate acceptance bar of **at least 29/31 complete cases**.

Known local residuals, not sent to cloud merely because they are noisy:

- `noise_compound` commits age 30 instead of 32
- `noise_choice` returns no calls instead of promotion `fall`

The 27B GGUF is a host artifact. Zebra was not measured.

## Package

`packages/form_assistant_cloud`

- `CloudLLMAdapter` decodes one canonical `{"actions":[...]}` object through
  `FormActionCodec`. The host callback owns the network. This package does not
  open a socket.
- `HybridIntelligenceAdapter` composes a local `IntelligenceAdapter` with the
  cloud adapter. Proposals it returns use the hybrid adapter id, so the
  runtime provenance check still holds. `backendId` records which side produced
  the actions.
- `IntelligenceCapabilities` carries `networkAvailable`, `cloudAllowed`, and
  `localModelAvailable`.
- `SensitiveContextPolicy` matches field ids or concepts. A match blocks cloud.
- Both sides receive the same compact `SemanticContext`.

`QualityGate.evaluate` still returns accept or clarify. `considerFallback`
promotes only a non-ambiguous local failure, and only when the caller sets
`allowFallback`. Low confidence, empty answers, invalid values, and the other
existing clarification reasons stay clarify.

## Gate

`dart test` in `packages/form_assistant_cloud` covers:

- offline and `cloudAllowed: false` never call the cloud callback
- a sensitive field or concept never calls the cloud callback
- a missing cloud adapter does not invent a client
- low-confidence clarification does not fall back
- a local failure falls back with the same context and the same interaction,
  request, and operation ids
- cloud actions are canonical `set_value` and commit through `FormStateBridge`
- cancellation does not call cloud

Phase 8 voice orchestration has started. See [Phase 8](../phase8/README.md).

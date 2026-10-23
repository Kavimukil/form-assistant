# Phase 10 — Production hardening

Started 2026-10-22. The host keeps the form store. Core adds measurement,
redaction, and recovery around the existing runtime.

## Telemetry and privacy

`TelemetryPolicy` defaults every flag off. `RedactingTelemetrySink` removes
`utterance`, `text`, `transcript`, `value`, and `values` unless the matching
flag is set. `audio` and `raw` are always removed. Field ids, action names,
failure classes, and stage timings stay.

`TelemetryStage` covers STT, context, model, validation, and commit.
`StageTimer` records those durations. `latencyPercentile` is nearest-rank.

## Failure taxonomy and rates

`observeInteraction` classifies one interaction as deterministic, local model,
fallback, clarification, or unresolved. A correction is a separate flag.
`ProductionMetrics` reports:

- deterministic, local-model, fallback, clarification, and correction rates
- end-to-end state accuracy
- the share of failures attributed to STT, context selection, model, adapter,
  or runtime
- p50 and p95 latency for each stage that was timed

`runtime.context_budget_exceeded` is context selection. `stt.`, `model.`, and
`adapter.` error codes map to those classes. Other runtime errors stay runtime.

## Eval traces

`EvalTraceStore.persist` returns false and stores nothing unless
`persistEvalTraces` is true. With persistence on, utterance text and field
values are still omitted unless their own flags are set.

## Crash recovery

`RecoveryCheckpoint.capture` copies the committed bridge snapshot and the ids
of proposals that were still in flight. `CrashRecovery.resume` accepts only a
restored snapshot with the same form, revision, and values. Abandoned
proposals are not replayed. The existing store remains the authority.

## Protocol 1.0

`ProtocolDocument.decode` accepts `specVersion` `1.0` and canonical actions.
Any other spec version is rejected. Unknown action types still fail in
`FormActionCodec`. The fixture is
`packages/form_assistant_core/test/fixtures/protocol_1_0.json`.

## Tests

`packages/form_assistant_core/test/phase10_gate_test.dart` (9 tests) covers
redaction, eval-trace policy, latency, metrics, recovery, the protocol
fixture, and a 250-step seeded soak that replays identically and does not
commit twice for one value change. The existing 1,000-operation bridge
replays remain in `local_state_bridge_test.dart`.

Integration steps are in [COOKBOOK.md](COOKBOOK.md).

Phase 11 native forms have started. See [Phase 11](../phase11/README.md).

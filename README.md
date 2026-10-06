# Form Assistant Runtime — Production Implementation Plan

Current recovery state: phases 0–5 are complete. Original Phase 6 is superseded by
[Phase 6R](PHASE_6R_RECOVERY_IMPLEMENTATION_PLAN/PHASE_6R_RECOVERY_IMPLEMENTATION_PLAN.md).
See [recovery status](docs/phase6r/PHASE_6R_STATUS.md) and the
[GO/NO-GO decision](docs/phase6r/GO_NO_GO.md). Do not restart phases 0–5 or begin
Phase 7 while recovery is NO-GO.

## Cursor instruction

This repository is an implementation specification. **Implement it; do not redesign it.**

When a TODO is reached:
1. follow the public contracts and invariants in this repository;
2. do not introduce alternative abstractions without a concrete blocker;
3. do not couple core to Flutter widgets, FunctionGemma, STT implementations, source form schemas, or cloud providers;
4. keep each phase independently testable;
5. stop at every gate and make the gate pass before proceeding.

The product is a **schema-agnostic, local-first, voice-driven form-assistant runtime**. V1 targets Flutter/Dart and English. Existing forms are the primary integration path; future runtime-native forms are explicitly supported.

## North star

A new form project must integrate by supplying schema/state adapters. It must **not** require changing core or retraining a model to get started.

## Non-negotiable architecture

- Existing renderer remains authoritative presentation for existing forms.
- Source schema stops at `FormAdapter`.
- `FormIR` is canonical semantic schema.
- `FormAction` is canonical action language.
- `FormStateBridge` is the only form-state read/write boundary.
- Runtime never mutates form values directly.
- Existing forms use `ExternalStateBridge`; existing app/store remains source of truth.
- Future native forms use `LocalStateBridge`; local canonical state is source of truth.
- Runtime must never branch on concrete bridge type; use capabilities.
- AI proposes actions; it never directly changes form state.
- All AI proposals carry the state revision they were based on.
- Bridge performs atomic optimistic-concurrency checking.
- Stale AI proposals are never silently committed.
- Deterministic parsing runs before SLM where reliable.
- Full/raw form schemas are never sent to local/cloud models by default.
- `ContextCompiler` selects compact semantic context.
- FunctionGemma is the first intelligence candidate; model-specific formatting stays behind `IntelligenceAdapter`.
- Needle/cloud/other models must be replaceable without changing runtime contracts.
- No project-specific fine-tuning is required for initial integration; zero-shot is the north star.
- STT is a separate streaming adapter.
- STT partials never commit state.
- STT confidence and model confidence remain separate.
- Cloud fallback is optional and policy/capability controlled.
- Multi-action utterances are first-class.
- Best-effort batches may partially succeed; atomic batches never silently downgrade.
- State and events are distinct.
- Interaction/request/operation/proposal/segment IDs preserve provenance.
- English first; canonical identity must remain language-neutral.
- Flutter first. React/React Native are future bindings, not current scope.
- Public serialized contracts use portable JSON concepts and explicit `specVersion`.
- Do not turn FormIR into a universal widget/backend dump.
- Do not add generic arbitrary ObjectValue/ListValue in v1.

## Repository target

See `docs/02_REPOSITORY_STRUCTURE.md`, `docs/03_CONTRACTS.md`,
`docs/04_PHASED_IMPLEMENTATION.md`, `docs/05_GATES.md`, and
`docs/06_TEST_MATRIX.md`.

Start with Phase 0. Do not start FunctionGemma or voice before the deterministic core and ExternalStateBridge gates pass.

# 04 — Phased Implementation Plan

Cursor must implement in order. Do not skip gates.

## Phase 0 — Repository + contract foundation

Deliver:
- Dart package skeleton and strict analysis options.
- Public barrel exports.
- canonical JSON-safe validator/helpers;
- FormValue hierarchy + strict codec;
- FormAction hierarchy + strict codec;
- structural equality/hashCode;
- validation metadata;
- FormIR minimum V1 + codec;
- protocol `specVersion = "1.0"`;
- tests and golden canonical JSON fixtures.

Do NOT implement Flutter UI, STT, model inference or cloud.

Gate P0: all contract tests/goldens pass; malformed JSON is rejected; no Flutter dependency in core.

## Phase 1 — Local deterministic state engine

Deliver:
- FormStateSnapshot and bridge capabilities;
- ApplyContext/results/events;
- LocalFormStateBridge;
- optimistic revision checks;
- set/clear/navigation where capability allows;
- no-op detection;
- atomic and best-effort batches;
- ordered event publication;
- undo/redo history;
- immutable snapshots/collections;
- validation against FormIR.

Gate P1:
- stale write can never overwrite current state;
- atomic rollback verified;
- atomic batch increments revision once;
- best-effort partial success verified;
- no-op doesn't increment;
- event/snapshot ordering verified;
- undo/redo deterministic;
- randomized action sequence tests preserve invariants.

## Phase 2 — External state integration SPI

Deliver:
- reusable external bridge support primitives, but no assumptions about source store technology;
- example fake ExistingFormStore;
- ProjectExample FormAdapter;
- ProjectExample ExternalStateBridge;
- canonical snapshot mapper;
- canonical -> external mutation mapper;
- external subscription/diff;
- pending operation correlation using operationId;
- acknowledgement/timeout/error behavior;
- existing external store remains authoritative.

Gate P2:
- assistant-originated write produces exactly one semantic revision;
- its echoed store notification is not double-counted;
- manual/external store write becomes `origin: external`;
- async acknowledgement only returns ActionApplied after authoritative commit;
- external overwrite wins;
- stale concurrent write rejected;
- dispose unsubscribes cleanly;
- 1,000 mixed internal/external simulated operations show no revision/event corruption.

**This is the primary integration gate for existing forms.**

## Phase 3 — Headless ActionRuntime + runtime state/events

Deliver:
- FormAssistantRuntime;
- ActionRuntime routing by classification;
- runtime state separate from bridge state;
- trace context;
- runtime event map;
- proposal execution;
- stale proposal policy;
- capability checks;
- clarification routing;
- navigation routing;
- no intelligence implementation yet: MockIntelligenceAdapter only.

Stale policy:
1. proposal current -> validate and execute;
2. stale -> inspect latest snapshot and semantic dependencies;
3. if relevant context changed -> discard/reinterpret;
4. otherwise revalidate against latest state and apply using latest expected revision;
5. bridge remains final concurrency guard.

Gate P3:
- runtime never accesses concrete bridge type;
- runtime never mutates values outside bridge;
- mutation/navigation/control actions route correctly;
- stale race between runtime check and bridge commit is caught;
- complete trace IDs survive proposal -> commit;
- mock multi-action utterance can partially apply and request clarification.

## Phase 4 — Deterministic InputRouter

Deliver parsers for:
- yes/no;
- integers/numbers;
- exact choice;
- conservative fuzzy choice;
- clear/correction phrases where unambiguous;
- navigation phrases where unambiguous.

Router result must explain whether it resolved deterministically, needs intelligence, or needs clarification.

Do not over-expand NLP. False positive deterministic commits are worse than SLM invocation.

Gate P4:
- deterministic suite has near-zero ambiguous false commits;
- supported trivial answers avoid intelligence;
- unsupported/ambiguous input falls through without mutation.

## Phase 5 — ContextCompiler

Deliver internal `ContextCompiler`:
- active field;
- candidate fields;
- rule/dependency-relevant fields;
- recent changed/unanswered fields;
- canonical current values;
- bounded interaction history;
- hard configurable budgets by field count and estimated tokens/chars;
- deterministic selection diagnostics for evaluation.

Do not expose algorithm publicly.

Gate P5:
- 5,000-field synthetic FormIR never passes whole form;
- context budget is respected;
- current field is retained;
- known dependency/reference fixtures retrieve required fields;
- no source schema leaks into context.

## Phase 6 — Intelligence contract + FunctionGemma adapter

Deliver:
- complete IntelligenceAdapter types;
- Mock adapter;
- FunctionGemma adapter package;
- inference backend interface internal to FunctionGemma package;
- model-specific prompt/tool schema formatter;
- strict output parser -> canonical ProposedAction;
- model confidence/provenance kept outside FormAction/FormValue;
- QualityGate;
- cancellation/timeouts;
- no fine-tuning.

FunctionGemma must not receive source schema. It receives SemanticContext + allowed canonical actions.

Gate P6 evaluation corpus:
- simple answer;
- multi-field;
- correction;
- negation;
- ambiguity;
- out-of-order;
- previous-field reference;
- invalid value;
- unsupported;
- no answer;
- long utterance;
- noisy/ASR-like transcript.

Primary metric: final canonical FormState correctness, not JSON validity.

No cloud yet.

## Phase 7 — Hybrid/cloud fallback

Status: started 2026-10-22. Local-first package `form_assistant_cloud`.
The host supplies transport. See [phase7/README.md](phase7/README.md).

Deliver:
- CloudLLMAdapter;
- HybridIntelligenceAdapter by composition;
- QualityGate outcomes ACCEPT/FALLBACK/CLARIFY;
- capability/policy object: networkAvailable, cloudAllowed, localModelAvailable;
- sensitive-context policy;
- identical compact SemanticContext boundary for local/cloud;
- fallback events/provenance.

Gate P7:
- cloud disabled/offline never causes hidden dependency;
- sensitive context prohibited from cloud;
- ambiguous input clarifies instead of blindly falling back;
- fallback preserves interaction/proposal tracing;
- local and cloud produce same canonical action protocol.

## Phase 8 — Streaming STT + voice orchestration

Status: started 2026-10-22. Contract and `VoiceOrchestrator` are in core.
`form_assistant_stt` is the host session and does not capture the microphone.
See [phase8/README.md](phase8/README.md).

Deliver:
- STTAdapter/session contract;
- PCM16 AudioChunk;
- partial/final/error/end;
- VoiceInput;
- voice runtime state;
- final transcript -> InputRouter;
- partial transcript -> presentation only;
- transcript confidence separate from intelligence confidence;
- segmentId provenance;
- cancellation/interruption handling.

Gate P8:
- partial transcript cannot mutate state even under race;
- final segment exactly once enters interpretation;
- cancelled segment cannot later commit;
- STT error leaves manual form usable;
- audio is not retained/logged by default.

## Phase 9 — Thin Flutter integration

Status: started 2026-10-22. `form_assistant_flutter` is chrome only.
`examples/flutter_existing_form` does not depend on it. See
[phase9/README.md](phase9/README.md).

Deliver `form_assistant_flutter`:
- provider/controller integration as appropriate;
- listen to runtime state/events;
- voice controls;
- clarification surface;
- accepted/provisional field highlighting hooks;
- no form renderer replacement;
- example integrating with an existing Flutter form/store.

Gate P9:
Remove assistant package from example and existing form must still function normally.
Assistant package must not own source form UI.

## Phase 10 — Production hardening

Status: started 2026-10-22. Telemetry, redaction, latency, failure rates,
eval-trace policy, and crash recovery are in core. See
[phase10/README.md](phase10/README.md).

Deliver:
- structured telemetry interfaces;
- privacy/redaction defaults;
- performance timings;
- failure taxonomy;
- persisted eval traces only under explicit policy;
- fuzz/property tests;
- soak tests;
- crash recovery strategy;
- compatibility fixtures for protocol 1.0;
- package docs/API docs;
- example integration cookbook.

Measure:
- deterministic resolution rate;
- local model rate;
- fallback rate;
- clarification rate;
- end-to-end state accuracy;
- STT error contribution;
- context-selection error contribution;
- model error contribution;
- adapter/runtime error contribution;
- p50/p95 STT, context, model, validation, commit latency;
- correction rate.

## Phase 11 — Future native form platform (not V1 blocker)

Status: started 2026-10-23. Visibility rules, a step workflow, and a Flutter
renderer sit on `LocalFormStateBridge`. Manual edits use `commitNative`.
See [phase11/README.md](phase11/README.md).

Build on LocalFormStateBridge:
- richer rules/workflow;
- renderer contract;
- Flutter renderer;
- richer canonical field types only when demanded by real use cases.

AI remains optional. Manual UI and AI use same ActionRuntime/state path.

## Phase 12 — Future multilingual / React (not V1 blocker)

Status: started 2026-10-23. Localized labels stay off canonical actions.
English routing is unchanged. A non-English lexicon can commit the same
action types. The React package only decodes protocol 1.0 JSON.
See [phase12/README.md](phase12/README.md). This is the last phase in the
written plan.

Multilingual:
- localized semantics;
- multilingual STT/intelligence;
- code-switch evaluation;
- canonical actions unchanged.

React:
- publish language-independent schemas;
- implement TS core/bindings only if product requires it;
- do not redesign protocol around React.

# 01 — Architecture Decisions

## System shape

```text
                         SOURCE FORM SCHEMA
                                |
                            FormAdapter
                                |
                              FormIR
                                |
                        ContextCompiler
                                |
 UserInput ---> InputRouter ----+----------------------+
   ^             |                                     |
   |             +--> deterministic                   |
   |                                                   v
 STTAdapter                                      IntelligenceAdapter
   ^                                               |
 microphone                                  FunctionGemmaAdapter
                                                   |
                                              QualityGate
                                               /       \
                                           ACCEPT      FALLBACK
                                                        |
                                                  Cloud adapter
                                                   |
                                             ActionProposal
                                                   |
                                              ActionRuntime
                                                   |
                                             FormStateBridge
                                             /             \
                                  ExternalStateBridge   LocalStateBridge
                                         |                  |
                                  existing app store   canonical state
                                         |                  |
                                  existing renderer   future renderer
```

Cross-cutting: trace/provenance, evaluation, observability, capability policy.

## Ownership

### Existing forms — primary V1
Existing application/store is authoritative. `ExternalStateBridge` maps canonical actions into existing state mutations and observes existing state changes back into canonical snapshots.

### Future native forms
`LocalStateBridge` owns canonical values, revision, history and transactions. A future renderer can project this state. No intelligence code changes.

## FormAdapter vs state
`FormAdapter` compiles source schema into FormIR. It does **not** own live state.
`FormStateBridge` owns the live state boundary. Do not reintroduce `importState/exportState` into FormAdapter.

## Action routing
`FormAction` is the model/runtime command vocabulary.
- mutation -> FormStateBridge
- navigation -> navigation handler / bridge capability
- assistant control -> interaction runtime
- future privileged actions -> authorization pipeline

Clarification is not a state mutation.

## Revision
Revision represents committed semantic form state. Failed writes, no-ops, focus changes, spinners and presentation-only changes do not increment it.
Atomic batch = one semantic commit = one revision increment.
Best-effort batch may increment once per successful commit.
Revision is bridge-lifecycle scoped, not globally unique.

## Stale proposals
Proposal records `baseRevision`.
Runtime checks it before execution, but bridge must also atomically compare `expectedRevision` at commit time.
Bridge only reports stale revision; runtime decides revalidate/reinterpret.
V1 policy:
1. if proposal is current -> validate/apply;
2. if stale -> obtain latest snapshot;
3. if touched fields, relevant dependencies, or selected semantic context changed -> discard and reinterpret original input;
4. otherwise revalidate proposal against latest snapshot and apply using latest expected revision;
5. never force stale write.

## External bridge acknowledgement
`ActionApplied` means authoritative external state has actually committed.
A bridge-originated store notification must be correlated with its pending `operationId` and counted exactly once.
Uncorrelated store changes become `StateChanged(origin: external)`.
The external store always wins.

## Intelligence
FunctionGemma first. Do not fine-tune initially. Adapter translates model-specific tool output into canonical actions. Canonical JSON must never be changed to match a model's preferred output.

## Context
Never pass entire huge FormIR by default. ContextCompiler selects active/relevant/dependent/recent fields, current canonical values and small interaction history. Retrieval strategy is internal.

## Voice
Streaming STT. Partial = preview only. Final = eligible for interpretation.
Preserve audio segment ID -> transcript -> semantic context -> intelligence request -> proposal -> validation -> commit/correction.

## Multilingual
V1 English. IDs/concepts are language-neutral. Do not make English labels identity. Later support native multilingual inference and code switching without changing canonical actions.

## Versioning
Package API: SemVer, remain 0.x until stable.
Serialized contracts: `specVersion` MAJOR.MINOR.
1.0 -> 1.1 additive/backward-compatible.
1.x -> 2.0 breaking.
Unknown optional fields ignored.
Required new behavior uses `requiredCapabilities`.
Extensions are namespaced and core preserves/ignores unknown extensions.

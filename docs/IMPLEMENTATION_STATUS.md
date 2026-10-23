# Implementation Status

Status: **Phases 0–5 GREEN; original Phase 6 superseded; Phase 6R recovery implemented/reviewed. Frozen category gate remains NO-GO. Phase 7 started 2026-10-22 under a 29/31 complete-case acceptance of Qwen3.8-27B. Phase 8 voice orchestration started 2026-10-22. Phase 9 thin Flutter chrome started 2026-10-22. Phase 10 production hardening started 2026-10-22. Phase 11 native forms started 2026-10-23. Phase 12 multilingual semantics and React bindings started 2026-10-23. Phase 12 completes the written plan.**

Verified: 2026-10-06, Dart SDK 3.13.5 stable.
Current completed foundation: Phase 5 — Internal ContextCompiler.
Current recovery: Phase 6R — constrained extraction implemented; model-quality gate FAILED.
See [task status](phase6r/PHASE_6R_STATUS.md) and [decision](phase6r/GO_NO_GO.md).

## Phase 0 completed deliverables

- Dart package `packages/form_assistant_core`, version 0.1.0, with public barrel exports and no production dependencies.
- Repository analysis options enable strict casts, inference and raw types, with additional correctness lint rules.
- Portable JSON validation, cycle rejection, recursive immutable copying, structural comparison and hashing helpers.
- All seven FormValue variants and strict codec; finite numbers, real calendar dates, preserved strings, canonical choice IDs and sorted/deduplicated multi-choice sets.
- FormAction hierarchy, classifications, navigation targets, clarification actions and strict codec; structural equality/hashCode.
- Validation issues and validation metadata with serialization, strict decoding, revision preservation, JSON-safe immutable metadata and structural equality/hashCode.
- Minimum V1 FormIR, value definitions, semantics, constraints, options, codec and schema-only FormAdapter contract.
- Protocol version constant `1.0`; serialized FormIR requires explicit specVersion and preserves compatible 1.x versions.
- Immutable public collections, omitted optional null properties, preserved unknown extensions, ignored unknown optional fields and rejected unknown discriminators.
- Golden JSON fixtures for values/actions, FormIR and validation metadata; 31 contract tests.
- Package usage documentation and reproducible development dependency lockfile.

## Phase 0 commands and results

Dart was not installed in PATH. SDK downloaded to `/tmp/form-assistant-sdk/dart-sdk`; commands below used its `bin/dart` executable.

| Command | Working directory | Result |
| --- | --- | --- |
| `dart pub get` | `packages/form_assistant_core` | PASS — test dependencies resolved |
| `dart format packages` | Repository root | PASS — all 9 Dart files formatted |
| `dart format --output=none --set-exit-if-changed packages` | Repository root | PASS — 0 changes, exit 0 |
| `dart analyze` | Repository root | PASS — no issues found, exit 0 |
| `dart test` | `packages/form_assistant_core` | PASS — all 31 tests, exit 0; this is the repository's only Dart package |
| `git diff --check` | Repository root | PASS |

## Phase 0 gate results

| Phase 0 requirement | Result |
| --- | --- |
| Contract tests and canonical goldens pass | GREEN |
| Malformed JSON rejected without silent coercion | GREEN |
| Finite numbers and real calendar dates enforced | GREEN |
| Structural equality/hashCode and canonical unordered sets | GREEN |
| Immutable public collections and recursively JSON-safe metadata | GREEN |
| Optional nulls omitted, protocol version explicit | GREEN |
| No Flutter dependency in core | GREEN — no production dependencies |
| Scope remains phase 0 | GREEN — no state engine, bridge implementation, runtime, models, STT, cloud or Flutter bindings |

## Phase 0 specification clarifications and deviations

No architecture deviations.

- Concrete inconsistency: seed value/action schemas rejected all additional properties, while normative `docs/01_ARCHITECTURE_DECISIONS.md` requires unknown optional fields to be ignored. Updated seed schemas to allow additional properties to match that normative compatibility rule and the codecs. Known properties and discriminators remain strictly checked.
- Validation constructors defensively copy collections rather than retaining the sample's `const` constructors; retaining caller-owned mutable collections would fail the normative immutability gate. Fields and contract semantics are unchanged.
- `contracts/schemas/README.md` assigns state/event schemas to Phase 0/1. Those schemas are deferred to Phase 1 alongside their state/event contracts, consistent with the explicit Phase 0 scope and the instruction not to begin Phase 1.

## Phase 1 completed deliverables

- Normative FormStateSnapshot, bridge capabilities, ApplyContext, FormStateBridge interface, action/batch results and bridge events, exported through the public barrel.
- Immutable snapshots, result/event collections and recursively JSON-safe rejection details; structural equality/hashCode and strict serialized codecs for the new contracts.
- LocalFormStateBridge owns canonical values, revision and history. A serialized operation queue combines expectedRevision checking with planning/commit and serializes entire logical batches, history operations and disposal.
- Set/clear/navigation, capability and lifecycle checks, unknown-field/type rejection, canonical option membership and all V1 field constraints.
- No-op detection; focus-only changes never increment semantic revision or create history.
- Atomic batches validate private candidate state before committing values/focus together; all successful applied results share previous/final revisions and final snapshot. No atomic downgrade.
- Best-effort batches report individual results and partial success; successful semantic commits increment separately.
- Snapshot publication precedes synchronous ordered StateChanged/ActiveFieldChanged events and completion notifications. Initialization ordering is covered even when a listener attaches after a write is queued. Reentrant writes are queued safely.
- Undo/redo per semantic commit, atomic history units, deterministic origins, stale guards, redo invalidation and preserved focus.
- Ordered/idempotent disposal, stream closure and rejection of later operations.
- Added versioned form-state and bridge-event JSON schemas, canonical state/event/result/batch goldens and a schema verification tool.
- Added 21 state-engine tests (including five seeded model tests) and eight bridge-contract tests. Phase 0's 31 tests remain green.
- Updated package and schema documentation with API usage, precise behavior and verification commands.

## Phase 1 commands and results

Verified with Dart SDK 3.13.5 stable via `/tmp/form-assistant-sdk/dart-sdk/bin/dart`.

| Command | Working directory | Result |
| --- | --- | --- |
| `dart format packages` | Repository root | PASS — 17 Dart files formatted |
| `dart format --output=none --set-exit-if-changed packages` | Repository root | PASS — 0 changes, exit 0 |
| `dart analyze` | Repository root | PASS — no issues found, exit 0 |
| `dart test` | `packages/form_assistant_core` | PASS — all 60 tests, exit 0; all repository Dart packages covered |
| `python3 tools/check_contract_schemas.py` | Repository root | PASS — four schemas, 42 golden/malformed-input checks, exit 0 |
| `git diff --check` | Repository root | PASS |

The five independent reference-model tests use seeds 0, 1, 7, 42 and 2026, with
1,000 operations each. They check set/clear, atomic and best-effort batches,
rollback, stale writes, undo/redo, immutable state, revision monotonicity and
reconstruction of authoritative state from field-change events.

## Phase 1 gate results

| Requirement | Result |
| --- | --- |
| Stale writes cannot overwrite current state | GREEN — concurrent winner/loser and randomized stale-write checks |
| Atomic rollback | GREEN — values, focus and history unchanged; no speculative state events |
| Atomic commit increments once | GREEN — shared previous/final revisions and one state event |
| Best-effort partial success | GREEN — independent results/commits and per-commit history |
| No-op/failure never increments revision | GREEN — unchanged values, empty batches and atomic net no-op covered |
| Event/snapshot ordering | GREEN — synchronous observer, initialization race and reentrant-operation checks |
| Undo/redo deterministic | GREEN — transaction history, provenance, stale guards and redo invalidation |
| Randomized invariant checks | GREEN — 5,000 operations against an independent state/history model |
| FormIR validation | GREEN — all seven value kinds, bounds, lengths, patterns, required and canonical choices |
| Immutable contracts and strict codecs/goldens | GREEN — defensive copying, nested JSON safety and malformed types checked |
| Architecture boundary | GREEN — core imports only Dart SDK/local contracts; no production dependencies |
| Phase scope | GREEN — no external integration, runtime routing, models, STT, cloud or Flutter bindings |

## Phase 1 specification clarifications and deviations

No architecture deviations or alternative state/runtime abstractions.

- Concrete contract omission: undo/redo return ActionResult, which requires one FormAction, but history can restore a multi-field atomic commit and the action vocabulary has no history action. Kept the vocabulary unchanged: the result names the first restored field in canonical ID order; the complete snapshot and StateChanged contain all restored values. Empty/disabled history returns capabilityUnavailable with a diagnostic focus action that is never executed. No UndoApplied/RedoApplied event types were introduced.
- Empty history has no specified NoOpReason, so it is reported as capabilityUnavailable without changing revision. Capability-disabled history uses the same existing rejection code.
- Required constraints reject clearing or empty required answers. Initial partial forms may omit unanswered fields; undo may restore such a previously valid partial snapshot. History restores values while preserving current focus.
- Atomic actions are evaluated in order in private state. A batch that returns values to the starting state is a semantic no-op; only final focus is published. These choices follow the semantic-revision invariant and are documented and tested.
- Constructors containing collections defensively copy rather than retaining the sample's const constructors, as required by the immutable-public-collections gate.
- State/event schemas deferred at the Phase 0 stop are now delivered. Snapshot/event roots carry specVersion 1.0 and explicit event discriminators; UTC timestamps serialize the existing DateTime fields. BridgeError.cause is never serialized.

## Phase 2 completed deliverables

Scope clarified by the user: **implement Phase 2 only**. Phase 3 was not started.

- Reusable, technology-independent ExternalStateSource integration port, immutable source snapshot/receipt primitives and generic ExternalStateBridge implementing the unchanged FormStateBridge contract.
- Pure canonical snapshot and source mutation mapping callbacks; concrete source-project schema/store classes stay entirely in the external integration example.
- Source-owned commit-time compare-and-apply with an independent source version token. Canonical expectedRevision and source version checks guard bridge and authoritative commits respectively, including delayed requests and source presentation/focus races.
- Ordered external subscription/diff, canonical immutable snapshots, operationId correlation, authoritative notification/receipt acknowledgement and duplicate/older version suppression.
- Pending write correlation is established before dispatch. ActionApplied requires actual authoritative acknowledgement, never acceptance or provisional canonical values.
- Uncorrelated manual changes become StateChanged(origin: external). External overwrites win; older receipts cannot roll back the projection.
- Acknowledgement timeouts, late receipts, store/subscription failures and mapper failures return existing rejection codes and emit existing diagnostic BridgeError types.
- Capability-aware set/clear/navigation and atomic/best-effort batches. Atomic support reflects actual source transactions; no local emulation or silent downgrade. External changes during best-effort batches stop remaining stale edits.
- Disposal unsubscribes, releases pending waits, closes bridge events and rejects later operations without disposing the existing store.
- Runnable Dart example package at `examples/external_form_integration`, including ExistingFormStore, ProjectExampleFormAdapter and ProjectExampleExternalStateBridge. Its store uses Y/N booleans, distinct source/canonical field IDs and option keys; all seven V1 value kinds are covered.
- Thirty external integration tests, including the required 1,000-operation mixed assistant/external simulation against independent canonical state, revision and event replay expectations.
- Package/example integration documentation and example dependency lockfile. Core retains no production dependencies; example depends only on core.

## Phase 2 commands and results

Verified on 2026-10-05 with Dart SDK 3.13.5 stable through
`/tmp/form-assistant-sdk/dart-sdk/bin/dart`.

| Command | Working directory | Result |
| --- | --- | --- |
| `dart pub get --offline` | `examples/external_form_integration` | PASS — example dependencies resolved from existing cache |
| `dart format packages examples` | Repository root | PASS — all 24 Dart files formatted |
| `dart format --output=none --set-exit-if-changed packages examples` | Repository root | PASS — 0 changes, exit 0 |
| `dart analyze` | Repository root | PASS — no issues found, exit 0 |
| `dart test --reporter expanded` | `packages/form_assistant_core` | PASS — all 60 tests, exit 0 |
| `dart test --reporter expanded` | `examples/external_form_integration` | PASS — all 30 tests, exit 0 |
| `dart run bin/main.dart` | `examples/external_form_integration` | PASS — assistant write maps to existing Y/N state, manual change projects as external, existing store remains usable after bridge disposal |
| `python3 tools/check_contract_schemas.py` | Repository root | PASS — all four schemas and 42 fixture/malformed-input checks, exit 0 |
| `git diff --check` | Repository root | PASS |

**All repository Dart packages tested: 90 tests passed.** Phase 0/1 regressions,
including the existing 5,000 local randomized operations, remain green.

## Phase 2 gate results

| Requirement | Result |
| --- | --- |
| Assistant write produces exactly one semantic revision | GREEN — all value mappings and source transaction acknowledgement checked |
| Echoed notification is not double-counted | GREEN — notification-first, receipt-first, duplicate and older receipt checks |
| Manual/external writes use origin external | GREEN — canonical values/focus/lifecycle projected from source |
| ActionApplied only after authoritative commit | GREEN — held commit barrier leaves source/canonical values unchanged; committed notification or receipt acknowledges once |
| External overwrite wins | GREEN — delayed commit race, older receipt and reentrant overwrite checks |
| Concurrent stale write rejected | GREEN — commit-time CAS, two bridges, stale revisions and presentation-only source races |
| Dispose unsubscribes cleanly | GREEN — pending waits released, no later bridge events, manual store still usable |
| 1,000 mixed internal/external operations without revision/event corruption | GREEN — seed 2026, independent state/revision model and event replay |
| Atomic mode never silently downgrades | GREEN — actual source transaction, rollback-before-dispatch, unsupported-atomic rejection |
| No-op/failure does not increment revision | GREEN — no-op edits, source failures, empty/unchanged semantic state and presentation changes |
| Architecture boundary | GREEN — no concrete project types/imports in core; no Flutter/provider dependencies |
| Phase scope | GREEN — no runtime routing, inference, STT, cloud or Flutter bindings |

## Phase 2 specification clarifications and deviations

No architecture deviations or changes to canonical serialized contracts.

- Concrete contract omission: the public FormStateBridge contract does not specify the source-store subscription, authoritative receipt or commit-time concurrency boundary needed by Phase 2. Added only the required runtime-only external integration SPI. It exposes a monotonically increasing source version and atomic compare-and-apply; wrappers may implement these guarantees around any store technology. The source version is never a canonical semantic revision and is not added to canonical JSON.
- Authoritative notifications and committed receipts are both acknowledgements. operationId and expected canonical touched values/focus establish correlation. Duplicate and older source versions are ignored. Source wrappers must preserve commit/notification ordering and immutable receipts.
- No acknowledgement-timeout enum exists in the normative contract. Timeout uses ActionRejectionCode.conflict, detail code `bridge.acknowledgement_timeout`, and BridgeErrorCode.operationFailure. Timed-out requests are not retried/force-written; subsequently observed commits without pending correlation are external.
- The example source has no authoritative history API. Undo/redo capabilities are explicitly false, and calls return capabilityUnavailable; no parallel local history was introduced for an externally owned form.
- Source lifecycle changes are semantic and increment revision with an empty changes list when values do not change. Focus/spinner changes do not increment canonical revision, although their source versions can invalidate pending source writes.
- Canonically representable manual values remain authoritative even if they violate assistant edit constraints. An unrepresentable source encoding emits mappingFailure, retains the last valid projection and blocks writes until a valid source snapshot arrives. Subscription failure/closure blocks writes until a new bridge/subscription is created. No malformed source values are silently coerced or accepted into canonical contracts.
- Disposing a bridge cannot undo a request already dispatched to an independently owned store. It releases bridge waits and unsubscribes; the source's commit-time CAS continues to prevent delayed requests from overwriting newer source state.

## Phase 3 completed deliverables

- FormAssistantRuntime and ActionRuntime exported from the dependency-free core; the runtime uses only FormStateBridge, canonical FormIR/actions and capabilities.
- Classification-based mutation/navigation routing through the bridge, assistant-control clarification routing through runtime events/state, and fresh canonical constraint/capability validation. Proposal-supplied validation is not trusted.
- RuntimeState, RuntimeInteractionResult and typed runtime event map remain separate from authoritative bridge state. No runtime-owned form value store.
- TraceContext preserves interaction/request/operation/proposal/action/segment IDs; RuntimeBridgeEvent enriches canonical bridge events without changing bridge JSON. Proposal provenance origin reaches ApplyContext unchanged.
- Immutable mock intelligence requests/context/proposals, normative IntelligenceAdapter interface and MockIntelligenceAdapter as the only implementation.
- Current proposal execution, unrelated stale revalidation against latest expectedRevision, relevant stale discard/reinterpretation using original input, and bounded retry handling. Touched fields, explicit context/dependencies, focus and lifecycle are compared to the original snapshot.
- Bridge remains final commit-time concurrency guard. Partial commit races stop remaining edits and request clarification without replaying accepted actions. Atomic execution delegates one actual bridge transaction and never downgrades.
- Serialized submissions, published-before-event runtime state, interpreter error reporting, pending interpretation cancellation on runtime/bridge disposal, and caller-owned bridge lifetime.
- 24 core runtime tests and two external runtime integration tests, including full trace propagation, forged proposal rejection, disposal, selected/dependency changes, inference races, partial acceptance and atomic rollback.
- Public API and stale/partial-execution behavior documented in the core package README.

## Phase 3 commands and results

Commands use `/tmp/form-assistant-sdk/dart-sdk/bin/dart`.

| Command | Working directory | Result |
| --- | --- | --- |
| `dart format packages examples` | Repository root | PASS — 31 Dart files formatted |
| `dart format --output=none --set-exit-if-changed packages examples` | Repository root | PASS — 0 changes, exit 0 |
| `dart analyze` | Repository root | PASS — no issues found, exit 0 |
| `dart test --reporter expanded` | `packages/form_assistant_core` | PASS — all 84 tests, exit 0 |
| `dart test --reporter expanded` | `examples/external_form_integration` | PASS — all 32 tests, exit 0 |
| `python3 tools/check_contract_schemas.py` | Repository root | PASS — four schemas and 42 fixture/malformed-input checks, exit 0 |
| `git diff --check` | Repository root | PASS |

**All repository Dart packages tested: 116 tests passed.** Previous contract,
bridge and 6,000 randomized local/external operation checks remain green.

## Phase 3 gate results

| Requirement | Result |
| --- | --- |
| Runtime never accesses concrete bridge type | GREEN — interface/capability routing; source scan and both bridge integrations |
| Runtime never mutates values outside bridge | GREEN — all mutation/navigation calls delegate through FormStateBridge; runtime state contains interaction data only |
| Mutation/navigation/control route correctly | GREEN — local execution, external store execution, capabilities and atomic routing |
| Race between runtime check and bridge commit caught | GREEN — commit barrier forces stale rejection; bounded retry or safe clarification follows |
| Complete trace IDs survive proposal to commit | GREEN — single-action and atomic bridge event wrappers preserve full trace and original operation ID |
| Mock multi-action utterance partially applies and requests clarification | GREEN — valid action commits, invalid action rejects with fresh validation, clarification reaches runtime state/event |
| Unrelated stale change revalidates | GREEN — latest expectedRevision applied without another mock call |
| Relevant stale change reinterprets | GREEN — touched/selected/dependency values, focus and manual external inference race |
| Atomic execution never downgrades or emits premature clarification | GREEN — capability rejection and validation rollback before bridge invocation |
| Phase scope | GREEN — MockIntelligenceAdapter only; no deterministic router, context compiler algorithm, inference, STT, cloud or Flutter bindings |

## Phase 3 specification clarifications and deviations

No architecture redesign or changes to existing canonical serialized contracts.

- Concrete contract omissions: the specification names UserInput, FormFieldContext, ActionProvenance, IntelligenceResult and IntelligenceOptions without complete definitions. Added minimal immutable runtime boundaries needed by the normative request/proposal/interface; IntelligenceOptions remains an empty reserved type until Phase 6.
- IntelligenceRequest carries TraceContext so a mock proposal can preserve request/operation/segment provenance. Canonical actions remain identity-free; existing ApplyContext and bridge event contracts are unchanged. RuntimeBridgeEvent carries the additional request/segment/action trace.
- Phase 5 owns ContextCompiler. Phase 3 selects only caller-specified canonical field/dependency IDs plus the active field; no selection, budget or inference algorithm is implemented. Explicit dependency IDs support the required stale policy without starting Phase 5.
- Reinterpretation is bounded to two retries by default. A partial stale execution does not replay already accepted actions; it stops remaining edits and requests clarification. An exhausted retry returns a runtime error instead of forcing a write.
- Runtime events/helper types have no newly declared portable codec/schema beyond TraceContext's versioned JSON representation. Existing canonical contract schemas/goldens remain unchanged; model serialization and broader intelligence options stay in their assigned later phase.

## Phase 4 completed deliverables

- Pure, exported InputRouter and immutable InputRouterResult with three explicit outcomes: deterministic, needsIntelligence and needsClarification. Every result carries a reason code; non-deterministic results contain no mutation actions.
- Whole-utterance active-field parsing for English yes/no variants, signed integer/decimal digits, zero-through-ninety-nine number words, signed number words and spoken decimal digits.
- Exact option ID/label/alias matching produces canonical choice IDs. Multi-choice accepts one explicit option; compound answers fall through.
- Conservative fuzzy choice: one insertion/deletion/substitution on single ASCII words of at least five letters, requiring no other option within two edits. Alias collisions, close fuzzy competitors and command/choice collisions clarify.
- Narrow active-field clear and single-answer correction phrases; exact next/previous navigation phrases. No field-name/reference resolution or general NLP.
- Router runs before intelligence in FormAssistantRuntime.submit and on stale reinterpretation. Deterministic/clarification proposals use the existing ActionRuntime path with captured revision, full trace and origin deterministic. Unsupported inputs use the unchanged mock intelligence boundary.
- InputRouted event reports the decision. Recognized invalid values route to invalidValue clarification without writes; capabilities and commit-time concurrency remain enforced by runtime/bridge.
- Fourteen core router/runtime tests and one additional external integration test. Coverage includes 150 adversarial utterance/field combinations with zero deterministic resolutions, aliases, fuzzy margins, corrections, malformed numeric input, bounds, immutable results, mock bypass, clarification, unsupported fallthrough and a forced deterministic commit race.
- Updated public package documentation with grammar, fuzzy policy, trace/stale behavior and unsupported cases.

## Phase 4 commands and results

Commands use `/tmp/form-assistant-sdk/dart-sdk/bin/dart`.

| Command | Working directory | Result |
| --- | --- | --- |
| `dart format packages examples` | Repository root | PASS — 33 Dart files formatted |
| `dart format --output=none --set-exit-if-changed packages examples` | Repository root | PASS — 0 changes, exit 0 |
| `dart analyze` | Repository root | PASS — no issues found, exit 0 |
| `dart test --reporter expanded` | `packages/form_assistant_core` | PASS — all 98 tests, exit 0 |
| `dart test --reporter expanded` | `examples/external_form_integration` | PASS — all 33 tests, exit 0 |
| `python3 tools/check_contract_schemas.py` | Repository root | PASS — four schemas and 42 fixture/malformed-input checks, exit 0 |
| `git diff --check` | Repository root | PASS |

**All repository Dart packages tested: 131 tests passed.** Earlier phases and
6,000 randomized local/external operations remain green.

## Phase 4 gate results

| Requirement | Result |
| --- | --- |
| Near-zero ambiguous false deterministic commits | GREEN — zero deterministic resolutions across 150 adversarial utterance/field combinations; alias, fuzzy and command collisions clarify |
| Supported trivial answers avoid intelligence | GREEN — typed answers, local runtime trace/origin assertions and external authoritative commit with zero mock calls |
| Unsupported/ambiguous input falls through without mutation | GREEN — pure results contain no actions; unsupported reaches mock, identified ambiguity clarifies, both preserve values/revision |
| Canonical choice identity | GREEN — labels/aliases resolve to canonical option IDs; single-option multi-choice uses MultiChoiceValue |
| Existing concurrency/capability boundaries retained | GREEN — forced deterministic commit race reroutes, previous runtime/bridge tests remain green |
| Architecture and phase scope | GREEN — no concrete bridge checks, direct runtime writes, source schema access, production dependencies, ContextCompiler, model, STT, cloud or Flutter additions |

## Phase 4 specification clarifications and deviations

No architecture redesign or canonical serialized contract changes.

- The specification names InputRouter and its three outcomes but gives no public signature/result fields or exact English grammar. Added only the required pure router boundary, immutable result, reason codes and runtime event; existing proposal/action/state contracts are reused.
- Deliberately bounded grammar: English number words cover zero through ninety-nine plus signed/spoken decimals. Larger spelled numbers, units, grouping separators, scientific notation, general strings/dates, multi-choice combinations and references fall through to intelligence. Numeric digits remain supported within finite/portable integer limits. This follows the instruction to avoid broad NLP and prioritize avoiding false commits.
- Fuzzy matching has a fixed conservative single-edit rule with a two-edit competitor margin; transpositions and short/multiword guesses are unsupported. Tests establish fixture behavior, not a measured production-language false-positive rate.
- Explicit executeProposal retains its supplied proposal. If a relevant change requires reinterpretation, the original input now passes through InputRouter before the mock, as required by deterministic-first routing.
- No Phase 5 context selection/budget algorithm was introduced; routing reads only the current canonical active field. Capability decisions and writes remain in the established runtime/bridge path.

## Phase 5 completed deliverables

- Internal ContextCompiler, not exported from the public barrel; the runtime uses it for compact SemanticContext compilation.
- Active field retention, explicit candidate hints, exact canonical ID/label/alias references, previous-answer history references, transitive canonical rule/dependency hints, newest changed fields and unanswered fields.
- Current canonical values for selected fields only. FormIR extensions and field/option extensions are excluded; no raw source schema/store object is accepted or forwarded.
- Public immutable ContextBudget configuration and ContextDiagnostics evaluation data; the selection algorithm stays internal. ContextCompiled reports reasons and sizes without answer values.
- Hard maximum field count, complete-context JSON character count and estimated token count, including escaped values, options, locale, identifiers and history. Required active/dependency context that cannot fit fails closed before intelligence or writes.
- Bounded recent changed-ID tracking from bridge events, bounded interaction history retention and immutable additive SemanticContext.history. History values remain current bridge values; no parallel runtime form state was introduced.
- Fixed compiled context during pending inference; relevant changes recompile on reinterpretation, unrelated changes revalidate the original selection.
- Fourteen context compiler/runtime tests, including direct and runtime 5,000-field fixtures, dependency cycles, previous references, oversized mandatory fields, escaped/large values, token/character caps, immutable diagnostics, stripping source extension metadata, history limits and dependency races.
- Earlier runtime tests now explicitly configure small context budgets where they exercise unrelated-field races. Compact default fixture expectations include the new unanswered-field selection; routing/concurrency assertions remain intact.
- Updated package API documentation with defaults, selection priorities, fail-closed behavior, context-only budget accounting and limitations.

## Phase 5 commands and results

Commands use `/tmp/form-assistant-sdk/dart-sdk/bin/dart`.

| Command | Working directory | Result |
| --- | --- | --- |
| `dart format packages examples` | Repository root | PASS — 36 Dart files formatted |
| `dart format --output=none --set-exit-if-changed packages examples` | Repository root | PASS — 0 changes, exit 0 |
| `dart analyze` | Repository root | PASS — no issues found, exit 0 |
| `dart test --reporter expanded` | `packages/form_assistant_core` | PASS — all 112 tests, exit 0 |
| `dart test --reporter expanded` | `examples/external_form_integration` | PASS — all 33 tests, exit 0 |
| `python3 tools/check_contract_schemas.py` | Repository root | PASS — four schemas and 42 fixture/malformed-input checks, exit 0 |
| `git diff --check` | Repository root | PASS |

**All repository Dart packages tested: 145 tests passed.** Previous phase
regressions and 6,000 randomized local/external operations remain green.

## Phase 5 gate results

| Requirement | Result |
| --- | --- |
| 5,000-field FormIR never passed whole by default | GREEN — direct compiler and runtime mock request contain only configured five/seven fields, with final active field retained |
| Context budget respected | GREEN — hard field/JSON char/estimated-token checks cover values, options, escaping and history; oversized mandatory context fails before mock invocation |
| Current field retained | GREEN — active first, never silently omitted/truncated; impossible budgets fail closed |
| Known dependency/reference fixtures retrieve required fields | GREEN — transitive/cyclic dependency hints, exact label references, previous accepted answer and pending dependency update |
| No source schema leaks | GREEN — canonical-only input; form/field/option extension metadata excluded and unselected values omitted |
| Deterministic selection diagnostics | GREEN — duplicate/permuted hints yield identical selection/reasons/sizes; immutable reason maps and counts |
| Bounded history and recency | GREEN — count/text/reference bounds, latest history preference, budget omission and disposal cleanup |
| Internal algorithm | GREEN — compiler not exported; public surface is budget/hints/semantic data/evaluation diagnostics |
| Architecture and phase scope | GREEN — bridge remains sole state boundary; no rule evaluator, model adapter/backend, STT, cloud or Flutter code |

## Phase 5 specification clarifications and deviations

No architecture redesign or changes to existing canonical action/value/bridge serialization.

- Concrete contract omissions: FormIR has no rule/dependency graph, and SemanticContext's sample lacks the bounded interaction history required by Phase 5. Added a runtime constructor hint map `dependenciesByField` with canonical IDs and an additive immutable history field with minimal text/interaction/accepted-field records. No source rules or general rule engine were added.
- Hard limits and diagnostics were specified without types/defaults. Added ContextBudget and ContextDiagnostics; the compiler itself is internal. Defaults: eight fields, 12,000 JSON characters, 3,000 estimated tokens, four history entries, 512 text characters per entry and sixteen recent changed IDs.
- Tokens use `ceil(JSON chars / 4)` as an explicit estimate, not a tokenizer-specific guarantee. Budgets cover compiled SemanticContext, not the current UserInput or complete IntelligenceRequest envelope. Phase 6 model formatting/tokenization remains unimplemented.
- Required active/dependency payloads may themselves exceed any finite budget. The runtime reports `runtime.context_budget_exceeded` and never invokes intelligence rather than dropping the active field, truncating canonical values/options or violating a hard cap. Other candidates/history may be omitted with diagnostics.
- Retrieval uses exact canonical name/alias phrases plus bounded accepted-answer history; it does not interpret arbitrary semantic references. Extension maps are stripped at the intelligence boundary even though canonical contracts continue to preserve them elsewhere.
- Runtime retains only bounded interaction text/IDs and changed field IDs, not authoritative values. History field references are capped/projected to selected context; oversized interaction IDs are skipped. This history is runtime-only and cleared at disposal; no persistence/model/privacy-policy implementation from later phases was introduced.

## Phase 6 implemented deliverables

- Completed IntelligenceOptions timeout/cancellation boundary, CancellationToken, cancellation exception and bounded execution helper. MockIntelligenceAdapter supports the same contract.
- Runtime submit/executeProposal options, cancellation of pending interpretation on runtime/bridge disposal, late-output suppression, distinct cancellation/timeout errors and queue release. Existing disposal behavior remains covered.
- Provider-neutral QualityGate validates allowed action families, selected canonical field identity, types/constraints and optional model confidence. Decisions preserve valid actions with invalid-value clarification when appropriate. No Phase 7 fallback/cloud implementation.
- Additive IntelligenceResult quality outcome/reason and IntelligenceQualityEvaluated runtime event; confidence/provenance remain outside canonical action/value data.
- New `form_assistant_function_gemma` package depending only on core, with public FunctionGemmaAdapter and local inference callback. InferenceBackend interface, native formatter and strict parser stay internal to this adapter package.
- Zero-shot FunctionGemma developer/tool/user/model prompt format, typed tool schemas, allowed tools, compact canonical context and control-token escaping of untrusted data. Extensions/raw schemas/unselected values are excluded.
- Native tool-call parser handles all seven canonical value types, clear, navigation and clarification, multiple calls, strict argument names/types, finite values, real dates and duplicate rejection. No JSON repair or accepting a valid prefix of malformed output.
- Cooperative backend abort signals on timeout/cancellation; late outputs/errors are observed but cannot produce runtime writes. Backend failures do not introduce a network fallback.
- Twelve-category hand-authored evaluation corpus checks final canonical state and clarification through the actual headless runtime; 21 adapter tests plus five additional core intelligence tests.
- Package documentation covers callback ownership, prompt/output boundaries, confidence limitations, cancellation and the distinction between scripted conformance and live model evaluation.

## Phase 6 commands and results

Commands use `/tmp/form-assistant-sdk/dart-sdk/bin/dart`.

| Command | Working directory | Result |
| --- | --- | --- |
| `dart pub get --offline` | `packages/form_assistant_function_gemma` | PASS — cached dependencies resolved; pub-cache metadata required approved SDK execution outside sandbox |
| `dart format packages examples` | Repository root | PASS — 42 Dart files formatted |
| `dart format --output=none --set-exit-if-changed packages examples` | Repository root | PASS — 0 changes, exit 0 |
| `dart analyze` | Repository root | PASS — no issues found, exit 0 |
| `dart test --reporter expanded` | `packages/form_assistant_core` | PASS — all 117 tests, exit 0 |
| `dart test --reporter expanded` | `packages/form_assistant_function_gemma` | PASS — all 21 tests, exit 0 |
| `dart test --reporter expanded` | `examples/external_form_integration` | PASS — all 33 tests, exit 0 |
| `python3 tools/check_contract_schemas.py` | Repository root | PASS — four schemas and 42 fixture/malformed-input checks, exit 0 |
| `git diff --check` | Repository root | PASS |

**All three repository Dart packages tested: 171 tests passed.** Scripted corpus:
12/12 final canonical state and clarification expectations pass. These are
hand-authored backend outputs, not observed FunctionGemma generations; this is
adapter conformance, not a model accuracy measurement.

## Phase 6 gate results

| Requirement | Result |
| --- | --- |
| Complete adapter boundary, mock, quality and cancellation/timeouts | GREEN — implementation and unit/runtime tests |
| Model-specific formatting/parsing isolated from core | GREEN — separate adapter package; no native model tokens in canonical values/actions |
| Compact canonical context, no raw source schema | GREEN — sanitized fields/options, selected values and escaped user/context data |
| Confidence/provenance outside canonical actions/values | GREEN — proposal metadata and quality result/event only |
| Scripted corpus covers all twelve required categories | GREEN — simple, multi-field, correction, negation, ambiguity, out-of-order, previous reference, invalid, unsupported, no answer, long, ASR noise |
| Final state evaluated rather than JSON validity alone | GREEN for fixtures — runtime snapshot and clarification assertions for every corpus case |
| Live zero-shot FunctionGemma state accuracy on corpus | FAILED — supplied GGUF scored 2/12 complete cases; 5/12 field-state matches |
| No fine-tuning or cloud | GREEN — no training/model download/network fallback introduced |
| Overall P6 | FAILED — live evaluation completed, but model correctness does not satisfy corpus expectations |

## Phase 6 specification clarifications and deviations

- Concrete omission: the specification requires an internal inference backend interface but chooses no local execution engine, model artifact, tokenizer or device target. Implemented the required internal interface with a host-supplied local generation callback; no inference framework dependency was invented. The user subsequently supplied a local Q8_0 GGUF; the CPU llama.cpp evaluation runner now connects this callback (details below).
- Native prompt/output syntax follows [Google's FunctionGemma formatting guide](https://ai.google.dev/gemma/docs/functiongemma/formatting-and-best-practices). Typed model tools translate into unchanged canonical actions; all model-specific syntax remains in the adapter package.
- Quality thresholds/outcomes were not fully defined for Phase 6. Added accept/clarify decisions, default 0.8 confidence threshold when a score exists, constraint checks and optional diagnostics. Missing confidence is never fabricated. Phase 7 fallback outcomes/policies remain unimplemented.
- Cancellation is cooperative and blocks interpretation/undispatched runtime writes; a host callback must honor the token to physically stop inference. Already-dispatched authoritative writes cannot be rolled back by cancelling interpretation.
- Portable intelligence codecs/schemas are not specified by the repository. New options/cancellation/backend/quality types remain runtime boundaries; canonical serialized value/action/state/event contracts are unchanged.
- Initial implementation used scripted fixtures only. Subsequent live evaluation is recorded below; scripted success is never treated as a green real-model P6 gate.

## Phase 6 live GGUF evaluation — 2026-10-05

- User-provided `functiongemma-270m-it-q8_0.gguf`, 279 MiB; SHA-256 `83940d4dd9676710856f43523bed096164a595a96f6b34771610a03937de5270`.
- Restored Dart 3.13.5 and downloaded the official CPU llama.cpp build b11429 (commit d81235049, version 0.6.0-dev) into `/tmp`; repository core/adapter production dependencies unchanged.
- Added reproducible `packages/form_assistant_function_gemma/bin/evaluate_gguf.dart`. Real generation callback invokes llama-completion with argument lists, unique temporary prompts, cancellation-driven process termination and separate stdout/stderr capture. No shell interpolation or network inference.
- Sampling: temperature 0, seed 42, one CPU thread, 8192-token context, 512-token output cap, two-minute per-case timeout. Every case uses the existing headless runtime and unchanged corpus expectations.
- Baseline [P6_GGUF_BASELINE.json](evaluation/P6_GGUF_BASELINE.json): **0/12 complete cases**. Refusals, extra arguments and generated function-response tails failed strict parsing.
- Fixed runner stop configuration at `<start_function_response>`; stripped only configured terminal stop and llama-completion's terminal UI marker. Did not weaken canonical/parser validation or accept malformed arguments.
- Improved zero-shot formatter: only value tools for selected field types, canonical ID enums, concrete operation/property descriptions and natural-language user turn with compact context in the developer turn. Untrusted declaration metadata is escaped. No corpus-specific answer injection or fine-tuning.
- Final [P6_GGUF_EVALUATION.json](evaluation/P6_GGUF_EVALUATION.json): **2/12 complete cases (16.7%)**, **5/12 field-state matches (41.7%)**. State-only matches include unchanged empty/initial values; they are not successful interpretation. Ambiguity and invalid-value cases passed the existing state/clarification expectations. Other cases over-clarified, refused or generated extra tool arguments.
- No case committed incorrect values; initial state remained unchanged in both runs. This safety result does not compensate for failing ordinary answers, corrections, multi-field requests and negation.
- Both reports preserve real prompts, raw transport output, normalized output, stderr, timings, model/runner identity, actual final state and per-case failure information. Data is synthetic corpus input, not real user form data.
- Two new formatter regression tests check context-specific tool declarations and injection-safe tool metadata.

### Live follow-up commands and results

| Command | Working directory | Result |
| --- | --- | --- |
| `dart run bin/evaluate_gguf.dart --binary /tmp/form-assistant-llama/llama-b11429/llama-completion --model ../../functiongemma-270m-it-q8_0.gguf` | `packages/form_assistant_function_gemma` | FAILED gate — exit 1, 2/12 complete cases; report saved |
| `dart format packages examples` | Repository root | PASS — 43 Dart files formatted |
| `dart format --output=none --set-exit-if-changed packages examples` | Repository root | PASS — 0 changes |
| `dart analyze` | Repository root | PASS — no issues |
| `dart test --reporter expanded` | `packages/form_assistant_core` | PASS — 117 tests |
| `dart test --reporter expanded` | `packages/form_assistant_function_gemma` | PASS — 23 tests |
| `dart test --reporter expanded` | `examples/external_form_integration` | PASS — 33 tests |
| `python3 tools/check_contract_schemas.py` | Repository root | PASS — four schemas, 42 checks |
| `git diff --check` | Repository root | PASS |

**173 automated tests pass. Live P6 gate fails.** These results are intentionally
reported separately; no gate was bypassed and no Phase 7 code was introduced.

## Remaining work / next phase

Phase 6 needs zero-shot model generations that satisfy the fixed corpus. The
provided GGUF and tested prompt/runner configuration do not achieve that. No
fine-tuning, deterministic NLP expansion, parser coercion, oracle injection or
architecture redesign was used to manufacture a passing result.

Phase 7 — Hybrid/cloud fallback. **Started 2026-10-22** under the 29/31
complete-case acceptance. The frozen category gate is still not green. See
[phase7/README.md](phase7/README.md).

## Phase 6 extraction persona comparison — 2026-10-06

- Added a developer-turn form extraction persona covering explicit multi-field
  slots, unnamed active-field answers, corrections, negation, numeric words,
  canonical choices and clarification only when needed.
- Added `FunctionGemmaAdapter.interpretJson` for a JSON-safe proposal envelope.
  Canonical actions/values and runtime state ownership are unchanged; native model
  tool syntax stays inside the adapter. No fine-tuning or Phase 7 work performed.
- Added regression coverage for persona placement and JSON multi-slot output,
  canonical codec round trips, metadata separation and recursive immutability.
- Live report: [P6_GGUF_PERSONA_EVALUATION.json](evaluation/P6_GGUF_PERSONA_EVALUATION.json).
  Same model SHA-256, corpus and generation settings as the prior 2/12 run.
  Result: **1/12 complete cases; 5/12 final-state matches** (including unchanged
  states). Refusals, malformed calls and unrelated navigation persist. Persona
  wording alone has not resolved model reliability; the cause is not isolated.
- Verification: Dart formatter (43 files), analyzer, core tests (117), adapter tests
  (25), external integration tests (33), schema checks (42) and diff whitespace
  check. All software checks passed; **live-model P6 gate FAILED**.
- Next: investigate checkpoint/template parity and task adaptation before claiming
  model correctness. Phase 7 remains unstarted.


## Phase 6R recovery — 2026-10-06

Original Phase 6 preserved at tag `phase-6-failed-baseline` (f1a32df); recovery branch
`phase-6r-functiongemma-recovery`. Implemented tasks 6R.0–6R.11 in order, with each
software gate checked before the next task. Canonical actions/values, FormIR,
bridges, authoritative state and phases 0–5 behavior are preserved.

Deliverables: SemanticContext v1.1 and compatibility projection, writable/candidate
metadata and budgets, frozen eight-tool protocol, dynamic field/option specialization,
strict parser/validator, canonical action mapping, compact native formatter, quality
policy, revision/fingerprint checks, bounded prepared-schema cache and frozen live
JSON/CSV evaluation. Legacy broad model path isolated rather than deleted.

Verification: formatter/analyzer, **233 tests** across three packages, 42 canonical
schema checks, 45 extraction schema checks, whitespace check all pass.

Live evidence: 31 frozen cases across 17 categories; two native-schema variants each
scored **7/31 complete cases**. Critical age+consent case failed **0/3 successes per
variant**. No expectations/thresholds weakened. Hard deterministic accepted-output
and concurrency checks pass; valid-but-wrong semantic values remain a model failure.
Simpler native enums reduced malformed output from 41.9% to 29.0%, still above 2%.

**Decision: NO-GO FunctionGemma for the supplied GGUF/current integration.**
[Full decision](phase6r/GO_NO_GO.md), [recovery task status](phase6r/PHASE_6R_STATUS.md),
[raw simpler-schema report](../benchmarks/function_gemma_phase6r/reports/simple_native.v1.json).
Phase 7 remains untouched and blocked. Next work requires a separate decision on
checkpoint parity/task adaptation or another IntelligenceAdapter, not a project restart.

## Additional model gate — Needle 3 (2026-10-06)

- FunctionGemma 270M recorded as **MODEL_NO_GO**, including 35 raw ablation runs proving clear-field competition and independent semantic/type failures. Its adapter and raw benchmark remain preserved.
- Added NeedleAdapter using the same SemanticContext, specialized eight-tool contract, strict validators and runtime; no Phase 6R architecture changes.
- Complete frozen 31-case benchmark: FunctionGemma 7/31; Needle 4/31; critical compound 0/3 each. **Needle MODEL_NO_GO**. Expected outputs and quality thresholds unchanged.
- [Side-by-side report](model_evaluation/FUNCTIONGEMMA_VS_NEEDLE3.md) includes native-engine limitations, pinned artifacts, all-call evidence and reproducible JSON/CSV comparison. Suppressed Needle candidates are diagnostic only; confidence gate remains 0.8.
- Formatter, fatal analyzer, all 273 software tests, canonical/extraction schema gates and whitespace check: PASS. Model quality: FAIL for both. No Phase 7 work.

## Additional model gate — Qwen3VL-2B (2026-10-06)

- Added `form_assistant_qwen3vl` (`Qwen3VlAdapter`) behind `IntelligenceAdapter`, reusing Phase 6R compact context, eight-tool specialization, strict validator/mapper and QualityGate. Host owns llama.cpp `llama-completion` (CPU build b11445 / commit 58cb913). Text-only Qwen chat prompts; no images; no repair.
- Pinned artifact: `Qwen3VL-2B-Instruct-Q4_K_M.gguf` SHA-256 `089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae`.
- Frozen 31-case host eval: **22/31** complete; critical age+consent **0/3**; boolean/numeric typed and hallucination caps PASS; simpleExact 92.9%, compoundExact 0%, malformed 19.4% FAIL. Primary compound failure: multiple consecutive JSON objects instead of one `function_calls` array.
- Decision: **MODEL_NO_GO**. Report: [qwen3vl.v1.json](../benchmarks/qwen3vl_phase6r/reports/qwen3vl.v1.json). Write-up: [QWEN3VL_2B.md](model_evaluation/QWEN3VL_2B.md). Comparison tool updated for three models. Phase 7 remains blocked.

## Additional model gate — Qwen3-4B-Instruct-2507 (2026-10-06)

- Same Qwen chat adapter / frozen corpus / eight-tool contract; pinned
  `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` SHA-256
  `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`.
- Host eval: **22/31** complete (same as 2B). Critical age+consent **3/3**;
  malformedCallRate **0%**; compoundExact 80%. Failures moved to field-selection /
  ambiguity / multi_add / noise value extraction.
- Decision: **MODEL_NO_GO**. Report:
  [qwen3_4b.v1.json](../benchmarks/qwen3_4b_phase6r/reports/qwen3_4b.v1.json).
  Write-up: [QWEN3_4B.md](model_evaluation/QWEN3_4B.md). Phase 7 remains blocked.

## Additional model gate — Qwen3VL-8B-Instruct (2026-10-06)

- Same adapter / frozen corpus; pinned `Qwen3VL-8B-Instruct-Q4_K_M.gguf`
  SHA-256 `67d1659bfe71b89d50b45a4ad1a9e5b997e5bb16ce5da66a6a6167abd569e9e2`.
- Host eval: **26/31** complete (best so far). Critical **3/3**; simpleExact
  **100%**; malformed **0%**. Remaining fails: negation_consent, reference_multi,
  ambiguous_number, noise_compound (age 30 vs 32), noise_choice.
- Decision: **MODEL_NO_GO**. Report:
  [qwen3vl_8b.v1.json](../benchmarks/qwen3vl_8b_phase6r/reports/qwen3vl_8b.v1.json).
  Write-up: [QWEN3VL_8B.md](model_evaluation/QWEN3VL_8B.md). Phase 7 remains blocked.

## Additional model gate — functiongemma270_trained (2026-10-09)

- Same FunctionGemma adapter and frozen corpus. Artifact
  `functiongemma270_trained.gguf` SHA-256
  `6452fdf7c89be44a861e3e3de1961d642db5b5acad12a9728ee4b5fe6bcf47bd`.
- Host eval: **3/31** complete (untuned baseline 7/31). Critical **0/3**.
  18/31 TOOL_FORMAT (model emits a user turn instead of a function call).
- Decision: **MODEL_NO_GO**. Report:
  [trained.v1.json](../benchmarks/function_gemma_phase6r/reports/trained.v1.json).
  Write-up: [FUNCTIONGEMMA_270M_TRAINED.md](model_evaluation/FUNCTIONGEMMA_270M_TRAINED.md).
  Phase 7 remains blocked.

## Additional model gate — Qwen3.8-27B (2026-10-22)

- Same Qwen chat adapter, frozen corpus, and eight-tool contract. Pinned
  `Qwen3.8-27B-UD-Q4_K_M.gguf` SHA-256
  `322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482`.
  Prompt uses the model's `enable_thinking=false` prefix so generation is the
  required JSON object.
- Host eval on Apple Silicon Metal (llama.cpp build 11515): **29/31** complete.
  Critical age+consent **3/3**. simpleExact, boolean, numeric, multi-choice,
  correction/reference, hallucination, and malformed gates PASS.
  choiceCanonical **75%** and compoundExact **80%** FAIL.
- Remaining fails: noise_compound wrote age 30 (expected 32); noise_choice
  emitted no calls (expected promotion=fall).
- Decision: **MODEL_NO_GO**. Report:
  [qwen3_8_27b.v1.json](../benchmarks/qwen3_8_27b_phase6r/reports/qwen3_8_27b.v1.json).
  Write-up: [QWEN3_8_27B.md](model_evaluation/QWEN3_8_27B.md). Accepted for
  Phase 7 at 29/31 complete cases. Frozen category gate remains failed.

## Phase 7 — Hybrid/cloud fallback (2026-10-22)

- Acceptance bar for leaving Phase 6R: **≥29/31** complete cases on the frozen
  corpus. Qwen3.8-27B is 29/31. `gate.v1.json` thresholds were not edited.
- Added `form_assistant_cloud`: `CloudLLMAdapter`, `HybridIntelligenceAdapter`,
  `IntelligenceCapabilities` (`networkAvailable`, `cloudAllowed`,
  `localModelAvailable`), and `SensitiveContextPolicy`.
- The host owns cloud transport. Offline, cloud-disabled, and sensitive
  contexts never invoke it. Ambiguous clarifications stay local. Fallback
  keeps the interaction trace and emits canonical `FormAction`s.
- Core `QualityOutcome.fallback` and `QualityGate.considerFallback` added.
  `QualityGate.evaluate` still returns only accept or clarify.
- Gate tests: `packages/form_assistant_cloud/test/phase7_gate_test.dart`,
  10 tests. Core suite 121 tests.

## Phase 8 — Streaming STT and voice orchestration (2026-10-22)

- Core contract: `AudioChunk` (PCM16), `STTAdapter` / `STTSession`, partial,
  final, error, and end events, plus `VoiceInput`.
- `VoiceOrchestrator` sends one final transcript through the existing runtime
  and `InputRouter`. Partials update voice state only. Transcript confidence
  stays off `ActionProposal.confidence`. `segmentId` is on the submit trace.
- Interrupt cancels the in-flight interpretation. A later final for that
  segment cannot commit. An STT error does not dispose the runtime, so a
  manual submit still commits.
- `HostSTTAdapter` drops audio bytes unless `retainAudio` is set. It does not
  open a microphone. Gate tests:
  `packages/form_assistant_stt/test/phase8_gate_test.dart`, 5 tests.

## Phase 9 — Thin Flutter integration (2026-10-22)

- `form_assistant_flutter` listens to runtime and voice events and builds
  listen/stop controls, a clarification banner, and highlight colors.
  `AssistantChrome` places that chrome around a form widget the host builds.
  The package builds no source fields and does not open a microphone.
- Provisional highlight follows a proposal. Accepted highlight follows
  `ActionApplied`. Dismissing a clarification does not write the store.
  A partial transcript is display text and is not submitted.
- `examples/flutter_existing_form` has no dependency on the assistant
  package. Its age field writes `ExistingFormStore` directly. Removing the
  assistant package leaves that form working.
- `examples/flutter_assistant_shell` is the optional composition: it passes
  `ExistingAgeForm` into `AssistantChrome.buildForm`. Core does not import
  Flutter.
- Gate tests: `packages/form_assistant_flutter/test/chrome_test.dart` (4),
  `examples/flutter_existing_form/test/existing_age_form_test.dart` (1),
  `examples/flutter_assistant_shell/test/assistant_shell_test.dart` (1).

## Phase 10 — Production hardening (2026-10-22)

- `TelemetryPolicy` defaults off. `RedactingTelemetrySink` removes utterances
  and field values unless a flag allows them, and always removes audio and
  raw bytes. `StageTimer` and nearest-rank `latencyPercentile` cover STT,
  context, model, validation, and commit.
- `observeInteraction` and `ProductionMetrics` report deterministic,
  local-model, fallback, clarification, and correction rates, state accuracy,
  and the share of failures from STT, context selection, model, adapter, and
  runtime. p50 and p95 are per stage.
- `EvalTraceStore` stores nothing unless `persistEvalTraces` is set. Raw
  utterance and values still require their own flags.
- `RecoveryCheckpoint` copies the committed bridge snapshot and abandons
  in-flight proposal ids. `CrashRecovery.resume` accepts only that snapshot.
  Proposals are not replayed.
- `ProtocolDocument` accepts spec version 1.0. Fixture:
  `packages/form_assistant_core/test/fixtures/protocol_1_0.json`.
- Gate tests: `packages/form_assistant_core/test/phase10_gate_test.dart`,
  9 tests, including a 250-step seeded soak. Core suite is 130 tests.
  Cookbook: [phase10/COOKBOOK.md](phase10/COOKBOOK.md).

## Phase 11 — Native form platform (2026-10-23)

- Not required for an existing-form integration. `LocalFormStateBridge`
  remains the state owner. No new canonical value types.
- `NativeForm` adds visibility rules and a workflow that covers every field
  in exactly one step. `NativeFormView` is the renderer contract: visibility,
  labels, canonical values, and the current step.
- A hidden field write or navigation fails in `ActionRuntime` with
  `rule.field_hidden` and does not change the revision.
- `commitNative` runs a manual edit through `executeProposal` and does not
  call the model. Deterministic speech uses the same action runtime. Only
  unresolved utterances call intelligence.
- `NativeFormRenderer` paints the current step and sends edits to the host
  callback. Phase 9 chrome still does not replace a source form.
- Gate tests: `packages/form_assistant_core/test/phase11_gate_test.dart` (3)
  and `packages/form_assistant_flutter/test/native_form_renderer_test.dart`.
  Core suite is 133 tests.

## Phase 12 — Multilingual semantics and React bindings (2026-10-23)

- Not a V1 blocker. Field ids and `FormAction` JSON are unchanged. Localized
  labels and aliases are optional and omitted when empty.
- `FormAssistantRuntime.locale` and an STT session locale reach
  `SemanticContext`. English routing is unchanged. Code-switch commits only
  when a non-English lexicon contributed, and the action still has no locale.
- `contracts/schemas/` stays the shared contract.
  `bindings/form_assistant_react` decodes protocol 1.0 and does not
  reimplement the runtime.
- Gate tests: `packages/form_assistant_core/test/phase12_gate_test.dart` (6).
  Core suite is 139 tests. Phase 12 completes the written plan.

# form_assistant_core

Canonical protocol 1.0 contracts, the local deterministic state engine, and
phase 6 intelligence options/quality gating, compact context and external state
integration support, with no production dependencies. Import
`package:form_assistant_core/form_assistant_core.dart` for the public API.

## Local state bridge

Create `LocalFormStateBridge(form: formIR)`, optionally supplying canonical
initial values, active field, lifecycle and capabilities. Read `snapshot` for
current authoritative state and listen to `events` for notifications. Existing
application stores use ExternalStateBridge; this local bridge owns its canonical
state.

```dart
final bridge = LocalFormStateBridge(form: formIR);
final result = await bridge.apply(
  const SetValueAction(fieldId: 'age', value: IntegerValue(30)),
  context: ApplyContext(
    expectedRevision: bridge.snapshot.revision,
    interactionId: 'interaction-1',
    operationId: 'operation-1',
    origin: ActionOrigin.user,
  ),
);
await bridge.dispose();
```

Operations are serialized, including revision checks, batches, history and
disposal. Stale starting revisions reject the operation before processing.
Semantic commits increment revision once; failures, unchanged values and focus
changes do not. Completion results reference the committed immutable snapshots.
StateChanged and ActiveFieldChanged publish synchronously after the snapshot is
visible, followed by ActionCompleted. BatchCompleted follows action completions.
The first subscription receives BridgeInitialized before any observed operation;
the broadcast event stream does not replay history for subsequent subscribers.
Dispose emits BridgeDisposed, closes the stream, clears history and rejects
subsequent operations.

`applyBatch` defaults to best effort and serializes the whole logical batch.
Successful semantic edits increment individually. Atomic mode evaluates actions
in order against private candidate state, validates all edits before committing,
and commits once or rolls back values and focus together. Unsupported atomic
mode is rejected without downgrading. Every atomic result references the final
snapshot; a sequence that returns values to their starting state is a semantic
no-op. Atomic focus changes also publish only the final active field.

Type, canonical option ID, required, numeric bound, Unicode character length and
pattern constraints come from FormIR. Initial state may omit unanswered fields;
provided initial answers must be valid. Clearing a required field, setting an
empty required string/multi-choice, and invalid values are rejected. String
patterns use Dart RegExp search semantics. Malformed schemas (duplicate field or
option IDs, invalid patterns or contradictory bounds) fail construction.
Assistant-control actions are unsupported at this state boundary.

Undo/redo restore values per semantic commit, preserving current focus and
incrementing the current revision rather than restoring an old revision. Atomic
batches are one history entry; best-effort commits are individual entries. A new
semantic edit clears redo; failures, no-ops and navigation preserve it. Restoring
history may restore an unanswered required field from a valid partial snapshot.
History origins are explicitly undo/redo. Empty or disabled history returns
capabilityUnavailable. The normative ActionResult requires one FormAction: a
multi-field restoration names the first changed field in canonical ID order,
while its snapshot and StateChanged contain the full restoration. Empty-history
rejections carry the current focus target, or next when no field is focused;
that action is diagnostic and is never executed.

## External state integration

`ExternalStateBridge<TState, TMutation>` implements the same FormStateBridge
contract while projecting an existing authoritative store. Supply an
integration-owned ExternalStateSource plus pure source-to-snapshot and
canonical-action-to-source-mutation callbacks. Source schema/store types stay in
the integration. The bridge never publishes planned values before the source
acknowledges its actual commit. See `examples/external_form_integration` for a
complete schema adapter, fake existing store and project-specific bridge.

The source port supplies immutable ordered snapshots with its own monotonically
increasing version. This concurrency token is independent of the bridge-lifecycle
semantic revision. All source writes, including manual edits, must share the
source's atomic compare-and-apply boundary. This is a consistency requirement,
not a dependency on any store framework. The bridge checks expectedRevision;
the source checks expectedSourceVersion atomically at authoritative commit.
Presentation/focus changes can advance source version without advancing semantic
revision, and still invalidate an already-dispatched write.

A pending operation is correlated by operationId and the acknowledged canonical
values/focus it requested. An authoritative notification or committed receipt can
acknowledge it. Echoed/older source versions are ignored, so each observed
semantic commit counts once. Uncorrelated changes become origin external.
Lifecycle changes are semantic; focus and source presentation changes are not.
Snapshots are published before ordered events, including reentrant source edits.

Acknowledgement timeout returns conflict with code
`bridge.acknowledgement_timeout`, emits an operationFailure error, and removes
pending correlation. A later observed commit is external and is never
force-written. Store failures and mapper failures emit diagnostic BridgeError
and return rejection. An unrepresentable source snapshot preserves the last
valid projection and blocks writes until a valid source snapshot arrives; valid
but constraint-invalid manual answers are still projected because the source is
authoritative. Subscription failure/closure blocks writes until the integration
recreates its bridge/subscription.

Best-effort batches serialize bridge-originated writes and stop remaining edits
if external semantic/focus changes invalidate the batch context. Atomic batches
require the source's actual transaction capability; unsupported atomic mode is
rejected without local emulation or downgrade. The phase 2 support does not
emulate external undo/redo: these capabilities are false and history methods
return capabilityUnavailable.

Dispose cancels the subscription, releases pending acknowledgement waits,
closes bridge events and rejects further calls. It does not dispose the source
store or undo a dispatched source request. The source's commit-time version
check still prevents delayed writes from overwriting newer state.

## Headless runtime

`FormAssistantRuntime(form: formIR, bridge: bridge, intelligence: mock)` uses
only the FormStateBridge interface. Core provides MockIntelligenceAdapter,
whose handler returns a scripted IntelligenceResult/ActionProposal. Proposals
carry baseRevision, unique action IDs and ActionProvenance with the request trace.

Call `submit(UserInput(text: text), trace: TraceContext(...))`. The runtime
captures the bridge snapshot, interprets, validates canonical constraints and
capabilities, and routes mutation/navigation to the bridge. Clarification stays
in runtime interaction state. `state` contains phase, trace and clarification,
while authoritative form values remain in `bridge.snapshot`. Listen to `events`
for interpretation, proposal disposition, validation, completion, clarification,
errors and RuntimeBridgeEvent wrappers preserving full request/segment/action
trace alongside unchanged canonical bridge events.

`contextFieldIds` supplies candidate hints; `dependencyFieldIds` supplies
required canonical dependency hints. The internal ContextCompiler retains the
active field and selects additional bounded semantic context. A
relevant touched/selected/dependency value, focus or lifecycle change discards
the proposal and reinterprets the original input. Unrelated revision changes
revalidate against the latest revision. Bridge commit-time concurrency checking
remains the final guard. Retries are bounded (default two) and preserve the
interaction/segment IDs with new request/operation IDs.

Best effort supports partial acceptance. A race after some actions completed
stops remaining edits and requests clarification without replaying committed
actions. Atomic execution requires bridge batch/atomic capabilities and never
downgrades. Proposal-provided validation metadata is diagnostic; runtime
validation is fresh. `executeProposal` requires the original `basedOn` snapshot
from the same bridge lifecycle, input and trace. Its provenance origin is passed
to the bridge unchanged.

Submissions are serialized. Dispose releases pending mock interpretation and
closes runtime events; the caller retains ownership of the bridge and source.
The event map and intelligence helper objects are runtime-only boundaries; no
model implementation or new canonical bridge JSON fields are introduced.

## Deterministic input routing

`submit` runs InputRouter before intelligence. `InputRouted` explains the route:
`deterministic`, `needsIntelligence` or `needsClarification`, with a reason code.
The pure `InputRouter.route(input, activeField: field)` API returns immutable
canonical action proposals and never reads or writes a store.

Supported whole answers for the active field include yes/no variants, signed
digits/decimals, English numbers zero through ninety-nine, signed word numbers,
and decimal words such as "one point two five". Integer answers must be integral
and within the portable exact-integer range. Exact choice IDs, labels and aliases
produce canonical option IDs. Multi-choice supports one explicit choice; combined
answers fall through. Strings and dates are left to intelligence.

Fuzzy choice matching permits one edit on ASCII words at least five letters
long, only when no other option is within two edits. Short words, prefixes,
transpositions, multiple matches and compound utterances are not guessed.
Alias collisions and command/choice collisions request clarification.

Narrow clear phrases target the active field. "actually", "correction" and
"change my answer to" prefixes accept a single supported replacement answer.
"next", "next field", "previous", "previous field" and "go back" propose
navigation. No field-name/reference resolution or general NLP is attempted.
Recognized constraint-invalid answers request clarification; unsupported and
compound/negated language goes to intelligence without a router mutation.

Deterministic proposals carry origin deterministic, the captured revision and
full trace, and use the same ActionRuntime validation, capability checks and
bridge concurrency guard. Relevant races reroute the original input against the
latest active field. Explicit `executeProposal` still executes the supplied
proposal; routing runs when reinterpretation becomes necessary.

## Bounded semantic context

The runtime owns an internal ContextCompiler; its retrieval algorithm is not
exported. Configure `contextBudget: ContextBudget(...)` on the runtime. Defaults
are eight fields, 12,000 JSON characters, 3,000 estimated tokens, four history
entries, 512 characters per history text and sixteen recent changed field IDs.
`dependenciesByField` supplies integration-known rule/dependency relationships
using canonical field IDs only; transitive dependencies are included and cycles
terminate. No rule evaluator or source schema enters the compiler.

The compiler prioritizes the active field and required dependencies, then explicit
candidates, exact canonical label/alias/ID references, previous-answer references,
recent changed fields and unanswered fields in stable form order. Recent IDs come
from bridge StateChanged events, including external edits. Reference retrieval
selects context only; it never generates an action. Optional fields may be omitted
under a budget. If the active field or required dependencies cannot fit, the
runtime returns `runtime.context_budget_exceeded` without calling intelligence
or mutating the form. Canonical values/options are never silently truncated.

Budget cost covers the complete compiled semantic context JSON: selected fields,
current canonical values, options, locale, identifiers, revision and history,
including JSON escaping. Token cost is `ceil(chars / 4)`, an estimate rather than
a model tokenizer measurement. The current UserInput/request envelope is outside
this semantic-context budget. The stricter character/token limit wins.

Compiled fields/options strip all extension maps. FormIR extensions, raw source
schemas and nonselected values are excluded. SemanticContext has an additive
immutable `history` list: bounded recent interaction text, interaction ID and
accepted mutation field IDs. History field IDs are projected to selected fields;
newest entries are preferred, and history is omitted if the remaining size budget
cannot fit it. Runtime history retention bounds entry count, text length and field
ID count, skips oversized interaction IDs, and clears on disposal.

`ContextCompiled` reports immutable selected/omitted canonical IDs with reason
codes, JSON character count, estimated tokens and history count. These evaluation
diagnostics contain no answer values and are separate from the adapter context.
The original compilation remains fixed while inference is pending. Relevant
selected/dependency changes cause a fresh compilation on reinterpretation;
unrelated changes retain the original selection for revalidation.

## Canonical serialization

Value/action and FormIR codecs reject malformed known properties with
FormatException and ignore unknown optional fields. FormIR requires explicit
specVersion and preserves compatible 1.x versions. Value/action fragments retain
the normative discriminator format without adding a version property.

FormStateSnapshotCodec and BridgeEventCodec encode versioned root documents;
result, batch, capability and ApplyContext codecs serialize nested contracts.
Snapshot/event decoding accepts compatible 1.x versions; current writers emit
1.0. Timestamps encode as canonical UTC ISO strings. BridgeError.cause remains
runtime-only. Immutable contracts have structural equality/hashCode; event
comparison covers serialized fields and excludes runtime-only cause.

Collection inputs are defensively copied; metadata and extensions are recursively
validated and frozen. Constructors reject invalid calendar dates, non-finite
numbers and empty choice IDs.

## Verification

From this directory: `dart pub get`, `dart analyze`, and `dart test`.
From the repository root: `dart format packages examples`, `dart analyze`, and
`python3 tools/check_contract_schemas.py` (development dependency: jsonschema 4.x).
Tests include canonical goldens and five independent seeded model checks totaling
5,000 operations through revisions, batches, rollback, undo/redo and event replay.
Also run `dart test` in `examples/external_form_integration`; its integration
suite includes 1,000 mixed assistant/external operations. Both packages keep their
own dependency lockfiles.

The FunctionGemma adapter lives in `packages/form_assistant_function_gemma` and
accepts an injected local generation callback. Live model evaluation is pending;
voice, cloud and Flutter bindings remain later phases.

## Intelligence options and quality

`submit` and `executeProposal` accept `options: IntelligenceOptions(...)` with a
per-interpretation timeout (default 30 seconds) and optional CancellationToken.
Cancellation before execution prevents dispatch; pending interpretation is
released and late output is ignored. Disposing runtime/bridge signals adapter
cancellation. Cancellation does not roll back writes already dispatched to an
authoritative bridge/store. A timeout releases the submission queue, preserves
form values and reports `runtime.intelligence_timeout`; cancellation reports
`runtime.cancelled`. Interpreter disposal retains `runtime.disposed`.

The provider-neutral QualityGate produces accept/clarify decisions from allowed
actions, selected canonical context, constraints and optional model confidence.
IntelligenceResult carries optional quality diagnostics, and the runtime emits
IntelligenceQualityEvaluated. No cloud fallback outcome or provider dependency
has been introduced into core. The mock supports the same timeout/cancellation
contract, and runtime enforces options for arbitrary injected adapters too.

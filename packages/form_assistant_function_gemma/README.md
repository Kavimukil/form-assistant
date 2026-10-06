# form_assistant_function_gemma

Phase 6R constrained local typed slot extractor, isolated behind IntelligenceAdapter.
Phases 0–5 remain the deterministic foundation. Supply
`FunctionGemmaAdapter(inference: localGenerate)` with
`Future<FunctionGemmaOutput> Function(String prompt, CancellationToken token)`.
The host owns model loading, tokenizer, local runtime and physical abort.
No network inference, fine-tuning, workflow tools or cloud fallback is included.

The model sees compact canonical SemanticContext v1.1: selected field IDs/types,
labels/aliases/concepts, current values, active/recent references, constraints and
candidate option IDs/labels/aliases. Source extensions, full forms, selection
reasons, tracing and fingerprints are excluded from its prompt. Oversized context
fails closed. Context budgets are estimates; actual llama.cpp counts are reported
in live evaluation.

Exactly eight extraction tools are available: set_string, set_integer, set_number,
set_boolean, set_date, set_choice, set_multi_choice, clear_field. Only compatible
writable selected fields appear in declarations; empty setter groups are omitted.
clear_field maps to canonical ClearValueAction. No navigation, submit, undo/redo or
request_clarification model tool exists. Canonical runtime workflow stays available
outside this extraction surface.

FunctionGemma uses native developer/user/model turns, tool declarations/calls and
`<escape>` string delimiters. Return only the newly generated continuation without
an echoed prompt. Stop at turn/eos/function-response boundaries after all calls for
one proposal. Control-looking untrusted text is escaped. Syntax, argument names,
exact types, finite numbers, real ISO dates, field writability/type and candidate
option membership are validated strictly. No repair or valid-prefix acceptance.
Duplicates are diagnosed/deduplicated; conflicting same-field calls are rejected.
Multi-choice output replaces the complete selection, never appends implicitly.

Canonical schema correlates choice fields/options. Native v0.2.1 declarations use
flat candidate enums after the first real benchmark exposed spurious `oneOf`
arguments; strict validation still enforces per-field correlation. This experiment
is explicitly permitted by the recovery plan and changes no expected answers.

QualityGate handles constraints, empty extraction and optional confidence, producing
canonical clarification when needed. Model confidence is never invented. Malformed
outputs are explicit failures. Runtime and bridge own fresh validation, authoritative
revision checks and commits. Schema LRU caches prepared declarations only, never
requests, current values, model results or proposals.

Use `await adapter.interpretJson(request)` for a JSON-safe proposal envelope and
`jsonEncode` to serialize. `proposal.actions[].action` contains unchanged canonical
action/value JSON; provenance/confidence/quality stay outside actions. This returns
a proposal, not a form commit. `interpret` remains the standard adapter interface.
Timeout/cancellation signal the backend; the host must observe the token to abort.

## Verification and live evaluation

Run formatter/analyzer from the repository root, `dart test` in both packages and
the external integration example, and both Python schema checkers. Scripted tests
prove software behavior, not model quality.

Run from this package directory:

```
dart run bin/evaluate_phase6r.dart \
  --binary /tmp/form-assistant-llama/llama-b11429/llama-completion \
  --model ../../functiongemma-270m-it-q8_0.gguf
```

See [recovery documentation](../../docs/phase6r/README.md) and the
[frozen benchmark](../../benchmarks/function_gemma_phase6r/README.md). JSON/CSV reports
record model/corpus hashes, full prompts/outputs, strict validation, exact extraction,
commit behavior, failure categories, host latency/token counts and peak RSS. The
threshold config is frozen before real generation. No target Zebra claim is made.

## Superseded Phase 6

Internal legacy_adapter.dart / legacy_format.dart preserve the old broad model
surface. The historical `bin/evaluate_gguf.dart` explicitly uses that legacy adapter;
its original corpus and regression expectations remain unchanged. Reports in
`docs/evaluation` show 0/12, 2/12 and persona-only 1/12 complete cases. The failed
baseline is reproducible at tag `phase-6-failed-baseline`. These are different
corpora/scoring from 6R and must not be compared as equivalent accuracy estimates.

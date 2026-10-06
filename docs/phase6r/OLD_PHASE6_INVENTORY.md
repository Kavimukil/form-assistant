# Failed Phase 6 inventory

Baseline: `phase-6-failed-baseline` (f1a32df). Reproduce software checks with
`dart test` in both packages and the external integration example. Reproduce live
results with adapter `bin/evaluate_gguf.dart` and the checked-in GGUF, using
llama.cpp b11429. Reports in `docs/evaluation` preserve prompts, raw continuations,
settings and artifact SHA-256 (0/12 baseline, 2/12 revised, 1/12 persona).

| File / responsibility | Migration | Dependency / affected tests |
| --- | --- | --- |
| core contracts/form_value, form_action, form_ir, form_state, form_state_bridge | KEEP | All canonical goldens and bridge tests remain |
| core state/* and examples/external_form_integration | KEEP | Authoritative state, CAS, external mapping |
| core runtime/action_runtime, input_router, tracing/events | KEEP | Deterministic actions, validation, workflow and concurrency |
| core contracts/intelligence: SemanticContext / FormFieldContext | EVOLVE compatibly | Add explicit v1.1 projection/codec while retaining old constructor/accessors |
| core runtime/context_compiler + context_configuration | EVOLVE | Budgets, current values, writable/truncation, semantic identity |
| core runtime/quality_gate | EVOLVE | Writable and conflicting-write safety; retain canonical clarification |
| core runtime/form_assistant_runtime | KEEP stale re-evaluation; verify | No model cache may bypass authoritative revision |
| adapter src/format.dart | ISOLATE legacy | Broad workflow/clarification tools and verbose full canonical field formatting |
| adapter src/backend.dart | KEEP | Local callback, cancellation; no state ownership |
| adapter FunctionGemmaAdapter | REBUILD intelligence path | Specialized eight-tool extraction only |
| adapter bin/evaluate_gguf.dart + test/fixtures/evaluation.json | PRESERVE historical | Legacy broad-surface corpus; new frozen 6R corpus/report separate |
| adapter test/adapter_test.dart | KEEP legacy fixtures isolated; migrate public adapter coverage | Preserve old expectations; add strict extraction-specific tests |

No generic set_form_field or submit model tool exists. Navigation and
request_clarification DO exist in the old formatter; remove from the new model
surface, not from canonical runtime actions. clear_value becomes model-only
clear_field and still maps to canonical ClearValueAction. No source-schema
interpretation moves into core. No Phase 7 or fine-tuning in this migration.

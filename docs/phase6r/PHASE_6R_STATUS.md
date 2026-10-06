# Phase 6R status

Original Phase 6 superseded. Phases 0–5 preserved. Recovery implementation and review complete: **NO-GO FunctionGemma**. Phase 7 blocked.

| Task | Status | Evidence |
| --- | --- | --- |
| 6R.0 | GREEN | Baseline tag f1a32df; branch; inventory/ADR; analyzer, 175 tests and 42 schema checks pass |
| 6R.1 | GREEN | v1.1 codec, compatible accessors, writable lifecycle, caps and identity; 178 tests/analyzer/schema checks pass |
| 6R.2 | GREEN | Eight-tool DTO/schema golden; analyzer, 180 tests and schema checks pass |
| 6R.3 | GREEN | Specialized/correlated option schema golden, writable filtering; 183 tests and checks pass |
| 6R.4 | GREEN | Strict native parser/DTO/context validator; negative matrix and conflict policy; 185 tests/checks pass |
| 6R.5 | GREEN | All eight canonical mappings, order/revision/provenance; 187 tests/checks pass |
| 6R.6 | GREEN | Public adapter now compact extraction only; legacy path isolated, no old expectations changed; 191 tests/checks pass |
| 6R.7 | GREEN | Deterministic constraint/empty/readonly policy, internal outcomes, trace/bridge coverage; 194 tests/checks pass |
| 6R.8 | GREEN | Exact selected-context identity path, rev17→18 relevant/unrelated races; 196 tests/checks pass |
| 6R.9 | GREEN | Bounded prepared-declaration LRU, exact cache/uncached prompts, invalidation and concurrency; 198 tests/checks pass |
| 6R.10 | GREEN | Frozen 31-case/17-category corpus, strict JSON/CSV harness and adversarial scoring; 231 tests/checks pass |
| 6R.11 | COMPLETE — NO-GO | Two unchanged-corpus real runs: 7/31 each; critical 0/3 each; hard checks pass, model thresholds fail |

Migration: historical adapter/formatter and corpus remain internal legacy files and tests, and the old runner explicitly uses the legacy adapter. Public adapter v0.2.0 uses only extraction tools. This preserves baseline reproducibility without broadening the new path.


## Final gates and commands

Run from repository root with Dart SDK 3.13.5:

| Check | Result |
| --- | --- |
| `dart format packages examples` and no-change check | PASS — 68 Dart files |
| `dart analyze --fatal-infos` | PASS — no issues |
| `dart test --reporter expanded` in core | PASS — 120 tests |
| Same command in adapter | PASS — 80 tests (including preserved legacy tests) |
| Same command in external integration example | PASS — 33 tests |
| `python3 tools/check_contract_schemas.py` | PASS — 4 schemas / 42 checks |
| `python3 tools/check_phase6r_schemas.py` | PASS — extraction protocol/specialization / 45 checks |
| `git diff --check` | PASS |
| Real `bin/evaluate_phase6r.dart` correlated native schema | FAIL quality — 7/31; raw JSON/CSV preserved |
| Same frozen corpus with simple native enums | FAIL quality — 7/31; raw JSON/CSV preserved |
| Decision | NO-GO; see GO_NO_GO.md and reports/review.v1.json |

Software gates 6R.0–6R.10 are green. The final model-quality gate is intentionally
reported failed rather than weakening requirements. Model alias/choice/multi-choice
and compound reliability remains unfulfilled; it is not represented as a completed
model capability merely because scripted mapping tests pass.

All task boundaries committed in order. Small compatible core edits were limited
to SemanticContext/ContextCompiler/budgets/QualityGate and selected-context freshness;
FormValue/FormAction/FormIR, both state bridges and authoritative commits retained.
Exact canonical JSON identity avoids dependencies/hash collisions; it is not sent
to the model. The explicit flat-native-schema comparison follows plan §7.10. Legacy
benchmark reports and expected outputs are retained. No Phase 7, STT or fine-tuning.

Final review correction: ContextCompiler now receives bridge.capabilities.writable in addition to lifecycle. An active but read-only bridge exposes no model mutation target; a native adapter integration regression verifies this. All frozen live fixtures use writable bridges, so benchmark prompts and results are unaffected.

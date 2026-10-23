# Phase 6R model decision: MODEL_NO_GO — Qwen3VL-8B-Instruct

Host-eval candidate `Qwen3VL-8B-Instruct-Q4_K_M.gguf` fails the unchanged
Phase 6R model gate. Phases 0–5 and the Phase 6R architecture remain intact.
Phase 7 remains blocked. Same extraction contract and Qwen chat adapter path
(text-only; no images).

| Measure | Qwen3VL-2B | Qwen3-4B | Qwen3VL-8B |
| --- | ---: | ---: | ---: |
| Complete cases passed | 22/31 | 22/31 | **26/31 (83.9%)** |
| Critical age + consent | 0/3 | 3/3 | **3/3** |
| Simple extraction | 92.9% | 92.9% | **100%** |
| Boolean extraction | 100% | 100% | 66.7% (need ≥98%) |
| Numeric typed | 100% | 100% | **100%** |
| Choice / multi / compound | 75/33/0% | 50/33/80% | 75/67/**80%** |
| Correction / reference | 66.7% | 66.7% | 66.7% (need ≥90%) |
| Hallucinated field / option | 0/0% | 0/0% | **0/0%** |
| Malformed call rate | 19.4% | 0% | **0%** |
| Cold host latency p50 / p95 | 4.8 / 6.5 s | 11.2 / 13.9 s | 19.5 / 25.1 s |
| Model decision | MODEL_NO_GO | MODEL_NO_GO | **MODEL_NO_GO** |

## What improved vs 4B

- Complete cases **26/31** (best so far).
- `simpleExact` **100%**; `multi_add` and several ambiguity/noise cases now pass.
- Critical compound still **3/3**; malformed still **0%**.

## Remaining failures (5)

| Category | Case | Behavior |
| --- | --- | --- |
| NEGATION | negation_consent | cleared consent instead of `set_boolean false` |
| FIELD_SELECTION | reference_multi | extra `clear_field` before set |
| FIELD_SELECTION | ambiguous_number | wrote register_count when expected no mutation |
| VALUE_EXTRACTION | noise_compound | age **30** instead of **32** |
| FIELD_SELECTION | noise_choice | empty `function_calls` instead of promotion=fall |

Gate still fails booleanExact (from the negation miss), choiceCanonical,
multiChoiceExact, compoundExact, and correctionReferenceExact.

## Artifacts

- Model SHA-256: `67d1659bfe71b89d50b45a4ad1a9e5b997e5bb16ce5da66a6a6167abd569e9e2`
- Report: [qwen3vl_8b.v1.json](../../benchmarks/qwen3vl_8b_phase6r/reports/qwen3vl_8b.v1.json)
- Runtime: CPU llama.cpp b11445 / commit `58cb913`, cold process per case

Stop here: Phase 7 has not been started.

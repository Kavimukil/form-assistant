# Phase 6R model decision: MODEL_NO_GO — Qwen3-4B-Instruct-2507

Host-eval candidate `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` fails the unchanged
Phase 6R model gate. Phases 0–5 and the Phase 6R architecture remain intact.
Phase 7 remains blocked. Same extraction contract and Qwen chat adapter path as
the Qwen3VL-2B eval (text-only).

| Measure | Qwen3VL-2B Q4_K_M | Qwen3-4B-Instruct-2507 Q4_K_M |
| --- | ---: | ---: |
| Complete cases passed | 22/31 (71.0%) | **22/31 (71.0%)** |
| Critical age + consent | 0/3 | **3/3** |
| Simple extraction | 92.9% | 92.9% (need ≥97%) |
| Boolean / numeric typed | 100% / 100% | **100% / 100%** |
| Choice / multi-choice / compound | 75% / 33% / 0% | 50% / 33% / **80%** |
| Correction / reference | 66.7% | 66.7% (need ≥90%) |
| Hallucinated field / option | 0% / 0% | **0% / 0%** |
| Malformed call rate | 19.4% | **0%** (need ≤2%) |
| Cold host latency p50 / p95 | 4841 / 6521 ms | 11219 / 13912 ms |
| Model decision | MODEL_NO_GO | **MODEL_NO_GO** |

## What improved vs 2B

- Critical compound (`Age thirty two, consent yes`) now **3/3**.
- Malformed / multi-object JSON failures dropped to **0%**.
- `compoundExact` rose from 0% to 80% (still below ≥92%).
- `criticalRegression` and `malformedCallRate` gate checks **PASS**.

## What still fails (9)

| Category | Cases |
| --- | --- |
| FIELD_SELECTION | negation_choice, reference_multi (extra clear before set); ambiguous_number, ambiguous_option, option_truncated (answered when expected no mutation) |
| VALUE_EXTRACTION | constraint_age (cleared instead of writing 150); noise_compound (age 30 vs 32); noise_choice (clear instead of fall) |
| MULTI_CHOICE_STATE | multi_add — replaced set instead of additive union |

Same pass count as 2B, but failures shifted from TOOL_FORMAT to semantic /
ambiguity policy. Gate still fails on simpleExact, choiceCanonical,
multiChoiceExact, compoundExact, and correctionReferenceExact.

## Artifacts

- Model SHA-256: `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`
- Report: [qwen3_4b.v1.json](../../benchmarks/qwen3_4b_phase6r/reports/qwen3_4b.v1.json)
- Runtime: CPU llama.cpp b11445 / commit `58cb913`, cold process per case

Stop here: Phase 7 has not been started.

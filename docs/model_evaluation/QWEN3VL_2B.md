# Phase 6R model decision: MODEL_NO_GO — Qwen3VL-2B

Host-eval candidate `Qwen3VL-2B-Instruct-Q4_K_M.gguf` fails the unchanged
Phase 6R model gate. Phases 0–5 and the Phase 6R architecture remain intact.
Phase 7 remains blocked. This decision applies to the pinned artifact and the
current extraction contract (text-only prompts; no images).

| Measure | FunctionGemma 270M Q8_0 | Needle 3 | Qwen3VL-2B Q4_K_M |
| --- | ---: | ---: | ---: |
| Complete cases passed | 7/31 (22.6%) | 4/31 (12.9%) | **22/31 (71.0%)** |
| Critical age + consent | 0/3 | 0/3 | **0/3** |
| Simple extraction | 35.7% | 14.3% | 92.9% (need ≥97%) |
| Boolean extraction | 0% | 0% | **100%** |
| Numeric typed extraction | 50% | 0% | **100%** |
| Canonical choice / multi-choice / compound | 0% / 0% / 0% | 0% / 0% / 0% | 75% / 33% / **0%** |
| Correction / reference | 66.7% | 0% | 66.7% (need ≥90%) |
| Hallucinated field / option rate | 0% / 6.5% | 0% / 0% | **0% / 0%** |
| Malformed call rate | 29.0% | 6.5% | 19.4% (need ≤2%) |
| Cold host latency p50 / p95 | 2046 / 2941 ms | 1047 / 2590 ms | 4841 / 6521 ms |
| Model decision | MODEL_NO_GO | MODEL_NO_GO | **MODEL_NO_GO** |

## Implementation

[Qwen3VlAdapter](../../packages/form_assistant_qwen3vl/lib/form_assistant_qwen3vl.dart)
implements `IntelligenceAdapter`. It reuses compact SemanticContext formatting,
dynamic specialization of the eight extraction tools, strict DTO/context
validation and canonical mapping. No core architecture, production FunctionGemma
or Needle behavior, runtime bridge or frozen fixture was changed.

Host inference uses llama.cpp `llama-completion` (CPU build, tag b11445 /
commit `58cb9138e46180d45854cf45d4c1e25ad5f7e1c4`) with a manually formatted
Qwen chat template. Temperature 0, seed 42, one thread, ctx 8192, n-predict 512,
cold process per case. The model must emit a single JSON object:

```json
{"function_calls":[{"name":"...","arguments":{...}}]}
```

No adapter repair. Multi-object concatenations (common on compound utterances)
are rejected as TOOL_FORMAT failures even when individual calls look correct.

Pinned model SHA-256:
`089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae`.

Complete report:
[qwen3vl.v1.json](../../benchmarks/qwen3vl_phase6r/reports/qwen3vl.v1.json).

## Primary failures (9)

| Category | Cases |
| --- | --- |
| TOOL_FORMAT | compound_age_consent_001/002/003, compound_store, reference_multi, noise_compound — multiple consecutive JSON objects instead of one `function_calls` array |
| MULTI_CHOICE_STATE | multi_add — replaced set instead of additive update |
| FIELD_SELECTION | ambiguous_number, ambiguous_option — answered when expected no mutation |

Boolean, numeric typed, hallucinated field/option and hard correctness checks pass.
Critical compound and compoundExact remain 0. Simple extraction (92.9%) misses
the ≥97% threshold by one case.

## Reproducible comparison

```
python3 tools/compare_extraction_models.py
```

Checks corpus/config/context hashes and identical case IDs/inputs/expected
calls/state before writing
[comparison.v1.json](../../benchmarks/model_comparison/comparison.v1.json).

Stop here: Phase 7 has not been started.

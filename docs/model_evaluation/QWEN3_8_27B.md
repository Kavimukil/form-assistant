# Phase 6R model decision: MODEL_NO_GO — Qwen3.8-27B

Host-eval candidate `Qwen3.8-27B-UD-Q4_K_M.gguf` fails the unchanged Phase 6R
model gate. Phases 0–5 and the Phase 6R architecture remain intact. Phase 7
remains blocked. Same frozen corpus, eight-tool contract, strict JSON parser,
and Qwen chat adapter. Qwen3.8's chat template opens a `<think>` block unless
thinking is disabled; this run prepends the template's `enable_thinking=false`
prefix (`<think>\n\n</think>\n\n`) so the model can emit the required JSON
object. A smoke prompt without that prefix produced a think trace before the
JSON, which the strict parser rejects.

| Measure | Qwen3VL-8B | Qwen3.8-27B UD-Q4_K_M |
| --- | ---: | ---: |
| Complete cases passed | 26/31 (83.9%) | **29/31 (93.5%)** |
| Critical age + consent | 3/3 | **3/3** |
| Simple extraction | 100% | **100%** |
| Boolean / numeric typed | 66.7% / 100% | **100% / 100%** |
| Choice / multi-choice / compound | 75% / 67% / 80% | 75% / **100%** / 80% |
| Correction / reference | 66.7% | **100%** |
| Hallucinated field / option | 0% / 0% | **0% / 0%** |
| Malformed call rate | 0% | **0%** |
| Cold host latency p50 / p95 | 19.5 / 25.1 s (CPU) | 5.6 / 8.6 s (Apple GPU) |
| Model decision | MODEL_NO_GO | **MODEL_NO_GO** |

## Gate

| Metric | Actual | Required | Gate |
| --- | ---: | ---: | --- |
| Simple single-field exact | 100% | ≥97% | PASS |
| Boolean exact | 100% | ≥98% | PASS |
| Integer/number typed exact | 100% | ≥97% | PASS |
| Choice canonical ID | 75% | ≥97% | FAIL |
| Multi-choice exact set | 100% | ≥93% | PASS |
| Compound exact action set | 80% | ≥92% | FAIL |
| Correction/reference exact | 100% | ≥90% | PASS |
| Hallucinated field rate | 0% | ≤1% | PASS |
| Hallucinated option rate | 0% | ≤1% | PASS |
| Malformed output rate | 0% | ≤2% | PASS |
| Critical age+consent | 3/3 | reliably succeed | PASS |

`choiceCanonical` is 3/4 set-choice cases. `compoundExact` is 4/5 multi-call
cases. One miss on each small slice fails the gate. Hard correctness passed:
zero safety violations, zero hallucinated fields or options.

## Remaining failures (2)

| Category | Case | Behavior |
| --- | --- | --- |
| VALUE_EXTRACTION | noise_compound | utterance `age thirty to consent yes`; wrote age **30** and consent true (expected age **32**) |
| FIELD_SELECTION | noise_choice | utterance `promotion was auto man`; emitted `{"function_calls":[]}` (expected promotion=`fall`) |

## Artifacts

- Model SHA-256: `322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482`
- Architecture in GGUF: `qwen35` (`general.name` Qwen3.8-27B, Unsloth UD-Q4_K_M)
- Report: [qwen3_8_27b.v1.json](../../benchmarks/qwen3_8_27b_phase6r/reports/qwen3_8_27b.v1.json)
- Runtime: llama.cpp 0.6.0-dev build 11515 / commit `3d65c90d0`, Apple Silicon Metal, one thread, temperature 0, cold process per case. Host p50/p95 latency 5604/8624 ms; TTFT p50/p95 4075/5173 ms including process and model load. Peak RSS was not captured (macOS has no GNU `time -v`). Block 64 next-token tensors were unused by this llama.cpp build. These are host measurements; no Zebra latency claim.

Phase 7 started under a separate acceptance bar of at least 29/31 complete
cases. The frozen category gate above remains failed. Known residuals are
unchanged. This artifact is the host local candidate, not a measured Zebra
runtime. See [Phase 7](../phase7/README.md).

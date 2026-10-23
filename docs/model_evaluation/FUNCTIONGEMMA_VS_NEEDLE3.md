# Phase 6R model decision: MODEL_NO_GO

Both FunctionGemma 270M and Needle 3 fail the unchanged Phase 6R model gate.
Phases 0–5 and the Phase 6R architecture remain intact. Phase 7 remains blocked.
This decision applies to these pinned artifacts and the current extraction contract.

| Measure | FunctionGemma 270M Q8_0 | Needle 3 full-depth base |
| --- | ---: | ---: |
| Complete cases passed | 7/31 (22.6%) | 4/31 (12.9%) |
| Exact returned action sets | 7/31 (22.6%) | 6/31 (19.4%) |
| Critical age + consent | 0/3 | 0/3 |
| Simple extraction | 35.7% | 14.3% |
| Boolean extraction | 0% | 0% |
| Numeric typed extraction | 50% | 0% |
| Canonical choice / multi-choice / compound | 0% / 0% / 0% | 0% / 0% / 0% |
| Correction / reference | 66.7% | 0% |
| Hallucinated option rate | 6.5% | 0% |
| Malformed call / engine failure rate | 29.0% | 6.5% |
| Peak process RSS | 397.7 MiB | 79.1 MiB |
| Cold host latency p50 / p95 | 2046 / 2941 ms | 1047 / 2590 ms |
| Model decision | MODEL_NO_GO | MODEL_NO_GO |

Needle's two engine failures are date cases exhausting the unchanged 512-token
budget (`error_code: truncated`); their native envelopes are valid JSON.
The frozen scorer classifies unsuccessful engine responses as malformed-call failures.
All accepted actions satisfy the strict hard correctness checks; neither model
passes the extraction quality thresholds. Safe rejection does not establish model quality.

## FunctionGemma ablation evidence

[Recorded raw outputs and validation](../../benchmarks/function_gemma_ablation/results.json)
contain 35 runs: seven cases, five repetitions each, with greedy decoding and seed 42.
Outputs were identical within each case.

| Tools / input | Produced | Expected success |
| --- | --- | ---: |
| set_string: My name is Mukil | name = Mukil | 5/5 |
| set_boolean: Yes I consent | consent = true | 5/5 |
| set_boolean: I do not consent | consent = true (wrong negation) | 0/5 |
| set_boolean + clear_field: Yes I consent | clear consent | 0/5 |
| set_boolean + clear_field: I do not consent | clear consent | 0/5 |
| set_integer: There were four registers open | numeric field IDs 3, 2, 1 with values 4, 10, 5; rejected | 0/5 |
| set_integer + set_boolean: Age thirty two, consent yes | age = 32, consent = untyped `yes`; rejected | 0/5 |

Adding clear_field changes valid positive setters into clear actions. Independent
negation, field-ID and typed boolean failures also occur without that competition.
The evidence supports MODEL_NO_GO without changing tools or relaxing expectations.
FunctionGemmaAdapter remains available and benchmarked.

## Needle implementation and evaluation

[NeedleAdapter](../../packages/form_assistant_needle/lib/form_assistant_needle.dart)
implements the existing IntelligenceAdapter interface. It reuses compact
SemanticContext formatting, dynamic specialization of the eight extraction tools,
strict DTO/context validation and canonical mapping in place. No core architecture,
production FunctionGemma behavior, runtime bridge or frozen fixture was changed.
The evaluation harness gained an adapter entry point with identical scoring; a
31-case recorded FunctionGemma replay test verifies unchanged scores and state results.

The official local CLI receives separate factual context, JSON tools and the same
natural-language inputs. It uses one-turn completion, one thread, full depth,
512 output tokens, no forced calls, no tool execution and no cloud fallback.
Pinned official artifact revision: `2ae11323dc000f5e70c49f7403efa6af12ba9e67`.
The [complete report](../../benchmarks/needle3_phase6r/reports/needle3.v1.json)
records model/binary SHA-256, every request, raw native output, parsed calls,
confidence, suppression, strict validation, canonical actions and resulting state.
See the [package instructions](../../packages/form_assistant_needle/README.md).

The native Needle engine includes grammar constraints, grounding/repair and
confidence suppression; its CLI does not expose pre-repair model tokens.
This comparison evaluates the supplied local engines under the same extraction
contract, rather than claiming identical neural decoding. The adapter performs no
repair. Native suppressed calls remain diagnostic and never become accepted actions.
The existing QualityGate minimum confidence remains 0.8.

None of Needle's outputs reached 0.8. Its four complete passes were ambiguous or
out-of-context inputs requiring no mutation. Including suppressed candidates yields
only 6/31 exact sets, so lowering confidence would not resolve most extraction errors.
Examples: age thirty two became 30; positive consent became clear_field; the critical
compound input produced age writes 30, 8 and 9 without a boolean. City = Bangalore
and clear promotion were correct returned calls, but remained below the existing
confidence threshold. No expected outputs were modified to accommodate these failures.

Cold host timings include model/process startup. Needle model TTFT and token counts
are unavailable and recorded as null. Zebra device measurements remain outstanding;
no device-performance GO is claimed.

## Reproducible comparison and stop point

Run `python3 tools/compare_extraction_models.py` from the repository root.
It checks corpus/config/context hashes and identical case IDs, inputs, expected calls,
expected state and context fingerprints before producing the [JSON comparison](../../benchmarks/model_comparison/comparison.v1.json)
and [per-case CSV](../../benchmarks/model_comparison/comparison.v1.csv).
The original FunctionGemma raw report is preserved; the Needle complete benchmark
was run against the exact frozen corpus. Benchmark failures are recorded, not fixed.

Validation: formatter and fatal analyzer pass; 273 software tests pass
(core 120, FunctionGemma 80, external-form 33, Needle 40). Canonical and extraction
schema checks pass. These software checks do not override either MODEL_NO_GO.
Stop here: Phase 7 has not been started.

## Qwen3VL-2B follow-up

Qwen3VL-2B host eval against the same frozen corpus scored **22/31** complete
cases (critical 0/3) and remains **MODEL_NO_GO**. See
[QWEN3VL_2B.md](QWEN3VL_2B.md). The comparison tool now includes all three
recorded models.

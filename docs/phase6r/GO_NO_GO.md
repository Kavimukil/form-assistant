# Phase 6R FunctionGemma result: MODEL_NO_GO

Date: 2026-10-06. Recovery implementation and review completed; the model-quality
gate fails. **Frozen category gate: NO-GO.** Phase 7 later started under the
2026-10-22 29/31 acceptance amendment at the end of this file. This is not a
project restart.

## Evidence

- Evaluation commits: `e38bb37` (correlated native schema), `6f97d78` (flat native candidate enums).
- Device/runtime: managed Linux x86_64 CPU, llama.cpp b11429 / d81235049,
  one CPU thread, cold process per case. Zebra target not measured.
- Model: functiongemma-270m-it-q8_0.gguf, no fine-tuning;
  SHA-256 `83940d4dd9676710856f43523bed096164a595a96f6b34771610a03937de5270`.
- Corpus: v1, 31 frozen cases / 17 categories, three critical-case repetitions;
  SHA-256 `f788fc886642f9b9a7f371e4a3e46c426ad2215ac264635803eda701dc08dad5`.
- Cases executed: 62 across two schema variants; temperature 0, seed 42.
- [Correlated native report](../../benchmarks/function_gemma_phase6r/reports/baseline.v1.json)
- [Simpler native report](../../benchmarks/function_gemma_phase6r/reports/simple_native.v1.json)
- [Machine-readable review](../../benchmarks/function_gemma_phase6r/reports/review.v1.json)

## Model-quality gate

Both variants passed 7/31 complete cases (22.6%). Simpler native schema results:

| Metric | Actual | Required | Gate |
| --- | --- | --- | --- |
| Simple single-field exact | 35.7% | >=97% | FAIL |
| Boolean exact | 0% | >=98% | FAIL |
| Integer/number typed exact | 50% | >=97% | FAIL |
| Choice canonical ID | 0% | >=97% | FAIL |
| Multi-choice exact set | 0% | >=93% | FAIL |
| Compound exact action set | 0% | >=92% | FAIL |
| Correction/reference exact | 66.7% | >=90% | FAIL |
| Hallucinated field rate | 0% | <=1% | PASS |
| Hallucinated option rate | 6.5% | <=1% | FAIL |
| Malformed native/DTO output rate | 29.0% | <=2% | FAIL |
| Critical age+consent | 0/3 per variant | reliably succeed | FAIL |

Flat native enums reduced malformed cases from 13/31 to 9/31, but did not improve
complete correctness. The corpus, constraints, expected calls and gate config were
unchanged. No repair, workflow tools, fine-tuning or fallback masked failures.
The benchmark is small: ratios are engineering gate evidence, not population
accuracy estimates. Legacy 12-case scores are preserved but not equivalent metrics.

## Deterministic correctness

Zero unauthorized/out-of-context canonical field IDs accepted; zero unknown option
IDs accepted; zero wrong-type or malformed-date calls committed; zero raw source IDs
accepted. Relevant and unrelated revision races pass with authoritative CAS and
cache enabled; stale results are never blindly committed. Static live cases do not
exercise stale races: that evidence comes from the software integration suites.

These guarantees do not establish semantic correctness. The model recorded valid
but incorrect values in permitted fields: weight 72 rather than 72.5, extra React
in a multi-choice selection, and age/consent values invented for “My country is
India.” These are failed cases, not successful safety filtering or acceptable UX.

## Primary failures and measurements

Simpler variant primary failures: TOOL_FORMAT (9), VALUE_EXTRACTION (6),
FIELD_SELECTION (4), MODEL_HALLUCINATION (2), NEGATION (1), MULTI_CHOICE_STATE (1),
REFERENCE_RESOLUTION (1). Every failed case is categorized in the raw report. The broader invalid-tool/argument/context rejection rate is 45.2% (including malformed output and conflicting or unauthorized candidate calls); it is recorded separately in the machine-readable review.

Host p50/p95 total inference: 2046/2941 ms. First-output-byte TTFT p50/p95:
1449/1630 ms, including process/model loading. Peak RSS: 407200 KiB (~397.7 MiB).
Input/output token counters are recorded per case. These are host measurements;
no target Zebra viability or latency-budget claim is made.

## Required follow-up

Verify original checkpoint/tokenizer/GGUF conversion parity before attributing all
failure to the FunctionGemma model family. The tested artifact/current constrained
integration is NO-GO. If it remains unreliable, evaluate another IntelligenceAdapter
against the same frozen corpus, keeping canonical contracts, compact context,
QualityGate, ActionRuntime and FormStateBridge. Fine-tuning or replacement is a
separate future decision; neither was implemented. Phase 7 remains blocked.


## Focused ablation evidence

Formal model status: **MODEL_NO_GO — FunctionGemma 270M**. Its adapter, raw reports,
frozen expectations and architecture are preserved as a benchmarked implementation.
[35-run ablation](../../benchmarks/function_gemma_ablation/results.json): setter-only
name and positive consent succeed 5/5; adding clear_field flips positive consent
to clear 5/5. Negation still returns true 5/5 with only set_boolean, register
extraction invents numeric field IDs 5/5 with only set_integer, and compound
extraction without clear_field emits invalid yes 5/5. Tool competition is real,
but removing clear_field does not cure basic semantic/field/type failures.

Needle 3 is evaluated separately through IntelligenceAdapter using the same compact
SemanticContext, frozen eight-tool contract and corpus. No Phase 6R architecture
or benchmark requirements are changed, and this record does not authorize Phase 7.

Needle 3 candidate evaluation is complete: **MODEL_NO_GO**, 4/31 complete cases,
critical compound 0/3. See [model comparison](../model_evaluation/FUNCTIONGEMMA_VS_NEEDLE3.md).
The recovery architecture and frozen gate remain unchanged; Phase 7 remains blocked.

Qwen3VL-2B host-eval candidate is complete: **MODEL_NO_GO**, 22/31 complete cases,
critical compound 0/3. Boolean/numeric typed gates pass; compound/multi-object
JSON format and simpleExact still fail. See
[Qwen3VL decision](../model_evaluation/QWEN3VL_2B.md).

Qwen3-4B-Instruct-2507 host-eval candidate is complete: **MODEL_NO_GO**, 22/31;
critical compound **3/3**; malformed 0%; remaining fails are ambiguity /
multi_add / noise value extraction. See
[Qwen3-4B decision](../model_evaluation/QWEN3_4B.md).

Qwen3VL-8B-Instruct host-eval candidate is complete: **MODEL_NO_GO**, **26/31**;
critical **3/3**; simpleExact 100%; remaining fails are negation_consent,
reference_multi, ambiguous_number, noise_compound, noise_choice. See
[Qwen3VL-8B decision](../model_evaluation/QWEN3VL_8B.md).

Qwen3.8-27B host-eval candidate is complete: **MODEL_NO_GO**, **29/31**;
critical **3/3**; simpleExact, boolean, numeric, multi-choice, and
correction/reference gates pass. Choice canonical stays 75% and compound exact
stays 80%. Remaining fails are noise_compound (age 30 vs 32) and noise_choice
(empty calls vs promotion=fall). See
[Qwen3.8-27B decision](../model_evaluation/QWEN3_8_27B.md).

## Amendment 2026-10-22 — Phase 7 permitted

The frozen thresholds in `benchmarks/function_gemma_phase6r/gate.v1.json` are
unchanged. Qwen3.8-27B still fails that category gate on choice canonical
(75%) and compound exact (80%).

Product acceptance for leaving Phase 6R is **at least 29/31 complete cases**
on the same frozen corpus. Qwen3.8-27B meets that bar at 29/31, with critical
age+consent 3/3. Known residuals stay `noise_compound` (age 30 instead of 32)
and `noise_choice` (no call instead of promotion `fall`).

Phase 7 is therefore permitted as local-first hybrid/cloud fallback. The 27B
GGUF remains a host artifact. Zebra latency and memory were not measured, so
this amendment does not make that file the on-device runtime.

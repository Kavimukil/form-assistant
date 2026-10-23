# Phase 6R model decision: MODEL_NO_GO — functiongemma270_trained

Host eval of `functiongemma270_trained.gguf` on the unchanged frozen 31-case
corpus. Same FunctionGemma adapter, prompt, tools, and gate as the untuned
Q8_0 baseline. Phase 7 remains blocked.

| Measure | Untuned 270M Q8_0 | functiongemma270_trained |
| --- | ---: | ---: |
| Complete cases | 7/31 (22.6%) | **3/31 (9.7%)** |
| Critical age + consent | 0/3 | **0/3** |
| Malformed call rate | 29.0% | **67.7%** |
| Hallucinated option rate | 6.5% | 16.1% |
| Cold host p50 / p95 | 2046 / 2941 ms | 853 / 957 ms |
| Decision | MODEL_NO_GO | **MODEL_NO_GO** |

Passes: `boolean_consent`, `string_name`, `correction_age`.

## What the outputs show

18/31 are TOOL_FORMAT. The continuation is often a new user turn instead of a
function call, for example `integer_age` produced
`<start_of_turn>user\nOkay so the age is not 32.`

When a call is well formed, values are still wrong: `string_city` wrote
`Bhopal` instead of `Bangalore`; `multi_selection` emitted a string instead of
an option-id list; critical compound wrote age 32 and dropped consent.

## Artifacts

- SHA-256: `6452fdf7c89be44a861e3e3de1961d642db5b5acad12a9728ee4b5fe6bcf47bd`
- Report: [trained.v1.json](../../benchmarks/function_gemma_phase6r/reports/trained.v1.json)
- Runtime: CPU llama.cpp b11445 / commit `58cb913`, cold process per case

Stop here: Phase 7 has not been started.

# form_assistant_qwen3vl

Qwen3VL llama.cpp IntelligenceAdapter using the unchanged Phase 6R compact
SemanticContext, eight-tool extraction contract and deterministic validators.
No runtime-core, FunctionGemma production behavior, vocabulary, expected answer
or benchmark threshold is changed.

Supply `Qwen3VlAdapter(inference: localGenerate)`. The callback receives
`Qwen3VlInferenceRequest` (fully formatted Qwen chat prompt) and a
CancellationToken and returns `Qwen3VlOutput` containing the model text.
The host owns loading, local inference and physical abort. This package does
not execute tool functions or mutate form state.

Formatting reuses the existing compact canonical context projection and
dynamically specialized schemas in the FunctionGemma package. The model must
emit strict JSON only:

```json
{"function_calls":[{"name":"set_integer","arguments":{"field_id":"age","value":32}}]}
```

JSON duplicate keys, malformed primitives, extra arguments, wrong types,
conflicting writes, unknown fields/options and non-writable fields are rejected
without repair. Same QualityGate minimum confidence 0.8 when confidence is
present; confidence and provenance stay outside FormAction/FormValue.

## Local benchmark

Pinned host artifact: `Qwen3VL-2B-Instruct-Q4_K_M.gguf` at the repository root.
Use a llama.cpp `llama-completion` binary that successfully loads this GGUF.
Model/binary hashes are recorded in the report. No fine-tuning or hosted
inference is used. Text-only prompts (no images).

Run in this package:

```
dart pub get
dart test
dart run bin/evaluate_qwen3vl.dart \
  --binary /path/to/llama-completion \
  --model ../../Qwen3VL-2B-Instruct-Q4_K_M.gguf
```

The evaluator reads the exact frozen corpus/contexts/gate config from
`benchmarks/function_gemma_phase6r`, guards their SHA-256 hashes, and invokes
the same shared scoring/runtime implementation. Reports land under
`benchmarks/qwen3vl_phase6r/reports/`.

Result: MODEL_NO_GO for Qwen3VL-2B against the current extraction contract —
22/31 complete cases; critical compound 0/3. See
docs/model_evaluation/QWEN3VL_2B.md.

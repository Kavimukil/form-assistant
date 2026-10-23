# form_assistant_needle

Needle 3 IntelligenceAdapter using the unchanged Phase 6R compact SemanticContext,
eight-tool extraction contract and deterministic validators. No runtime-core,
FunctionGemma production behavior, vocabulary, expected answer or benchmark threshold
is changed. FunctionGemmaAdapter remains available as the benchmarked implementation.

Supply `NeedleAdapter(inference: localGenerate)`. The callback receives
NeedleInferenceRequest (systemFacts, toolsJson, natural-language input) and a
CancellationToken and returns NeedleOutput containing the native JSON engine reply.
The host owns loading, local inference and physical abort. This package does not
execute tool functions or mutate form state. Use one-turn completion, not Needle's
agentic run loop; runtime/bridge remain authoritative.

Formatting reuses the existing compact canonical context projection and dynamically
specialized schemas in the FunctionGemma package in place. This deliberate internal
package dependency avoids a shared-contract/architecture rewrite. The tools use the
current flat native choice-candidate enum projection, with per-field correlation
checked by the unchanged strict validator. No workflow tools, triggers, forced calls,
raw source schema, implicit date facts or cloud fallback are added.

Native response `function_calls` becomes strict eight-tool DTOs and existing
canonical actions. JSON duplicate keys, malformed primitives, extra arguments,
wrong types, conflicting writes, unknown fields/options and non-writable fields
are rejected without repair. Same QualityGate minimum confidence 0.8; confidence
and provenance stay outside FormAction/FormValue. `suppressed_calls` are diagnostic
only; ungrounded fields cannot become mutations. Engine errors remain errors.
Timeout/cancellation suppress late output and signal the callback to abort.

Needle's shipped native engine has schema-constrained decoding and documented
built-in grounding/repair and suppression. The adapter itself adds no repair or
coercion. The CLI exposes its returned envelope, not pre-grammar/pre-repair token
output. Reports disclose this distinction and do not present its candidate metrics
as unassisted raw model accuracy.

## Local benchmark

The pinned official artifacts are downloaded to /tmp, outside the production
package. Artifact revision: 2ae11323dc000f5e70c49f7403efa6af12ba9e67 from
https://huggingface.co/Cactus-Compute/needle3 . Model/binary hashes are in the report.
No fine-tuning or hosted inference is used. Evaluation disables engine telemetry
with NEEDLE_TELEMETRY=0 and DO_NOT_TRACK=1.

Run in this package:

```
dart pub get --offline
dart test
dart run bin/evaluate_needle3.dart \
  --binary /tmp/form-assistant-needle3/needle \
  --model /tmp/form-assistant-needle3/needle3.cact
```

The evaluator reads the exact frozen corpus/contexts/gate config from
benchmarks/function_gemma_phase6r, guards their SHA-256 hashes, and invokes the same
shared scoring/runtime implementation. Reports capture system facts, actual tool
JSON, input, native output, calls/suppressed candidates, confidence, validation,
canonical proposals, states, failure taxonomy and host latency/RSS. Token counts
and model TTFT are unavailable from this CLI and are explicitly null, never invented.

Result: MODEL_NO_GO for the supplied full-depth base Needle 3 artifact/current
extraction contract. See docs/model_evaluation/FUNCTIONGEMMA_VS_NEEDLE3.md.

Official runtime/API references:
- https://github.com/cactus-compute/needle
- https://github.com/cactus-compute/needle/blob/main/llms.txt

# Frozen FunctionGemma Phase 6R corpus v1

31 cases, 17 categories, explicit v1.1 contexts, expected typed calls and expected
clarification behavior. Critical age+consent extraction is repeated three times
with exactly those two fields selected. No expected output is included in live
prompts. No case/expectation may be changed to fit a failed model response. Any
future revision requires a new corpus version and explicit rationale.

Run in the adapter package:

```
dart run bin/evaluate_phase6r.dart \
  --binary /tmp/form-assistant-llama/llama-b11429/llama-completion \
  --model ../../functiongemma-270m-it-q8_0.gguf
```

`gate.v1.json` freezes the plan's quality thresholds. Target-device latency budget
is deliberately unset: this host is not the Zebra target. Deterministic decoding
(temp0, seed42) and model/corpus SHA-256 are recorded. Reports include every prompt,
raw continuation, stderr, envelope/call decoding, proposal, quality decision,
expected/final state, failure class and JSON/CSV metrics. A nonzero runner exit
means quality thresholds failed, not that report generation failed.

Scripted corpus tests verify the harness/runtime only. Live CLI always invokes the
GGUF. Raw extraction is scored before QualityGate modifies proposals; invalid age
150 can be correctly extracted while its commit is rejected. Ambiguous/out-of-context
answers require no calls and deterministic clarification, not model workflow tools.
Only independent action order and multi-choice set order are normalized. No type,
label-to-ID or date repairs. Exact comparison does not remove duplicate writes.

TTFT is first generated stdout byte including model/process load, not instrumented
per-token timing. Token counts come from llama.cpp performance diagnostics. Peak RSS
comes from /usr/bin/time and includes model loading. No target-device claim follows.
Legacy corpus metrics are preserved separately and not numerically comparable to
this expanded exact-action benchmark.

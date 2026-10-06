# Benchmark specification

Frozen inputs in benchmarks/function_gemma_phase6r/corpus.v1.jsonl; production-codec
context fixtures; thresholds in gate.v1.json. 31 cases span all 17 required
categories; the critical two-field case is repeated three times. Software regression
tests exercise every expected call through the real adapter/parser/QualityGate and
ActionRuntime/FormStateBridge using scripted generation, plus adversarial output
and unchanged legacy tests. Real evaluation never uses scripted outputs.

Metrics are per-case exactness: exact action set, selected fields, all typed values,
simple, boolean, numeric, choice, multi-choice, compound, corrections/references;
case hallucinated field/option and malformed-tool rates; unnecessary no-answer and
clarification; invalid constraint extraction separately from deterministic rejection.
Both extraction and expected commit/clarification must pass for a complete case.
Each failed case has a primary taxonomy category. Scalar/date/type mismatches are
never repaired. Raw output and parsed envelopes remain inspectable on rejection.

Independent mutations are order-independent for scoring; multi-choice order is set
normalized. Runtime retains input order. Duplicate calls are not erased for exact
scoring, even if the validator can safely deduplicate identical writes.

Input/output tokens: llama.cpp counters; TTFT: first stdout byte; p50/p95 total
latency and peak RSS: host measurements. Target Zebra latency/memory viability
remains unmeasured; no invented latency threshold or automatic GO is permitted.

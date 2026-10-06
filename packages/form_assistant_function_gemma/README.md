# form_assistant_function_gemma

FunctionGemma IntelligenceAdapter, isolated from core and all form stores. Supply
`FunctionGemmaAdapter(inference: localGenerate)` where localGenerate has signature
`Future<FunctionGemmaOutput> Function(String prompt, CancellationToken token)`.
The host owns model loading, tokenizer, local inference runtime and physical abort.
The internal InferenceBackend interface and formatter/parser are not exported.
No model is downloaded, trained or contacted over a network by this package.

The zero-shot prompt uses FunctionGemma developer/user/model turns, native
function declaration/call tokens and `<escape>` string delimiters, based on
[Google's formatting guide](https://ai.google.dev/gemma/docs/functiongemma/formatting-and-best-practices).
The callback receives a complete prompt including the open model turn and must
return only the newly generated continuation, not the echoed prompt. Configure
engine stopping at `<end_of_turn>`/`<eos>` or function-response boundaries; return
all tool calls for one proposal before stopping. The parser accepts consecutive
calls and an optional terminal end-of-turn or eos marker. It rejects function
responses, prose, JSON, unknown tools, duplicate/extra arguments and malformed
values; it never repairs output or commits a valid prefix of an invalid response.

Typed model tools (set_string/integer/number/boolean/date/choice/multi_choice)
map to the existing canonical SetValueAction and strict FormValue codecs.
clear_value, navigate and request_clarification map to the unchanged canonical
vocabulary. navigate target uses next/previous or a selected canonical field ID.
The tool schema contains only allowed action families. Prompt context excludes
extensions, raw form/schema data and unselected values. Untrusted user/context
control-token characters are JSON escaped to prevent closing the model turn.

QualityGate checks allowed actions, selected field identity, type/constraints and
optional model confidence before returning proposals. Low confidence (default
threshold 0.8), unknown context fields and empty output clarify. Valid actions can
be retained alongside invalid-value clarification in a multi-action proposal.
Confidence is optional because most runners do not produce a calibrated score;
absent confidence does not imply high confidence and is not invented. Confidence
and quality diagnostics remain outside canonical actions/values. Runtime and
bridge still perform fresh validation and final concurrency checks.

IntelligenceOptions supports timeout and cooperative cancellation. Timeouts and
cancellation release the caller, signal backend cancellation and ignore late
outputs/errors. A host runner should observe the token to physically abort work.
Cancellation cannot roll back an authoritative write already dispatched/committed.
No cloud fallback exists. Model unavailability and malformed output surface as
errors; manual form state remains usable.

Run `dart pub get --offline`, `dart analyze`, `dart test --reporter expanded`.
The twelve-category evaluation fixture corpus checks final canonical state and
clarification through the headless runtime, plus malformed parser, quality,
formatting and cancellation tests. **Outputs are hand-authored scripted fixtures,
not recorded FunctionGemma generations.** Passing these verifies the adapter
pipeline, not zero-shot model quality. Live results are recorded separately in
`docs/evaluation/P6_GGUF_EVALUATION.json`; the tested GGUF currently fails P6.

## Live GGUF evaluation

Run from this package directory:

```sh
dart run bin/evaluate_gguf.dart \
  --binary /tmp/form-assistant-llama/llama-b11429/llama-completion \
  --model ../../functiongemma-270m-it-q8_0.gguf
```

The runner uses the existing twelve-case corpus without scripted completions or
changing expected states. It captures prompts, real outputs, runner diagnostics,
model SHA-256, generation settings and final runtime state. CPU-only llama.cpp
build b11429 is an external evaluation tool, not a core/package dependency.
Temperature is zero, seed 42, one CPU thread, context 8192 tokens and output cap
512 tokens. Per-case inference timeout is two minutes. Generation stops at the
native function-response boundary; the runner removes only llama-completion's
terminal display marker and the configured terminal stop marker. Parser validation
remains strict. Exit code 1 means the complete-case corpus did not pass.

The baseline scored 0/12 complete cases. After stopping function responses and
improving zero-shot descriptions/type-specific declarations, the supplied Q8_0
model scored **2/12 complete cases**, with **5/12 field-state matches**. The latter
includes unchanged initial/empty states and is not equivalent to successful
interpretation. No incorrect values committed in these runs; refusals/malformed
arguments were rejected. P6 remains failed; no fine-tuning, parser repair or cloud
fallback was introduced. Two formatter regression tests protect typed declarations
and escaping of untrusted tool metadata.


## Natural-language extraction persona and JSON output

The developer turn defines a form-answer extraction assistant: extract all explicit
slots by canonical field ID, use the active field for unambiguous unnamed answers,
preserve negation, take the final corrected value, and clarify unresolved answers.
User input remains natural language. Context and user text are data; output must
contain declared tool calls with exact argument names and types.

Use `await adapter.interpretJson(request)` for a JSON-safe proposal envelope,
then `jsonEncode` to serialize it. Its `proposal.actions[].action` contains the
unchanged canonical action/value JSON; provenance, confidence and quality remain
outside those actions. This returns a proposal, not a form-state commit. The model
continues using its native function-call format, which the adapter converts to JSON.

The persona-only comparison in `docs/evaluation/P6_GGUF_PERSONA_EVALUATION.json`
scored **1/12 complete cases** and **5/12 final-state matches**, compared with the
previous 2/12 complete cases. Model, corpus and generation settings were unchanged.
Malformed calls, refusals and unrelated navigation persist. This small comparison
does not establish persona wording as the main cause, and the live P6 gate remains
failed. The report includes canonical proposed actions for inspection.

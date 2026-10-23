# Focused tool-competition ablation

Standalone experiment. Production behavior, frozen 6R corpus, thresholds and status
are unchanged. No runtime commits, failure repair, prompt tuning or architecture changes.

Run from repository root:

```
/tmp/form-assistant-sdk/dart-sdk/bin/dart \
  --packages=packages/form_assistant_function_gemma/.dart_tool/package_config.json \
  packages/form_assistant_function_gemma/tool/run_ablation.dart
```

The script imports current SemanticContext codecs, specialized schema builder,
native formatter, strict parser/validator, canonical mapper and QualityGate. Only
exposed tool names change. It invokes the same GGUF/llama-completion binary and
Phase 6R generation flags directly. Contexts and expected outputs are loaded from
frozen fixtures, not embedded into the model instructions. No baseline report is
replaced. `results.json` captures prompts, raw/transport output, stderr, parsed
calls/envelopes, parse errors, validation/quality, expected output and correctness.

Five repeats per case, temperature zero, seed42, one CPU thread. All repeated raw
outputs were identical (35 runs total). B and C use identical context and expected
outputs; C prompts also match the current simple-native 6R report byte-for-byte.

| Group | Input | Expected | Actual every repeat | Correct |
| --- | --- | --- | --- | --- |
| A: set_string | My name is Mukil | name=Mukil | name=Mukil | 5/5 |
| B: set_boolean | Yes I consent | consent=true | consent=true | 5/5 |
| B: set_boolean | I do not consent | consent=false | consent=true | 0/5 |
| C: set_boolean + clear_field | Yes I consent | consent=true | clear consent | 0/5 |
| C: set_boolean + clear_field | I do not consent | consent=false | clear consent | 0/5 |
| D: set_integer | There were four registers open | register_count=4 | field_id 3=4, 2=10, 1=5 | 0/5 |
| E: set_integer + set_boolean | Age thirty two, consent yes | age=32, consent=true | age=32, consent=yes (invalid native boolean) | 0/5 |

A/B/C outputs are structurally valid, including semantically wrong true/clear
results. D and E fail strict parsing/typing and are not mapped to canonical actions.
Clear-field exposure flips positive boolean extraction from correct true to clear
in this controlled pair. Negation and register-field extraction also fail without
clear_field, and compound boolean output remains malformed without it. Both tool
competition and basic semantic/field/type extraction failures are present in this
small tested setup; removing clear_field alone does not resolve them.

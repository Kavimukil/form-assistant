# 02 — Repository Structure

Target monorepo:

```text
form-assistant/
├── README.md
├── melos.yaml                         # optional after package count justifies it
├── analysis_options.yaml
├── docs/
│   ├── 01_ARCHITECTURE_DECISIONS.md
│   ├── 02_REPOSITORY_STRUCTURE.md
│   ├── 03_CONTRACTS.md
│   ├── 04_PHASED_IMPLEMENTATION.md
│   ├── 05_GATES.md
│   └── 06_TEST_MATRIX.md
├── contracts/
│   └── schemas/
│       ├── form-value.schema.json
│       ├── form-action.schema.json
│       ├── form-state.schema.json
│       └── bridge-event.schema.json
├── packages/
│   ├── form_assistant_core/
│   │   ├── lib/
│   │   │   ├── form_assistant_core.dart
│   │   │   └── src/
│   │   │       ├── contracts/
│   │   │       │   ├── form_value.dart
│   │   │       │   ├── form_action.dart
│   │   │       │   ├── form_ir.dart
│   │   │       │   ├── form_adapter.dart
│   │   │       │   ├── form_state.dart
│   │   │       │   ├── form_state_bridge.dart
│   │   │       │   ├── bridge_events.dart
│   │   │       │   ├── intelligence.dart
│   │   │       │   ├── stt.dart
│   │   │       │   └── trace.dart
│   │   │       ├── runtime/
│   │   │       │   ├── form_assistant_runtime.dart
│   │   │       │   ├── action_runtime.dart
│   │   │       │   ├── input_router.dart
│   │   │       │   ├── runtime_events.dart
│   │   │       │   ├── production.dart
│   │   │       │   ├── native_form.dart
│   │   │       │   └── multilingual.dart
│   │   │       ├── state/
│   │   │       │   └── local_form_state_bridge.dart
│   │   │       ├── validation/
│   │   │       └── context/
│   │   └── test/
│   ├── form_assistant_flutter/
│   │   └── Phase 9 chrome, plus a Phase 11 native-form renderer
│   ├── form_assistant_function_gemma/
│   │   └── FunctionGemma IntelligenceAdapter implementation
│   ├── form_assistant_needle/
│   │   └── Needle 3 IntelligenceAdapter (evaluated MODEL_NO_GO)
│   ├── form_assistant_qwen3vl/
│   │   └── Qwen3VL llama.cpp IntelligenceAdapter (host-eval MODEL_NO_GO)
│   ├── form_assistant_stt/
│   │   └── Phase 8 host STT session; contract stays in core
│   └── form_assistant_cloud/
│       └── Phase 7 CloudLLMAdapter and HybridIntelligenceAdapter
├── bindings/
│   └── form_assistant_react/
│       └── Phase 12 protocol 1.0 decoder; not a second runtime
└── examples/
    ├── external_form_integration/
    ├── flutter_existing_form/
    │   └── source Flutter form; no dependency on form_assistant_flutter
    ├── flutter_assistant_shell/
    │   └── optional chrome around flutter_existing_form
    └── local_form_runtime/
```

## Dependency direction

```text
contracts/core
    ^
    |
runtime
    ^
    |
+---+--------------------+
|                        |
Flutter binding     adapters/providers
                         |
               FunctionGemma / Needle / Qwen3VL / STT / Cloud
```

Core must not import Flutter, provider-specific inference runtimes, source-project types, or cloud SDKs.

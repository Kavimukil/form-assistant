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
│   │   │       │   └── runtime_events.dart
│   │   │       ├── state/
│   │   │       │   └── local_form_state_bridge.dart
│   │   │       ├── validation/
│   │   │       └── context/
│   │   └── test/
│   ├── form_assistant_flutter/
│   │   └── thin Flutter-facing bindings only
│   ├── form_assistant_function_gemma/
│   │   └── FunctionGemma IntelligenceAdapter implementation
│   ├── form_assistant_stt/
│   │   └── concrete STT implementation(s), not STT contract
│   └── form_assistant_cloud/
│       └── optional cloud IntelligenceAdapter
└── examples/
    ├── external_form_integration/
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
               FunctionGemma / STT / Cloud
```

Core must not import Flutter, provider-specific inference runtimes, source-project types, or cloud SDKs.

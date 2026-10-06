# Phase 6R constrained intelligence recovery

Phases 0–5 preserved; original Phase 6 superseded and tagged. Recovery branch:
phase-6r-functiongemma-recovery. FunctionGemma is an eight-tool typed slot extractor,
not a form agent. FormStateBridge remains the sole authoritative commit boundary.

- [Task status](PHASE_6R_STATUS.md)
- [Architecture decision](ADR-006-CONSTRAINED-FUNCTIONGEMMA.md)
- [Old implementation inventory](OLD_PHASE6_INVENTORY.md)
- [SemanticContext v1.1](SEMANTIC_CONTEXT_V1_1.md)
- [Tool protocol](FUNCTIONGEMMA_TOOL_PROTOCOL_V1.md)
- [Specialization and native variant](TOOL_SCHEMA_SPECIALIZATION.md)
- [Quality policy](QUALITY_GATE.md)
- [Fingerprints/cache/concurrency](CACHE_AND_FINGERPRINTS.md)
- [Benchmark specification](BENCHMARK_SPEC.md)
- [GO/NO-GO decision](GO_NO_GO.md)

Checks per task: format, analyzer with fatal infos, all core/adapter/external tests,
canonical schema checks, whitespace checks. New extraction schema checker added at
6R.10. Each task is committed separately after its software gate passes. Original
canonical golden tests and legacy model fixture expectations are retained.

The final decision gates model viability independently of deterministic software
correctness. No Phase 7 or fine-tuning is part of this recovery.

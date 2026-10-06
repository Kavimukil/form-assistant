# Phase 6R status

Original Phase 6 superseded. Phases 0–5 preserved. Phase 7 blocked.

| Task | Status | Evidence |
| --- | --- | --- |
| 6R.0 | GREEN | Baseline tag f1a32df; branch; inventory/ADR; analyzer, 175 tests and 42 schema checks pass |
| 6R.1 | GREEN | v1.1 codec, compatible accessors, writable lifecycle, caps and identity; 178 tests/analyzer/schema checks pass |
| 6R.2 | GREEN | Eight-tool DTO/schema golden; analyzer, 180 tests and schema checks pass |
| 6R.3 | GREEN | Specialized/correlated option schema golden, writable filtering; 183 tests and checks pass |
| 6R.4 | GREEN | Strict native parser/DTO/context validator; negative matrix and conflict policy; 185 tests/checks pass |
| 6R.5 | GREEN | All eight canonical mappings, order/revision/provenance; 187 tests/checks pass |
| 6R.6 | GREEN | Public adapter now compact extraction only; legacy path isolated, no old expectations changed; 191 tests/checks pass |
| 6R.7 | GREEN | Deterministic constraint/empty/readonly policy, internal outcomes, trace/bridge coverage; 194 tests/checks pass |
| 6R.8 | GREEN | Exact selected-context identity path, rev17→18 relevant/unrelated races; 196 tests/checks pass |
| 6R.9 | GREEN | Bounded prepared-declaration LRU, exact cache/uncached prompts, invalidation and concurrency; 198 tests/checks pass |
| 6R.10–6R.11 | NOT STARTED | Execute in exact order |

Migration: historical adapter/formatter and corpus remain internal legacy files and tests, and the old runner explicitly uses the legacy adapter. Public adapter v0.2.0 uses only extraction tools. This preserves baseline reproducibility without broadening the new path.

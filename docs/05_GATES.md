# 05 — Gates and Non-Negotiable Checks

## Architecture gate
Fail build/review if:
- core imports Flutter UI;
- runtime imports project-specific schema/store classes;
- runtime checks `bridge is Local...` / `External...`;
- model directly mutates state;
- model-specific JSON becomes canonical action JSON;
- FormAdapter starts owning live state;
- source encodings enter FormIR/state;
- full raw schema is passed to model;
- cloud becomes required for normal operation.

## State gate
- bridge snapshot is authoritative;
- ActionApplied only after authoritative commit;
- expectedRevision checked atomically with write;
- no-op/failure doesn't increment revision;
- focus-only changes don't increment semantic revision;
- events are ordered;
- state is committed/published before StateChanged;
- external echoed write counted once;
- atomic batch never silently downgrades.

## Contract gate
- strict codecs;
- malformed types rejected;
- finite numbers only;
- valid real YYYY-MM-DD dates only;
- multi-choice dedupe + deterministic sort;
- immutable public collections;
- structural equality/hashCode;
- metadata JSON-safe;
- optional nulls omitted;
- canonical IDs, never labels, used for choices.

## Intelligence gate
- zero-shot first;
- compact SemanticContext only;
- FunctionGemma behind adapter;
- confidence/provenance outside canonical action/value;
- stale proposal policy enforced;
- correctness measured as final state.

## Voice gate
- partial cannot commit;
- final exactly once;
- confidence layers separate;
- audio not persisted by default;
- cancellation prevents late commits.

## Release gate
No production release until:
- all phase gates through target phase pass;
- public API documented;
- compatibility fixtures pass;
- telemetry does not leak raw sensitive values by default;
- existing form remains functional without assistant.

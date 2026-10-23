# QualityGate

Native parser and context validator reject malformed syntax, types, unauthorized
fields/options, non-writable fields and conflicts before canonical proposal mapping.
Identical writes are deduplicated with a count; independent call order is preserved.
Provider-neutral QualityGate validates constraints and allowed actions; invalid values
become canonical clarification and cannot commit. Empty extraction clarifies.

Internal outcomes are ACCEPT/REJECT/CLARIFY/FALLBACK. `QualityGate.evaluate` still
returns only accept or clarify, and ambiguous reasons stay clarify even when
fallback is allowed. Phase 7 `considerFallback` promotes only a non-ambiguous
local failure, and `HybridIntelligenceAdapter` is what routes that to cloud.
Strict decoding errors remain explicit exceptions, not repaired empty answers.
Canonical outcomes remain compatible accept/clarify.

Migration conflict: original core test intentionally retains a valid write and
clarifies an invalid same-field write. Keep that provider-neutral default unchanged;
6R explicitly enables rejectConflictingWrites, and its context validator rejects
conflicts earlier. Historical tests/expectations remain unchanged. Read-only checks
are provider-neutral; runtime/bridge still enforce authorization and fresh validation.

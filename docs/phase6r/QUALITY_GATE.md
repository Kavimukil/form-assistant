# QualityGate

Native parser and context validator reject malformed syntax, types, unauthorized
fields/options, non-writable fields and conflicts before canonical proposal mapping.
Identical writes are deduplicated with a count; independent call order is preserved.
Provider-neutral QualityGate validates constraints and allowed actions; invalid values
become canonical clarification and cannot commit. Empty extraction clarifies.

Internal outcomes are ACCEPT/REJECT/CLARIFY/FALLBACK. FALLBACK is reserved and not
routed in the initial benchmark. Strict decoding errors remain explicit exceptions,
not repaired empty answers. Canonical outcomes remain compatible accept/clarify.

Migration conflict: original core test intentionally retains a valid write and
clarifies an invalid same-field write. Keep that provider-neutral default unchanged;
6R explicitly enables rejectConflictingWrites, and its context validator rejects
conflicts earlier. Historical tests/expectations remain unchanged. Read-only checks
are provider-neutral; runtime/bridge still enforce authorization and fresh validation.

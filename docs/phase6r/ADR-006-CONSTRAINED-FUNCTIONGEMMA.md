# ADR-006: Constrained FunctionGemma

Accepted for Phase 6R. Original Phase 6 is superseded, preserved by tag and raw
reports. FunctionGemma proposes typed slots from bounded canonical context using
seven specialized setters and clear_field. It never controls navigation, submit,
clarification, rules, authorization or commits. Strict parser/context validator
and provider-neutral QualityGate precede ActionRuntime/FormStateBridge. Canonical
contracts remain stable; semantic context evolves with explicit v1.1 encoding
and compatibility accessors. Revision, semantic fingerprint and schema identity
are separate. Frozen expectations are not modified for model failures. A NO-GO
replaces the intelligence implementation, not the deterministic foundation.

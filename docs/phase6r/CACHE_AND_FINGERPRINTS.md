# Context identity, revisions and cache

Revision governs stale detection and authoritative CAS. Semantic fingerprint is
exact canonical JSON of model-relevant selected context, excludes revision. Schema
fingerprint is exact canonical JSON of the specialized permitted output space.
These identities are never interchangeable.

Runtime compares a fresh projection of the same selected context. Relevant changes
cause discard/re-inference. Unrelated changes preserve semantic identity, emit
ProposalRevalidated, and execute against the latest authoritative expected revision.
Additional touched/dependency value checks remain. Existing CAS/retry behavior is
preserved. Core types contain no FunctionGemma cache or schema machinery.

Bounded per-adapter LRU capacity=32 caches prepared native declarations only. The
exact output space is rebuilt for identity each time (measured separately); native
encoding is avoided on hits. No inference result/context/answer/proposal is cached.
Keys include cache/protocol/adapter/builder versions, normalized locale and exact
schema fingerprint, never revision/form/session/context fingerprint. Labels and
active/current values remain fresh in the uncached compact context. Truncation flag
alone is a HIT because supplied candidate IDs encode permitted outputs. Candidate
ID changes are MISS. Metrics: hits, misses, specialization/preparation microseconds.
Tests verify cache/uncached prompt equality and LRU invalidation; all revision tests
run with caching enabled and remain green.

# 06 — Test Matrix

## FormValue
- every type round-trip;
- malformed discriminator/value type;
- NumberValue rejects NaN/±Infinity;
- integer != number;
- date validates leap year/month/day;
- StringValue preserves whitespace/case;
- ChoiceValue rejects empty ID;
- MultiChoice dedupes/sorts and equality is order independent;
- hashCode consistent with equality.

## FormAction
- round-trip every action;
- equality ignores execution identity because identity is external;
- classification correct;
- clarification fieldIds dedupe/sort;
- malformed action rejected;
- unknown action rejected by 1.0 strict decoder unless future compatibility wrapper explicitly handles it.

## Validation metadata
- JSON-safe metadata recursively checked;
- validation revision preserved;
- issue codes preserved;
- optional null fields omitted.

## LocalStateBridge
- set/clear/no-op;
- unknown field/type/constraint rejection;
- stale revision;
- concurrent stale race;
- atomic all-pass;
- atomic one-fail rollback;
- best-effort partial;
- event ordering;
- snapshot visible before event;
- undo/redo;
- disposal;
- immutable snapshot.

## ExternalStateBridge
- initial snapshot mapping;
- canonical -> source mapping;
- source -> canonical mapping;
- Y/N boolean example;
- option key/ID mapping;
- bridge write + store echo = one revision;
- manual store write = external event;
- async ack;
- ack timeout;
- external override;
- store failure;
- concurrent external update during inference;
- unsubscribe/dispose.

## Runtime
- mutation routing;
- navigation routing;
- clarification routing;
- capability rejection;
- stale proposal unrelated change -> revalidate;
- stale proposal relevant change -> reinterpret;
- race after stale check -> bridge rejection;
- multi-action partial acceptance;
- trace IDs.

## Deterministic router
- yes/no variants;
- numeric words/digits;
- exact choice;
- conservative fuzzy choice;
- ambiguity;
- correction;
- unsupported.

## Context compiler
- huge form;
- current field;
- dependencies;
- recent values;
- field budget;
- token/char budget;
- deterministic output;
- no raw source schema.

## Intelligence evaluation
- simple;
- multi-field;
- correction;
- negation;
- ambiguous;
- out-of-order;
- previous reference;
- invalid;
- unsupported;
- no answer;
- long;
- ASR typo/noise;
- fallback;
- offline.

## STT
- partial/final ordering;
- partial never commit;
- duplicate final suppression;
- cancel race;
- error recovery;
- segment provenance.

## Property/soak
Generate long random sequences of:
- local actions;
- external actions;
- stale proposals;
- batches;
- undo/redo;
and assert revision monotonicity, snapshot/event consistency, no duplicate logical commits and deterministic replay.

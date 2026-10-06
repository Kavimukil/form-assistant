# Existing form integration example — Phase 2

This Dart example demonstrates the primary existing-form integration path. It
adds no renderer, model, runtime orchestration or voice layer.

- ExistingFormSchema/ExistingFormState/ExistingFormStore are source-project types.
- ProjectExampleFormAdapter compiles only source schema into minimum V1 FormIR.
- ProjectExampleExternalStateBridge maps the existing store into canonical
  snapshots and canonical actions into existing store mutations.
- The existing store remains the sole owner of committed answers and focus;
  manual edits continue to work after disposing the assistant bridge.

The source uses different storage keys and choice keys, and Y/N boolean strings.
For example, `CONSENT_YN: "Y"` maps to BooleanValue(true), and
`COLOR_KEY: "B"` maps to ChoiceValue("blue"). Source keys/encodings never enter
FormIR or canonical snapshots/actions. All seven V1 value kinds are demonstrated
in tests, including absent answers and unordered multi-choice sets.

The fake store is intentionally framework-independent. Its compareAndApply
checks a source version and commits without an asynchronous gap between check
and mutation. Manual/external changes advance the same source version. Test
barriers delay dispatch/receipts to exercise real acknowledgement races;
echoes, source errors and timeouts are also covered. Source versions advance
for focus/spinners as well as values. Bridge semantic revisions advance only
for observed value/lifecycle changes and are scoped to each bridge instance.

The source SPI types are runtime-only integration primitives, not new canonical
JSON contract formats. Actual integrations must supply coherent immutable
snapshots, ordered notifications, operation correlation and commit-time
concurrency checks. A dispatched/accepted request is not a committed receipt.
No source-store transaction support means atomic batches are unavailable; the
bridge never substitutes a local transaction. This example does not provide
external-store undo/redo.

Run from this directory:

```sh
dart pub get
dart run bin/main.dart
dart test
```

Run `dart analyze` and `dart format packages examples` from the repository root.
The tests include a seeded 1,000-operation source/assistant simulation checked
against independent canonical state, revision and event-replay expectations.

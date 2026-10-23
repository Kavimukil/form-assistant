# Integration cookbook

The host owns the form. These steps sit beside `FormAssistantRuntime` and do
not replace the store.

## 1. Record a redacted interaction

```dart
final memory = MemoryTelemetrySink();
final sink = RedactingTelemetrySink(memory);
final timer = StageTimer();

timer.start(TelemetryStage.commit);
final result = await runtime.submit(
  UserInput(text: utterance),
  trace: trace,
);
timer.stop(TelemetryStage.commit);

final observation = observeInteraction(
  route: InputRoute.deterministic,
  result: result,
  stateMatched: result.snapshot.values['age'] == const IntegerValue(32),
  latencyMs: timer.milliseconds,
);
sink.record(TelemetryRecord(
  name: observation.path == ResolutionPath.unresolved
      ? TelemetryName.interactionFailed
      : TelemetryName.interactionCompleted,
  trace: result.trace,
  path: observation.path,
  failure: observation.failure,
  attributes: {
    'fieldId': 'age',
    'utterance': utterance,
  },
  latencyMs: timer.milliseconds,
));
```

With the default policy the stored record keeps `fieldId` and the commit
timing. The utterance is dropped. Do not put audio bytes in attributes; those
keys are removed even when text and values are explicitly enabled.

Pass `usedFallback: true` only when the hybrid adapter actually called cloud.
Pass `correction: true` for an explicit correction. Those flags are how
fallback rate and correction rate are counted.

## 2. Summarize a session

```dart
final metrics = ProductionMetrics.from(observations);
metrics.deterministicRate;
metrics.localModelRate;
metrics.fallbackRate;
metrics.clarificationRate;
metrics.correctionRate;
metrics.stateAccuracy;
metrics.errorContribution(FailureClass.stt);
metrics.latency[TelemetryStage.model]?.p95Ms;
```

Rates are counts divided by the number of observations. Error contribution
divides by the number of unresolved observations. An empty batch is zero.

## 3. Keep an eval trace only when policy says so

```dart
final store = EvalTraceStore(policy: policy);
final kept = store.persist(EvalTrace(
  interactionId: trace.interactionId,
  outcome: observation.path.name,
  fieldIds: const ['age'],
  utterance: utterance,
  fieldValues: {'age': 32},
));
```

`kept` is false for the default policy, and `store.traces` stays empty.
Turning on `persistEvalTraces` still stores a redacted trace until
`includeUtterance` or `includeFieldValues` is also set.

## 4. Recover from the committed snapshot

```dart
final checkpoint = RecoveryCheckpoint.capture(
  bridge.snapshot,
  inFlightProposalIds: const ['proposal-in-flight'],
);
```

After a restart, load the store and project it through the same bridge. Resume
only when the restored snapshot matches:

```dart
const recovery = CrashRecovery();
if (!recovery.resume(bridge.snapshot, checkpoint)) {
  // The restored store is not the committed checkpoint.
}
```

Do not apply `checkpoint.abandonedProposalIds`. A proposal that never reached
`ActionApplied` is discarded. The form package, including
`examples/flutter_existing_form`, keeps working when the assistant package is
absent; recovery reads the bridge snapshot the host already owns.

## 5. Check protocol 1.0 before accepting a saved action document

```dart
final document = ProtocolDocument.decode(json);
```

`specVersion` must be `1.0`. Each action is a canonical `FormAction`. An
unknown action type throws `FormatException`. The checked fixture is
`packages/form_assistant_core/test/fixtures/protocol_1_0.json`.

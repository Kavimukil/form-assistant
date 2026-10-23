import '../contracts/canonical_json.dart';
import '../contracts/form_action.dart';
import '../contracts/form_state.dart';
import '../contracts/form_value.dart';
import '../contracts/trace.dart';
import 'input_router.dart';
import 'runtime_events.dart';

/// Keys removed from telemetry unless a policy flag explicitly keeps them.
/// Audio and raw bytes are never kept.
const sensitiveTelemetryKeys = <String>{
  'utterance',
  'text',
  'transcript',
  'value',
  'values',
  'audio',
  'raw',
};

/// Host policy for telemetry and eval traces. Every flag defaults off.
final class TelemetryPolicy {
  final bool includeUtterance;
  final bool includeFieldValues;
  final bool persistEvalTraces;
  const TelemetryPolicy({
    this.includeUtterance = false,
    this.includeFieldValues = false,
    this.persistEvalTraces = false,
  });
}

enum TelemetryStage { stt, context, model, validation, commit }

enum TelemetryName { interactionCompleted, interactionFailed }

/// How an interaction was resolved. [unresolved] is a failure, not a rate of success.
enum ResolutionPath {
  deterministic,
  localModel,
  fallback,
  clarification,
  unresolved,
}

/// Where a failed interaction is attributed. [none] is not a failure.
enum FailureClass { none, stt, contextSelection, model, adapter, runtime }

/// One structured telemetry event. Attributes are JSON. Sensitive keys are the
/// host's responsibility until [redacted] runs.
final class TelemetryRecord {
  final TelemetryName name;
  final TraceContext? trace;
  final ResolutionPath? path;
  final FailureClass failure;
  final Map<String, Object?> attributes;
  final Map<TelemetryStage, int> latencyMs;
  TelemetryRecord({
    required this.name,
    this.trace,
    this.path,
    this.failure = FailureClass.none,
    Map<String, Object?> attributes = const {},
    Map<TelemetryStage, int> latencyMs = const {},
  })  : attributes = Map<String, Object?>.unmodifiable(
            jsonObject(<String, Object?>{...attributes})),
        latencyMs = Map<TelemetryStage, int>.unmodifiable(latencyMs) {
    for (final milliseconds in this.latencyMs.values) {
      if (milliseconds < 0) throw ArgumentError('Negative latency');
    }
  }

  TelemetryRecord redacted(TelemetryPolicy policy) => TelemetryRecord(
      name: name,
      trace: trace,
      path: path,
      failure: failure,
      attributes: redactTelemetryAttributes(attributes, policy),
      latencyMs: latencyMs);

  Map<String, Object?> toJson() => {
        'name': name.name,
        if (trace != null) 'trace': trace!.toJson(),
        if (path != null) 'path': path!.name,
        'failure': failure.name,
        'attributes': attributes,
        'latencyMs': {
          for (final entry in latencyMs.entries) entry.key.name: entry.value,
        },
      };
}

/// Drops sensitive keys. [TelemetryPolicy.includeUtterance] keeps utterance,
/// text, and transcript. [TelemetryPolicy.includeFieldValues] keeps value and
/// values. `audio` and `raw` are always removed.
Map<String, Object?> redactTelemetryAttributes(
    Map<String, Object?> attributes, TelemetryPolicy policy) {
  return Map<String, Object?>.unmodifiable(
      _redactMap(jsonObject(attributes), policy));
}

const Object _dropped = Object();

Map<String, Object?> _redactMap(
    Map<String, Object?> input, TelemetryPolicy policy) {
  final redacted = <String, Object?>{};
  for (final entry in input.entries) {
    final kept = _redactEntry(entry.key, entry.value, policy);
    if (!identical(kept, _dropped)) redacted[entry.key] = kept;
  }
  return redacted;
}

Object? _redactEntry(String key, Object? value, TelemetryPolicy policy) {
  switch (key) {
    case 'audio':
    case 'raw':
      return _dropped;
    case 'utterance':
    case 'text':
    case 'transcript':
      return policy.includeUtterance ? value : _dropped;
    case 'value':
    case 'values':
      return policy.includeFieldValues ? value : _dropped;
  }
  if (value is Map<String, Object?>) return _redactMap(value, policy);
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map((Object? item) {
      if (item is Map<String, Object?>) return _redactMap(item, policy);
      return item;
    }));
  }
  return value;
}

/// Host destination for telemetry. Implementations must not assume attributes
/// still contain utterances or field values.
abstract interface class TelemetrySink {
  void record(TelemetryRecord record);
}

/// Forwards records after redaction. The default policy removes sensitive values.
final class RedactingTelemetrySink implements TelemetrySink {
  final TelemetrySink next;
  final TelemetryPolicy policy;
  const RedactingTelemetrySink(this.next,
      {this.policy = const TelemetryPolicy()});

  @override
  void record(TelemetryRecord record) => next.record(record.redacted(policy));
}

/// In-memory sink for tests and a single process. This is not an eval archive.
final class MemoryTelemetrySink implements TelemetrySink {
  final List<TelemetryRecord> records = [];

  @override
  void record(TelemetryRecord record) => records.add(record);
}

/// Manual stage timings. Pass [nowMs] in tests; otherwise the clock is wall time.
final class StageTimer {
  final int Function() nowMs;
  final Map<TelemetryStage, int> _started = {};
  final Map<TelemetryStage, int> _elapsed = {};
  StageTimer({int Function()? nowMs})
      : nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  void start(TelemetryStage stage) {
    if (_started.containsKey(stage)) {
      throw StateError('Stage ${stage.name} is already running');
    }
    _started[stage] = nowMs();
  }

  void stop(TelemetryStage stage) {
    final started = _started.remove(stage);
    if (started == null) {
      throw StateError('Stage ${stage.name} was not started');
    }
    final elapsed = nowMs() - started;
    if (elapsed < 0) {
      throw StateError('Clock moved backwards');
    }
    _elapsed[stage] = elapsed;
  }

  Map<TelemetryStage, int> get milliseconds =>
      Map<TelemetryStage, int>.unmodifiable(_elapsed);
}

/// Nearest-rank percentile. [percentile] is in `(0, 1]`.
int latencyPercentile(Iterable<int> samples, double percentile) {
  if (percentile <= 0 || percentile > 1) {
    throw ArgumentError('Percentile must be in (0, 1]');
  }
  final values = samples.toList()..sort();
  if (values.isEmpty) throw ArgumentError('No latency samples');
  for (final value in values) {
    if (value < 0) throw ArgumentError('Negative latency');
  }
  final index = (percentile * values.length).ceil() - 1;
  return values[index];
}

final class StageLatencySummary {
  final TelemetryStage stage;
  final int count;
  final int p50Ms;
  final int p95Ms;
  const StageLatencySummary(
      {required this.stage,
      required this.count,
      required this.p50Ms,
      required this.p95Ms});
}

/// One finished or failed interaction, already classified.
final class InteractionObservation {
  final ResolutionPath path;
  final FailureClass failure;
  final bool stateMatched;
  final bool correction;
  final Map<TelemetryStage, int> latencyMs;
  InteractionObservation({
    required this.path,
    this.failure = FailureClass.none,
    required this.stateMatched,
    this.correction = false,
    Map<TelemetryStage, int> latencyMs = const {},
  }) : latencyMs = Map<TelemetryStage, int>.unmodifiable(latencyMs) {
    if (path == ResolutionPath.unresolved && failure == FailureClass.none) {
      throw ArgumentError('Unresolved interaction needs a failure class');
    }
    if (path != ResolutionPath.unresolved && failure != FailureClass.none) {
      throw ArgumentError(
          'Failure class is only set for unresolved interactions');
    }
    for (final milliseconds in this.latencyMs.values) {
      if (milliseconds < 0) throw ArgumentError('Negative latency');
    }
  }
}

/// Rates over a batch of observations. Empty input yields zero rates.
final class ProductionMetrics {
  final int interactions;
  final int deterministicCount;
  final int localModelCount;
  final int fallbackCount;
  final int clarificationCount;
  final int correctionCount;
  final int stateMatchedCount;
  final int failureCount;
  final Map<FailureClass, int> failureCounts;
  final Map<TelemetryStage, StageLatencySummary> latency;
  ProductionMetrics({
    required this.interactions,
    required this.deterministicCount,
    required this.localModelCount,
    required this.fallbackCount,
    required this.clarificationCount,
    required this.correctionCount,
    required this.stateMatchedCount,
    required this.failureCount,
    required Map<FailureClass, int> failureCounts,
    required Map<TelemetryStage, StageLatencySummary> latency,
  })  : failureCounts = Map<FailureClass, int>.unmodifiable(failureCounts),
        latency =
            Map<TelemetryStage, StageLatencySummary>.unmodifiable(latency);

  factory ProductionMetrics.from(
      Iterable<InteractionObservation> observations) {
    final items = observations.toList();
    var deterministic = 0;
    var localModel = 0;
    var fallback = 0;
    var clarification = 0;
    var correction = 0;
    var matched = 0;
    final failures = <FailureClass, int>{};
    final samples = <TelemetryStage, List<int>>{};
    for (final item in items) {
      switch (item.path) {
        case ResolutionPath.deterministic:
          deterministic++;
        case ResolutionPath.localModel:
          localModel++;
        case ResolutionPath.fallback:
          fallback++;
        case ResolutionPath.clarification:
          clarification++;
        case ResolutionPath.unresolved:
          break;
      }
      if (item.correction) correction++;
      if (item.stateMatched) matched++;
      if (item.failure != FailureClass.none) {
        failures[item.failure] = (failures[item.failure] ?? 0) + 1;
      }
      for (final entry in item.latencyMs.entries) {
        (samples[entry.key] ??= <int>[]).add(entry.value);
      }
    }
    return ProductionMetrics(
        interactions: items.length,
        deterministicCount: deterministic,
        localModelCount: localModel,
        fallbackCount: fallback,
        clarificationCount: clarification,
        correctionCount: correction,
        stateMatchedCount: matched,
        failureCount: failures.values.fold<int>(0, (sum, count) => sum + count),
        failureCounts: failures,
        latency: {
          for (final entry in samples.entries)
            entry.key: StageLatencySummary(
                stage: entry.key,
                count: entry.value.length,
                p50Ms: latencyPercentile(entry.value, 0.5),
                p95Ms: latencyPercentile(entry.value, 0.95)),
        });
  }

  double _rate(int count) => interactions == 0 ? 0 : count / interactions;

  double get deterministicRate => _rate(deterministicCount);
  double get localModelRate => _rate(localModelCount);
  double get fallbackRate => _rate(fallbackCount);
  double get clarificationRate => _rate(clarificationCount);
  double get correctionRate => _rate(correctionCount);
  double get stateAccuracy => _rate(stateMatchedCount);

  /// Share of failed interactions attributed to [failure]. Zero when nothing failed.
  double errorContribution(FailureClass failure) {
    if (failure == FailureClass.none || failureCount == 0) return 0;
    return (failureCounts[failure] ?? 0) / failureCount;
  }
}

/// Classifies a finished runtime interaction. A correction is a separate flag:
/// it can also be deterministic. Fallback is explicit because the runtime does
/// not record which adapter served the proposal.
InteractionObservation observeInteraction({
  InputRoute? route,
  bool usedFallback = false,
  bool correction = false,
  RuntimeInteractionResult? result,
  bool stateMatched = false,
  FailureClass failure = FailureClass.none,
  Map<TelemetryStage, int> latencyMs = const {},
}) {
  final code = result?.errorCode;
  final resolvedFailure = _failureFor(failure, code);
  final clarified = route == InputRoute.needsClarification ||
      (result?.actions.any((action) => action.clarification != null) ?? false);
  final ResolutionPath path;
  if (resolvedFailure != FailureClass.none) {
    path = ResolutionPath.unresolved;
  } else if (clarified) {
    path = ResolutionPath.clarification;
  } else if (usedFallback) {
    path = ResolutionPath.fallback;
  } else if (route == InputRoute.deterministic) {
    path = ResolutionPath.deterministic;
  } else {
    path = ResolutionPath.localModel;
  }
  return InteractionObservation(
      path: path,
      failure: resolvedFailure,
      stateMatched: stateMatched,
      correction: correction,
      latencyMs: latencyMs);
}

FailureClass _failureFor(FailureClass given, String? errorCode) {
  if (given != FailureClass.none) return given;
  if (errorCode == null) return FailureClass.none;
  if (errorCode == 'runtime.context_budget_exceeded') {
    return FailureClass.contextSelection;
  }
  if (errorCode.startsWith('stt.')) return FailureClass.stt;
  if (errorCode.startsWith('model.')) return FailureClass.model;
  if (errorCode.startsWith('adapter.')) return FailureClass.adapter;
  return FailureClass.runtime;
}

/// An eval trace kept only when policy allows. Raw utterance and values are
/// stored only behind their own flags.
final class EvalTrace {
  final String interactionId;
  final String outcome;
  final List<String> fieldIds;
  final String? utterance;
  final Map<String, Object?>? fieldValues;
  EvalTrace({
    required this.interactionId,
    required this.outcome,
    List<String> fieldIds = const [],
    this.utterance,
    Map<String, Object?>? fieldValues,
  })  : fieldIds = List<String>.unmodifiable(fieldIds),
        fieldValues = fieldValues == null
            ? null
            : Map<String, Object?>.unmodifiable(jsonObject(fieldValues)) {
    if (interactionId.isEmpty || outcome.isEmpty) {
      throw ArgumentError('Eval trace identity is empty');
    }
  }
}

/// Refuses to keep traces unless [TelemetryPolicy.persistEvalTraces] is set.
final class EvalTraceStore {
  final TelemetryPolicy policy;
  final List<EvalTrace> _traces = [];
  EvalTraceStore({this.policy = const TelemetryPolicy()});

  List<EvalTrace> get traces => List<EvalTrace>.unmodifiable(_traces);

  /// Returns false and stores nothing when persistence is off.
  bool persist(EvalTrace trace) {
    if (!policy.persistEvalTraces) return false;
    _traces.add(EvalTrace(
        interactionId: trace.interactionId,
        outcome: trace.outcome,
        fieldIds: trace.fieldIds,
        utterance: policy.includeUtterance ? trace.utterance : null,
        fieldValues: policy.includeFieldValues ? trace.fieldValues : null));
    return true;
  }
}

/// The committed bridge snapshot is the recovery source. In-flight proposals
/// are named and then abandoned; they are not replayed.
final class RecoveryCheckpoint {
  final String formId;
  final int revision;
  final Map<FieldId, FormValue> values;
  final List<String> abandonedProposalIds;
  RecoveryCheckpoint._({
    required this.formId,
    required this.revision,
    required Map<FieldId, FormValue> values,
    required List<String> abandonedProposalIds,
  })  : values = Map<FieldId, FormValue>.unmodifiable(values),
        abandonedProposalIds = List<String>.unmodifiable(abandonedProposalIds);

  factory RecoveryCheckpoint.capture(FormStateSnapshot committed,
      {Iterable<String> inFlightProposalIds = const []}) {
    final abandoned = inFlightProposalIds.toList()..sort();
    if (abandoned.any((id) => id.isEmpty)) {
      throw ArgumentError('Empty proposal id');
    }
    return RecoveryCheckpoint._(
        formId: committed.formId,
        revision: committed.revision,
        values: Map<FieldId, FormValue>.of(committed.values),
        abandonedProposalIds: abandoned);
  }

  bool matches(FormStateSnapshot snapshot) =>
      snapshot.formId == formId &&
      snapshot.revision == revision &&
      jsonEquals(snapshot.values, values);
}

/// Resume is allowed only when the restored snapshot is the checkpoint.
/// Replaying [RecoveryCheckpoint.abandonedProposalIds] is not part of recovery.
final class CrashRecovery {
  const CrashRecovery();

  bool resume(FormStateSnapshot restored, RecoveryCheckpoint checkpoint) =>
      checkpoint.matches(restored);
}

/// Protocol 1.0 action document. Any other `specVersion` is rejected.
final class ProtocolDocument {
  final String specVersion;
  final List<FormAction> actions;
  ProtocolDocument(
      {this.specVersion = protocolSpecVersion,
      required List<FormAction> actions})
      : actions = List<FormAction>.unmodifiable(actions) {
    if (specVersion != protocolSpecVersion) {
      throw const FormatException('Unsupported specVersion');
    }
  }

  static ProtocolDocument decode(Object? input) {
    final json = jsonObject(input);
    if (json['specVersion'] != protocolSpecVersion) {
      throw const FormatException('Unsupported specVersion');
    }
    final encoded = requireType<List<Object?>>(json['actions']);
    return ProtocolDocument(
        actions: encoded.map(FormActionCodec.decode).toList());
  }
}

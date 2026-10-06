import 'dart:async';

import 'canonical_json.dart';
import 'form_ir.dart';
import 'form_state_bridge.dart';
import 'form_value.dart';
import 'trace.dart';
import 'validation_metadata.dart';

/// Phase 3 text boundary; no microphone, transcript processing or parsing.
final class UserInput {
  final String text;
  final SegmentId? segmentId;
  const UserInput({required this.text, this.segmentId});
}

final class FormFieldContext {
  final FormField field;
  const FormFieldContext({required this.field});
}

final class InteractionHistoryEntry {
  final String interactionId;
  final String text;
  final List<FieldId> fieldIds;
  InteractionHistoryEntry(
      {required this.interactionId,
      required this.text,
      List<FieldId> fieldIds = const []})
      : fieldIds = List.unmodifiable(fieldIds);
}

final class SemanticContext {
  final FormId formId;
  final Revision revision;
  final FieldId? activeFieldId;
  final List<FormFieldContext> fields;
  final Map<FieldId, FormValue> values;
  final String locale;
  final List<InteractionHistoryEntry> history;
  SemanticContext(
      {required this.formId,
      required this.revision,
      this.activeFieldId,
      required List<FormFieldContext> fields,
      required Map<FieldId, FormValue> values,
      this.locale = 'en',
      List<InteractionHistoryEntry> history = const []})
      : fields = List.unmodifiable(fields),
        values = Map.unmodifiable(values),
        history = List.unmodifiable(history);
}

final class IntelligenceRequest {
  final UserInput input;
  final SemanticContext context;
  final List<String> allowedActionTypes;
  final TraceContext trace;
  IntelligenceRequest(
      {required this.input,
      required this.context,
      required Iterable<String> allowedActionTypes,
      required this.trace})
      : allowedActionTypes = canonicalStrings(allowedActionTypes);
}

/// Cooperative cancellation shared by runtime and inference adapters.
final class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void throwIfCancelled() {
    if (_cancelled) throw const IntelligenceCancelled();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }
}

final class IntelligenceCancelled implements Exception {
  const IntelligenceCancelled();
}

final class IntelligenceOptions {
  final Duration timeout;
  final CancellationToken? cancellation;
  const IntelligenceOptions(
      {this.timeout = const Duration(seconds: 30), this.cancellation});
}

/// Applies timeout/cancellation even to adapters without physical abort support.
/// Late completions are observed but never returned to the caller.
Future<T> runIntelligence<T>(
    Future<T> Function() work, IntelligenceOptions options) async {
  if (options.timeout <= Duration.zero) {
    throw ArgumentError('Invalid inference timeout');
  }
  options.cancellation?.throwIfCancelled();
  final result = Completer<T>();
  final detach = options.cancellation?.listen(() {
    if (!result.isCompleted) {
      result.completeError(const IntelligenceCancelled());
    }
  });
  final timer = Timer(options.timeout, () {
    if (!result.isCompleted) {
      result.completeError(
          TimeoutException('Intelligence timeout', options.timeout));
    }
  });
  try {
    Future<T>.sync(work).then((value) {
      if (!result.isCompleted) result.complete(value);
    }, onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
    return await result.future;
  } finally {
    timer.cancel();
    detach?.call();
  }
}

final class ActionProvenance {
  final TraceContext trace;
  final String adapterId;
  final String adapterVersion;
  final ActionOrigin origin;
  const ActionProvenance(
      {required this.trace,
      required this.adapterId,
      required this.adapterVersion,
      this.origin = ActionOrigin.intelligence});
}

final class ActionProposal {
  final ProposalId id;
  final Revision baseRevision;
  final List<ProposedAction> actions;
  final ActionProvenance provenance;
  final double? confidence;
  ActionProposal(
      {required this.id,
      required this.baseRevision,
      required List<ProposedAction> actions,
      required this.provenance,
      this.confidence})
      : actions = List.unmodifiable(actions) {
    if (baseRevision < 0 ||
        (confidence != null &&
            (!confidence!.isFinite || confidence! < 0 || confidence! > 1))) {
      throw ArgumentError('Invalid proposal revision/confidence');
    }
    if (id.isEmpty ||
        actions.any((a) => a.id.isEmpty) ||
        actions.map((a) => a.id).toSet().length != actions.length) {
      throw ArgumentError('Proposal/action IDs must be nonempty and unique');
    }
  }
}

enum QualityOutcome { accept, clarify }

final class IntelligenceResult {
  final ActionProposal proposal;
  final QualityOutcome? quality;
  final String? qualityReason;
  const IntelligenceResult(
      {required this.proposal, this.quality, this.qualityReason});
}

abstract interface class IntelligenceAdapter {
  String get id;
  String get version;
  Future<IntelligenceResult> interpret(IntelligenceRequest request,
      {IntelligenceOptions? options});
}

/// The only intelligence implementation in Phase 3: caller-scripted results.
final class MockIntelligenceAdapter implements IntelligenceAdapter {
  @override
  final String id;
  @override
  final String version;
  final FutureOr<IntelligenceResult> Function(IntelligenceRequest request)
      handler;
  final List<IntelligenceRequest> _requests = [];
  List<IntelligenceRequest> get requests => List.unmodifiable(_requests);
  MockIntelligenceAdapter(
      {required this.handler, this.id = 'mock', this.version = '0.1.0'});
  @override
  Future<IntelligenceResult> interpret(IntelligenceRequest request,
      {IntelligenceOptions? options}) async {
    return runIntelligence(() async {
      _requests.add(request);
      return await handler(request);
    }, options ?? const IntelligenceOptions());
  }
}

import 'dart:async';
import 'dart:collection';

import 'package:form_assistant_core/form_assistant_core.dart';

// These are source-project types. They never become core contract types.
enum ExistingFieldType {
  text,
  integer,
  decimal,
  yesNo,
  date,
  select,
  multiSelect
}

final class ExistingOption {
  final String key;
  final String canonicalId;
  final String label;
  const ExistingOption(
      {required this.key, required this.canonicalId, required this.label});
}

final class ExistingField {
  final String storageKey;
  final String canonicalId;
  final String label;
  final ExistingFieldType type;
  final List<ExistingOption> options;
  final bool required;
  final num? min;
  final num? max;
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  ExistingField(
      {required this.storageKey,
      required this.canonicalId,
      required this.label,
      required this.type,
      List<ExistingOption> options = const [],
      this.required = false,
      this.min,
      this.max,
      this.minLength,
      this.maxLength,
      this.pattern})
      : options = List.unmodifiable(options);
}

final class ExistingFormSchema {
  final String canonicalId;
  final List<ExistingField> fields;
  ExistingFormSchema(
      {required this.canonicalId, required List<ExistingField> fields})
      : fields = List.unmodifiable(fields);
}

final class ExistingFormState {
  final Map<String, Object?> answers;
  final String? focusedStorageKey;
  final FormLifecycle lifecycle;
  final bool spinnerVisible;
  ExistingFormState(
      {Map<String, Object?> answers = const {},
      this.focusedStorageKey,
      this.lifecycle = FormLifecycle.active,
      this.spinnerVisible = false})
      : answers = jsonObject(answers);
}

sealed class ExistingMutation {
  const ExistingMutation();
}

final class ExistingAnswerMutation extends ExistingMutation {
  final String storageKey;
  final Object? value;
  final bool clear;
  const ExistingAnswerMutation(
      {required this.storageKey, this.value, this.clear = false});
}

final class ExistingFocusMutation extends ExistingMutation {
  final String? storageKey;
  const ExistingFocusMutation(this.storageKey);
}

/// Fake existing application store. Manual form code and the bridge both write
/// here; this store, not the assistant, owns values and the commit/version check.
final class ExistingFormStore
    implements ExternalStateSource<ExistingFormState, ExistingMutation> {
  @override
  final bool supportsAtomicBatch;
  late ExternalStoreSnapshot<ExistingFormState> _snapshot;
  final StreamController<ExternalStoreSnapshot<ExistingFormState>> _changes =
      StreamController<ExternalStoreSnapshot<ExistingFormState>>.broadcast(
          sync: true);
  bool _disposed = false;
  bool _publishing = false;
  final Queue<ExternalStoreSnapshot<ExistingFormState>> _notifications =
      Queue();
  int writeRequests = 0;
  // Deterministic fake-store controls for acknowledgement/race/failure tests.
  Completer<void>? commitBarrier;
  Completer<void>? receiptBarrier;
  bool suppressEcho = false;
  Object? nextWriteFailure;

  ExistingFormStore(
      {ExistingFormState? initialState, this.supportsAtomicBatch = true}) {
    _snapshot = ExternalStoreSnapshot(
        version: 0, state: initialState ?? ExistingFormState());
  }
  @override
  ExternalStoreSnapshot<ExistingFormState> get snapshot => _snapshot;
  @override
  Stream<ExternalStoreSnapshot<ExistingFormState>> get changes =>
      _changes.stream;
  bool get hasSubscribers => _changes.hasListener;
  ExternalStoreSnapshot<ExistingFormState> _publish(ExistingFormState state,
      {OperationId? operationId, bool notify = true}) {
    if (_disposed) throw StateError('Store disposed');
    _snapshot = ExternalStoreSnapshot(
        version: _snapshot.version + 1, state: state, operationId: operationId);
    final committed = _snapshot;
    if (notify) _notify(committed);
    return committed;
  }

  void _notify(ExternalStoreSnapshot<ExistingFormState> update) {
    _notifications.add(update);
    if (_publishing) return;
    _publishing = true;
    try {
      while (_notifications.isNotEmpty) {
        _changes.add(_notifications.removeFirst());
      }
    } finally {
      _publishing = false;
    }
  }

  @override
  Future<ExternalWriteResult<ExistingFormState>> compareAndApply(
      List<ExistingMutation> mutations,
      {required int expectedSourceVersion,
      required OperationId operationId,
      required bool atomic}) async {
    writeRequests++;
    if (atomic && !supportsAtomicBatch) {
      throw StateError('Atomic writes unsupported');
    }
    final gate = commitBarrier;
    if (gate != null) await gate.future;
    if (_disposed) throw StateError('Store disposed');
    final failure = nextWriteFailure;
    nextWriteFailure = null;
    if (failure != null) throw failure;
    // No await between CAS and publication: even delayed writes check at commit.
    if (_snapshot.version != expectedSourceVersion) {
      return ExternalWriteConflict(_snapshot);
    }
    var focused = _snapshot.state.focusedStorageKey;
    final answers = Map<String, Object?>.of(_snapshot.state.answers);
    for (final mutation in mutations) {
      switch (mutation) {
        case ExistingAnswerMutation(
            :final storageKey,
            :final value,
            :final clear
          ):
          if (clear) {
            answers.remove(storageKey);
          } else {
            answers[storageKey] = value;
          }
        case ExistingFocusMutation(:final storageKey):
          focused = storageKey;
      }
    }
    final acknowledged = _publish(
        ExistingFormState(
            answers: answers,
            focusedStorageKey: focused,
            lifecycle: _snapshot.state.lifecycle,
            spinnerVisible: _snapshot.state.spinnerVisible),
        operationId: operationId,
        notify: !suppressEcho);

    final receipt = receiptBarrier;
    if (receipt != null) await receipt.future;
    return ExternalWriteCommitted(acknowledged);
  }

  /// Represents manual form editing or another producer in the existing app.
  void manualSet(String storageKey, Object? value, {bool clear = false}) {
    final answers = Map<String, Object?>.of(_snapshot.state.answers);
    if (clear) {
      answers.remove(storageKey);
    } else {
      answers[storageKey] = value;
    }
    _publish(ExistingFormState(
        answers: answers,
        focusedStorageKey: _snapshot.state.focusedStorageKey,
        lifecycle: _snapshot.state.lifecycle,
        spinnerVisible: _snapshot.state.spinnerVisible));
  }

  void manualFocus(String? key) => _publish(ExistingFormState(
      answers: _snapshot.state.answers,
      focusedStorageKey: key,
      lifecycle: _snapshot.state.lifecycle,
      spinnerVisible: _snapshot.state.spinnerVisible));
  void setLifecycle(FormLifecycle lifecycle) => _publish(ExistingFormState(
      answers: _snapshot.state.answers,
      focusedStorageKey: _snapshot.state.focusedStorageKey,
      lifecycle: lifecycle,
      spinnerVisible: _snapshot.state.spinnerVisible));
  void showSpinner(bool visible) => _publish(ExistingFormState(
      answers: _snapshot.state.answers,
      focusedStorageKey: _snapshot.state.focusedStorageKey,
      lifecycle: _snapshot.state.lifecycle,
      spinnerVisible: visible));
  void echoLatest() {
    if (!_disposed) _notify(_snapshot);
  }

  void emitOld(ExternalStoreSnapshot<ExistingFormState> update) {
    if (!_disposed) _notify(update);
  }

  void subscriptionError(Object error) =>
      _changes.addError(error, StackTrace.current);
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final barrier in [commitBarrier, receiptBarrier]) {
      if (barrier != null && !barrier.isCompleted) barrier.complete();
    }
    await _changes.close();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());
void main() {
  final state = FormStateSnapshot(
      formId: 'test',
      revision: 1,
      values: {'a': const IntegerValue(1)},
      activeFieldId: 'a',
      lifecycle: FormLifecycle.active);
  const action = SetValueAction(fieldId: 'a', value: IntegerValue(1));
  final applied = ActionApplied(
      action: action, previousRevision: 0, revision: 1, snapshot: state);
  final batch = BatchActionResult(
      mode: BatchApplyMode.atomic,
      baseRevision: 0,
      finalRevision: 1,
      status: BatchStatus.applied,
      results: [applied],
      snapshot: state);
  final timestamp = DateTime.utc(2026, 10, 5, 12);
  final events = <FormStateBridgeEvent>[
    BridgeInitialized(bridgeId: 'local', timestamp: timestamp, snapshot: state),
    StateChanged(
        bridgeId: 'local',
        timestamp: timestamp,
        previousRevision: 0,
        revision: 1,
        changes: [
          const FieldChange(
              fieldId: 'a',
              previousValue: null,
              value: IntegerValue(1),
              type: FieldChangeType.set)
        ],
        origin: ChangeOrigin.user,
        interactionId: 'interaction',
        operationId: 'op',
        proposalId: 'proposal'),
    ActiveFieldChanged(
        bridgeId: 'local',
        timestamp: timestamp,
        previousFieldId: null,
        fieldId: 'a',
        origin: ChangeOrigin.user,
        interactionId: 'interaction',
        operationId: 'op'),
    ActionCompleted(
        bridgeId: 'local',
        timestamp: timestamp,
        operationId: 'op',
        interactionId: 'interaction',
        proposalId: 'proposal',
        result: applied),
    BatchCompleted(
        bridgeId: 'local',
        timestamp: timestamp,
        operationId: 'op',
        interactionId: 'interaction',
        proposalId: 'proposal',
        result: batch),
    BridgeError(
        bridgeId: 'local',
        timestamp: timestamp,
        code: BridgeErrorCode.operationFailure,
        message: 'Diagnostic',
        recoverable: true,
        cause: Object()),
    BridgeDisposed(bridgeId: 'local', timestamp: timestamp),
  ];
  test('snapshot canonical golden and strict round trip', () {
    expect(FormStateSnapshotCodec.encode(state), fixture('form_state'));
    final decoded = FormStateSnapshotCodec.decode(fixture('form_state'));
    expect(decoded, state);
    expect(decoded.hashCode, state.hashCode);
    expect(
        FormStateSnapshotCodec.encode(
            FormStateSnapshotCodec.decode(fixture('form_state'))),
        fixture('form_state'));
    for (final life in FormLifecycle.values) {
      final s = FormStateSnapshot(
          formId: 'test', revision: 0, values: {}, lifecycle: life);
      expect(
          FormStateSnapshotCodec.decode(FormStateSnapshotCodec.encode(s))
              .lifecycle,
          life);
    }
  });
  test(
      'all bridge event golden encodings and round trips, runtime cause omitted',
      () {
    final golden = requireType<List<Object?>>(fixture('bridge_events'));
    for (var i = 0; i < events.length; i++) {
      final json = BridgeEventCodec.encode(events[i]);
      expect(json, golden[i]);
      final decoded = BridgeEventCodec.decode(jsonDecode(jsonEncode(json)));
      expect(decoded.runtimeType, events[i].runtimeType);
      expect(decoded, events[i]);
      expect(decoded.hashCode, events[i].hashCode);
      expect(BridgeEventCodec.encode(decoded), json);
    }
    expect(BridgeEventCodec.encode(events[5]).containsKey('cause'), isFalse);
    expect(
        (BridgeEventCodec.decode(BridgeEventCodec.encode(events[5]))
                as BridgeError)
            .cause,
        isNull);
  });
  test('action results and batch canonical goldens round trip', () {
    final results = <ActionResult>[
      applied,
      ActionNoOp(
          action: action,
          revision: 1,
          snapshot: state,
          reason: NoOpReason.valueUnchanged),
      ActionRejected(
          action: action,
          rejection: ActionRejection(
              code: ActionRejectionCode.staleRevision,
              details: {'expected': 0}),
          snapshot: state)
    ];
    expect(results.map(ActionResultCodec.encode).toList(),
        fixture('action_results'));
    for (final result in results) {
      final json = ActionResultCodec.encode(result);
      final decoded = ActionResultCodec.decode(json);
      expect(ActionResultCodec.encode(decoded), json);
      expect(decoded, result);
      expect(decoded.hashCode, result.hashCode);
    }
    expect(BatchActionResultCodec.encode(batch), fixture('batch_result'));
    expect(
        BatchActionResultCodec.encode(
            BatchActionResultCodec.decode(fixture('batch_result'))),
        fixture('batch_result'));
  });
  test('all result, context, change, batch and error enum mappings round trip',
      () {
    for (final code in ActionRejectionCode.values) {
      final r = ActionRejection(code: code);
      expect(ActionRejectionCodec.decode(ActionRejectionCodec.encode(r)).code,
          code);
    }
    for (final reason in NoOpReason.values) {
      final r = ActionNoOp(
          action: action, revision: 1, snapshot: state, reason: reason);
      expect(
          (ActionResultCodec.decode(ActionResultCodec.encode(r)) as ActionNoOp)
              .reason,
          reason);
    }
    for (final code in BatchRejectionCode.values) {
      final r = BatchRejection(code: code, message: 'm', details: {
        'example:detail': [true, null]
      });
      expect(
          BatchRejectionCodec.decode(BatchRejectionCodec.encode(r)).code, code);
    }
    for (final status in BatchStatus.values) {
      final r = BatchActionResult(
          mode: BatchApplyMode.bestEffort,
          baseRevision: 1,
          finalRevision: 1,
          status: status,
          results: [],
          snapshot: state,
          rejection: BatchRejection(code: BatchRejectionCode.conflict));
      expect(
          BatchActionResultCodec.decode(BatchActionResultCodec.encode(r))
              .status,
          status);
    }
    for (final origin in ActionOrigin.values) {
      final c = ApplyContext(
          expectedRevision: 1,
          interactionId: 'i',
          operationId: 'o',
          origin: origin);
      expect(
          ApplyContextCodec.decode(ApplyContextCodec.encode(c)).origin, origin);
    }
    for (final origin in ChangeOrigin.values) {
      final e = StateChanged(
          bridgeId: 'b',
          timestamp: timestamp,
          previousRevision: 0,
          revision: 1,
          changes: [],
          origin: origin);
      expect(
          (BridgeEventCodec.decode(BridgeEventCodec.encode(e)) as StateChanged)
              .origin,
          origin);
    }
    for (final type in FieldChangeType.values) {
      final c = FieldChange(
          fieldId: 'a',
          previousValue: const IntegerValue(1),
          value: null,
          type: type);
      expect(FieldChangeCodec.decode(FieldChangeCodec.encode(c)).type, type);
    }
    for (final code in BridgeErrorCode.values) {
      final e = BridgeError(
          bridgeId: 'b',
          timestamp: timestamp,
          code: code,
          message: 'message',
          recoverable: false);
      expect(
          (BridgeEventCodec.decode(BridgeEventCodec.encode(e)) as BridgeError)
              .code,
          code);
    }
  });
  test('capabilities codec preserves all flags and rejects malformed types',
      () {
    for (final flag in [true, false]) {
      final c = FormStateBridgeCapabilities(
          writable: flag,
          supportsBatch: flag,
          supportsAtomicBatch: flag,
          supportsUndo: flag,
          supportsRedo: flag,
          supportsExternalChanges: flag,
          supportsActiveField: flag,
          supportsNavigation: flag);
      final json = FormStateBridgeCapabilitiesCodec.encode(c);
      expect(
          FormStateBridgeCapabilitiesCodec.encode(
              FormStateBridgeCapabilitiesCodec.decode(json)),
          json);
      expect(
          () => FormStateBridgeCapabilitiesCodec.decode(
              {...json, 'writable': 'true'}),
          throwsFormatException);
    }
  });
  test('snapshot, results, events and metadata collections defensively copied',
      () {
    final values = <String, FormValue>{'a': const IntegerValue(1)};
    final s = FormStateSnapshot(
        formId: 'f',
        revision: 0,
        values: values,
        lifecycle: FormLifecycle.active);
    values.clear();
    expect(s.values.length, 1);
    expect(s.values.clear, throwsUnsupportedError);
    final changes = <FieldChange>[
      const FieldChange(
          fieldId: 'a',
          previousValue: null,
          value: IntegerValue(1),
          type: FieldChangeType.set)
    ];
    final e = StateChanged(
        bridgeId: 'b',
        timestamp: timestamp,
        previousRevision: 0,
        revision: 1,
        changes: changes,
        origin: ChangeOrigin.system);
    changes.clear();
    expect(e.changes.length, 1);
    expect(e.changes.clear, throwsUnsupportedError);
    final detail = <String, Object?>{
      'nested': <Object?>[1]
    };
    final rejection =
        ActionRejection(code: ActionRejectionCode.conflict, details: detail);
    (detail['nested'] as List<Object?>).clear();
    expect(rejection.details['nested'], [1]);
    expect(() => (rejection.details['nested'] as List<Object?>).clear(),
        throwsUnsupportedError);
    expect(
        () => BatchRejection(
            code: BatchRejectionCode.conflict, details: {'bad': Object()}),
        throwsFormatException);
    final results = <ActionResult>[applied];
    final b = BatchActionResult(
        mode: BatchApplyMode.atomic,
        baseRevision: 0,
        finalRevision: 1,
        status: BatchStatus.applied,
        results: results,
        snapshot: state);
    results.clear();
    expect(b.results.length, 1);
    expect(b.results.clear, throwsUnsupportedError);
  });
  test(
      'strict snapshot rejects bad version/revision/lifecycle/value and optional null',
      () {
    for (final change in [
      {'specVersion': '2.0'},
      {'revision': -1},
      {'revision': '1'},
      {'revision': 1.0},
      {'lifecycle': 'unknown'},
      {'activeFieldId': null},
      {
        'values': {
          'a': {'type': 'integer', 'value': '1'}
        }
      },
    ]) {
      expect(
          () => FormStateSnapshotCodec.decode(
              {...FormStateSnapshotCodec.encode(state), ...change}),
          throwsFormatException);
    }
    final missing = FormStateSnapshotCodec.encode(state)..remove('specVersion');
    expect(() => FormStateSnapshotCodec.decode(missing), throwsFormatException);
    expect(
        FormStateSnapshotCodec.decode(
            {...FormStateSnapshotCodec.encode(state), 'future': true}).revision,
        1);
  });
  test('malformed events, timestamps, nested results and batches rejected', () {
    for (final bad in [
      null,
      <Object?>[],
      <String, Object?>{},
      {'type': 'future'}
    ]) {
      expect(() => BridgeEventCodec.decode(bad), throwsFormatException);
      expect(() => ActionResultCodec.decode(bad), throwsFormatException);
    }
    final json = BridgeEventCodec.encode(events.first);
    for (final change in [
      {'specVersion': '2.0'},
      {'timestamp': '2026-02-30T12:00:00.000Z'},
      {'timestamp': 1},
      {'timestamp': '2026-10-05T12:00:00'},
      {'snapshot': null},
      {'bridgeId': false},
    ]) {
      expect(() => BridgeEventCodec.decode({...json, ...change}),
          throwsFormatException);
    }
    expect(
        () => BatchActionResultCodec.decode(
            {...BatchActionResultCodec.encode(batch), 'mode': 'unknown'}),
        throwsFormatException);
    expect(
        () => BatchActionResultCodec.decode({
              ...BatchActionResultCodec.encode(batch),
              'results': [true]
            }),
        throwsFormatException);
    expect(
        () => ActionRejectionCodec.decode({
              'code': 'conflict',
              'details': {'bad': double.infinity}
            }),
        throwsFormatException);
  });
}

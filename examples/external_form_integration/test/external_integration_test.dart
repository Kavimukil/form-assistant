import 'dart:async';
import 'dart:math';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_external_example/existing_form_store.dart';
import 'package:form_assistant_external_example/project_example_form_adapter.dart';
import 'package:form_assistant_external_example/project_example_external_state_bridge.dart';
import 'package:test/test.dart';

ExistingFormSchema exampleSchema() =>
    ExistingFormSchema(canonicalId: 'profile', fields: [
      ExistingField(
          storageKey: 'AGE',
          canonicalId: 'age',
          label: 'Age',
          type: ExistingFieldType.integer,
          min: 0,
          max: 120),
      ExistingField(
          storageKey: 'SCORE',
          canonicalId: 'score',
          label: 'Score',
          type: ExistingFieldType.integer),
      ExistingField(
          storageKey: 'CONSENT_YN',
          canonicalId: 'consent',
          label: 'Consent',
          type: ExistingFieldType.yesNo),
      ExistingField(
          storageKey: 'COLOR_KEY',
          canonicalId: 'color',
          label: 'Color',
          type: ExistingFieldType.select,
          options: [
            const ExistingOption(key: 'R', canonicalId: 'red', label: 'Red'),
            const ExistingOption(key: 'B', canonicalId: 'blue', label: 'Blue')
          ]),
      ExistingField(
          storageKey: 'TAGS_KEYS',
          canonicalId: 'tags',
          label: 'Tags',
          type: ExistingFieldType.multiSelect,
          options: [
            const ExistingOption(key: 'R', canonicalId: 'red', label: 'Red'),
            const ExistingOption(key: 'B', canonicalId: 'blue', label: 'Blue')
          ]),
      ExistingField(
          storageKey: 'NAME',
          canonicalId: 'name',
          label: 'Name',
          type: ExistingFieldType.text),
      ExistingField(
          storageKey: 'DECIMAL',
          canonicalId: 'decimal',
          label: 'Decimal',
          type: ExistingFieldType.decimal),
      ExistingField(
          storageKey: 'DATE',
          canonicalId: 'date',
          label: 'Date',
          type: ExistingFieldType.date),
    ]);

final class Harness {
  final ExistingFormSchema schema;
  final FormIR form;
  final ExistingFormStore store;
  final FormStateBridge bridge;
  final List<FormStateBridgeEvent> events = [];
  int _operation = 0;
  Harness(this.schema, this.form, this.store, this.bridge) {
    bridge.events.listen(events.add);
  }
  ApplyContext context(
          {int? expected, ActionOrigin origin = ActionOrigin.intelligence}) =>
      ApplyContext(
          expectedRevision: expected ?? bridge.snapshot.revision,
          interactionId: 'interaction',
          operationId: 'op-${_operation++}',
          proposalId: 'proposal',
          origin: origin);
  Future<void> close() async {
    await bridge.dispose();
    await store.dispose();
  }
}

Future<Harness> harness(
    {ExistingFormState? initial,
    Duration timeout = const Duration(seconds: 1),
    bool atomic = true,
    FormStateBridgeCapabilities? capabilities,
    ExistingMutation Function(FormAction, FormStateSnapshot)?
        mutationMapper}) async {
  final schema = exampleSchema();
  final form = await ProjectExampleFormAdapter().compile(schema);
  final store =
      ExistingFormStore(initialState: initial, supportsAtomicBatch: atomic);
  final FormStateBridge bridge = mutationMapper == null
      ? ProjectExampleExternalStateBridge(
          form: form,
          schema: schema,
          store: store,
          acknowledgementTimeout: timeout,
          capabilities: capabilities)
      : ExternalStateBridge<ExistingFormState, ExistingMutation>(
          form: form,
          source: store,
          mapSnapshot: (state, revision) =>
              mapExistingSnapshot(schema, state, revision),
          mapMutation: mutationMapper,
          acknowledgementTimeout: timeout,
          capabilities: capabilities);
  final h = Harness(schema, form, store, bridge);
  addTearDown(h.close);
  return h;
}

SetValueAction age(int value) =>
    SetValueAction(fieldId: 'age', value: IntegerValue(value));
Future<void> pump() => Future<void>.delayed(Duration.zero);
void rejection(ActionResult result, ActionRejectionCode code) {
  expect(result, isA<ActionRejected>());
  expect((result as ActionRejected).rejection.code, code);
}

void main() {
  test(
      'adapter compiles canonical schema without source storage keys or encodings',
      () async {
    final schema = exampleSchema();
    final ir = await ProjectExampleFormAdapter().compile(schema);
    expect(ir.id, 'profile');
    expect(ir.specVersion, '1.0');
    expect(ir.fields.map((f) => f.id), [
      'age',
      'score',
      'consent',
      'color',
      'tags',
      'name',
      'decimal',
      'date'
    ]);
    expect(ir.fields[2].value, const BooleanDefinition());
    expect(ir.fields[3].options!.map((o) => o.id), ['red', 'blue']);
    expect(ir.fields[3].options!.map((o) => o.label), ['Red', 'Blue']);
    expect(ir.fields.first.constraints!.max, 120);
    expect(ir.toJson().toString(), isNot(contains('CONSENT_YN')));
    expect(ir.toJson().toString(), isNot(contains('COLOR_KEY')));
  });
  test(
      'initial snapshot maps every type, canonical focus, absent answers and immutable source state',
      () async {
    final h = await harness(
        initial: ExistingFormState(answers: {
      'AGE': 21,
      'CONSENT_YN': 'Y',
      'COLOR_KEY': 'R',
      'TAGS_KEYS': ['R', 'B', 'R'],
      'NAME': '  Mixed  ',
      'DECIMAL': 2.5,
      'DATE': '2024-02-29'
    }, focusedStorageKey: 'AGE'));
    final state = h.bridge.snapshot;
    expect(state.revision, 0);
    expect(state.activeFieldId, 'age');
    expect(state.values, {
      'age': const IntegerValue(21),
      'consent': const BooleanValue(true),
      'color': ChoiceValue('red'),
      'tags': MultiChoiceValue(['blue', 'red']),
      'name': const StringValue('  Mixed  '),
      'decimal': NumberValue(2.5),
      'date': DateValue('2024-02-29')
    });
    expect(state.values.containsKey('score'), isFalse);
    expect(state.values.clear, throwsUnsupportedError);
    expect(
        () => h.store.snapshot.state.answers.clear(), throwsUnsupportedError);
    expect(
        () => (h.store.snapshot.state.answers['TAGS_KEYS'] as List<Object?>)
            .clear(),
        throwsUnsupportedError);
    expect(h.store.hasSubscribers, isTrue);
  });
  test(
      'canonical writes map Y/N and canonical option IDs and each echo counts exactly once',
      () async {
    final h = await harness();
    final actions = <FormAction>[
      const SetValueAction(fieldId: 'consent', value: BooleanValue(true)),
      const SetValueAction(fieldId: 'consent', value: BooleanValue(false)),
      SetValueAction(fieldId: 'color', value: ChoiceValue('blue')),
      SetValueAction(fieldId: 'tags', value: MultiChoiceValue(['red', 'blue'])),
      const SetValueAction(fieldId: 'name', value: StringValue('User')),
      SetValueAction(fieldId: 'decimal', value: NumberValue(3.5)),
      SetValueAction(fieldId: 'date', value: DateValue('2024-02-29')),
    ];
    for (final action in actions) {
      final context = h.context();
      final before = h.bridge.snapshot.revision;
      final result = await h.bridge.apply(action, context: context);
      expect(result, isA<ActionApplied>());
      expect(h.bridge.snapshot.revision, before + 1);
      expect((result as ActionApplied).revision, before + 1);
      h.store.echoLatest();
      await pump();
      expect(h.bridge.snapshot.revision, before + 1);
      final event = h.events.whereType<StateChanged>().last;
      expect(event.origin, ChangeOrigin.intelligence);
      expect(event.operationId, context.operationId);
      expect(event.interactionId, context.interactionId);
      expect(event.proposalId, context.proposalId);
    }
    expect(h.store.snapshot.state.answers['CONSENT_YN'], 'N');
    expect(h.store.snapshot.state.answers['COLOR_KEY'], 'B');
    expect(h.store.snapshot.state.answers['TAGS_KEYS'], ['B', 'R']);
    expect(h.events.whereType<StateChanged>().length, actions.length);
    final clear = await h.bridge
        .apply(const ClearValueAction(fieldId: 'color'), context: h.context());
    expect(clear, isA<ActionApplied>());
    expect(h.store.snapshot.state.answers.containsKey('COLOR_KEY'), isFalse);
  });
  test(
      'manual source changes are external and authoritative even when outside assistant constraints',
      () async {
    final h = await harness();
    h.store.manualSet('CONSENT_YN', 'N');
    h.store.manualSet('AGE', 121);
    expect(h.bridge.snapshot.values['consent'], const BooleanValue(false));
    expect(h.bridge.snapshot.values['age'], const IntegerValue(121));
    expect(h.bridge.snapshot.revision, 2);
    for (final event in h.events.whereType<StateChanged>()) {
      expect(event.origin, ChangeOrigin.external);
      expect(event.operationId, isNull);
      expect(event.proposalId, isNull);
    }
    rejection(await h.bridge.apply(age(122), context: h.context()),
        ActionRejectionCode.validationFailed);
    h.store.manualSet('AGE', null, clear: true);
    expect(h.bridge.snapshot.values.containsKey('age'), isFalse);
    expect(h.bridge.snapshot.revision, 3);
  });
  test(
      'delayed dispatch cannot return Applied or publish provisional values before actual commit',
      () async {
    final h = await harness();
    h.store.commitBarrier = Completer();
    var completed = false;
    final pending = h.bridge.apply(age(42), context: h.context()).then((r) {
      completed = true;
      return r;
    });
    await pump();
    expect(completed, isFalse);
    expect(h.store.writeRequests, 1);
    expect(h.store.snapshot.state.answers, isEmpty);
    expect(h.bridge.snapshot.values, isEmpty);
    expect(h.bridge.snapshot.revision, 0);
    h.store.commitBarrier!.complete();
    final result = await pending;
    expect(result, isA<ActionApplied>());
    expect(h.store.snapshot.state.answers['AGE'], 42);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(42));
    expect(h.events.whereType<StateChanged>().length, 1);
  });
  test(
      'authoritative notification acknowledges even if dispatch receipt is delayed',
      () async {
    final h = await harness();
    h.store.receiptBarrier = Completer();
    final result = await h.bridge.apply(age(42), context: h.context());
    expect(result, isA<ActionApplied>());
    expect(h.store.receiptBarrier!.isCompleted, isFalse);
    expect(h.bridge.snapshot.revision, 1);
    h.store.receiptBarrier!.complete();
    await pump();
    expect(h.bridge.snapshot.revision, 1);
    expect(h.events.whereType<StateChanged>().length, 1);
  });
  test(
      'authoritative receipt without echo reconciles once, and a later echo is ignored',
      () async {
    final h = await harness();
    h.store.suppressEcho = true;
    h.store.receiptBarrier = Completer();
    var completed = false;
    final pending = h.bridge.apply(age(42), context: h.context()).then((r) {
      completed = true;
      return r;
    });
    await pump();
    expect(h.store.snapshot.state.answers['AGE'], 42);
    expect(completed, isFalse);
    expect(h.bridge.snapshot.values, isEmpty);
    h.store.receiptBarrier!.complete();
    expect(await pending, isA<ActionApplied>());
    expect(h.bridge.snapshot.revision, 1);
    h.store.echoLatest();
    await pump();
    expect(h.bridge.snapshot.revision, 1);
    expect(h.events.whereType<StateChanged>().single.origin,
        ChangeOrigin.intelligence);
  });
  test(
      'external edit while write is delayed wins; source CAS rejects stale write at commit',
      () async {
    final h = await harness();
    h.store.commitBarrier = Completer();
    final pending = h.bridge.apply(age(42), context: h.context());
    await pump();
    h.store.manualSet('AGE', 30);
    h.store.commitBarrier!.complete();
    rejection(await pending, ActionRejectionCode.staleRevision);
    expect(h.store.snapshot.state.answers['AGE'], 30);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(30));
    expect(h.bridge.snapshot.revision, 1);
    expect(h.events.whereType<StateChanged>().single.origin,
        ChangeOrigin.external);
  });
  test('external overwrite after own commit wins over an older receipt',
      () async {
    final h = await harness();
    h.store.suppressEcho = true;
    h.store.receiptBarrier = Completer();
    final pending = h.bridge.apply(age(42), context: h.context());
    await pump();
    h.store.manualSet('AGE', 30);
    final version = h.bridge.snapshot.revision;
    h.store.receiptBarrier!.complete();
    rejection(await pending, ActionRejectionCode.conflict);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(30));
    expect(h.store.snapshot.state.answers['AGE'], 30);
    expect(h.bridge.snapshot.revision, version);
  });
  test(
      'reentrant external overwrite preserves commit ordering and rejects obsolete acknowledgement',
      () async {
    final h = await harness();
    h.bridge.events.listen((event) {
      if (event is StateChanged && event.origin == ChangeOrigin.intelligence) {
        h.store.manualSet('AGE', 30);
      }
    });
    rejection(await h.bridge.apply(age(42), context: h.context()),
        ActionRejectionCode.conflict);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(30));
    expect(h.events.whereType<StateChanged>().map((e) => e.origin),
        [ChangeOrigin.intelligence, ChangeOrigin.external]);
    expect(h.events.whereType<StateChanged>().map((e) => e.revision), [1, 2]);
  });
  test(
      'ack timeout reports a conflict, and late commit becomes external without double counting',
      () async {
    final h = await harness(timeout: const Duration(milliseconds: 20));
    h.store.commitBarrier = Completer();
    final result = await h.bridge.apply(age(42), context: h.context());
    rejection(result, ActionRejectionCode.conflict);
    expect((result as ActionRejected).rejection.details['code'],
        'bridge.acknowledgement_timeout');
    expect(h.bridge.snapshot.revision, 0);
    expect(h.events.whereType<BridgeError>().single.code,
        BridgeErrorCode.operationFailure);
    h.store.commitBarrier!.complete();
    await pump();
    expect(h.bridge.snapshot.values['age'], const IntegerValue(42));
    expect(h.bridge.snapshot.revision, 1);
    expect(h.events.whereType<StateChanged>().single.origin,
        ChangeOrigin.external);
    h.store.echoLatest();
    expect(h.bridge.snapshot.revision, 1);
  });
  test('timed-out delayed request cannot overwrite a newer assistant commit',
      () async {
    final h = await harness(timeout: const Duration(milliseconds: 20));
    final barrier = Completer<void>();
    h.store.commitBarrier = barrier;
    rejection(await h.bridge.apply(age(42), context: h.context()),
        ActionRejectionCode.conflict);
    h.store.commitBarrier = null;
    expect(await h.bridge.apply(age(30), context: h.context()),
        isA<ActionApplied>());
    barrier.complete();
    await pump();
    expect(h.bridge.snapshot.values['age'], const IntegerValue(30));
    expect(h.store.snapshot.state.answers['AGE'], 30);
    expect(h.bridge.snapshot.revision, 1);
  });
  test(
      'no-ops, malformed actions and store failures never mutate or increment revision',
      () async {
    final h = await harness(initial: ExistingFormState(answers: {'AGE': 21}));
    expect(
        await h.bridge.apply(age(21), context: h.context()), isA<ActionNoOp>());
    expect(
        await h.bridge.apply(const ClearValueAction(fieldId: 'color'),
            context: h.context()),
        isA<ActionNoOp>());
    rejection(
        await h.bridge.apply(
            const SetValueAction(fieldId: 'age', value: StringValue('22')),
            context: h.context()),
        ActionRejectionCode.invalidValue);
    rejection(await h.bridge.apply(age(-1), context: h.context()),
        ActionRejectionCode.validationFailed);
    rejection(
        await h.bridge.apply(const ClearValueAction(fieldId: 'missing'),
            context: h.context()),
        ActionRejectionCode.unknownField);
    rejection(
        await h.bridge.apply(
            RequestClarificationAction(reason: ClarificationReason.ambiguous),
            context: h.context()),
        ActionRejectionCode.unsupportedAction);
    expect(h.store.writeRequests, 0);
    h.store.nextWriteFailure = StateError('Store unavailable');
    rejection(await h.bridge.apply(age(22), context: h.context()),
        ActionRejectionCode.internalError);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(21));
    expect(h.bridge.snapshot.revision, 0);
    expect(h.events.whereType<StateChanged>(), isEmpty);
    expect(h.events.whereType<BridgeError>().last.code,
        BridgeErrorCode.externalStoreFailure);
    expect(await h.bridge.apply(age(23), context: h.context()),
        isA<ActionApplied>());
  });
  test(
      'projection failure preserves last valid snapshot, blocks writes and recovers on valid source change',
      () async {
    final h = await harness();
    h.store.manualSet('CONSENT_YN', 'maybe');
    expect(h.bridge.snapshot.values, isEmpty);
    expect(h.events.whereType<BridgeError>().last.code,
        BridgeErrorCode.mappingFailure);
    rejection(await h.bridge.apply(age(22), context: h.context()),
        ActionRejectionCode.capabilityUnavailable);
    expect(h.store.writeRequests, 0);
    h.store.manualSet('CONSENT_YN', 'Y');
    expect(h.bridge.snapshot.values['consent'], const BooleanValue(true));
    expect(h.bridge.snapshot.revision, 1);
    expect(await h.bridge.apply(age(22), context: h.context()),
        isA<ActionApplied>());
  });
  test('mutation mapper errors are reported before touching the store',
      () async {
    final h = await harness(
        mutationMapper: (action, planned) =>
            throw const FormatException('No source mapping'));
    rejection(await h.bridge.apply(age(22), context: h.context()),
        ActionRejectionCode.internalError);
    expect(h.store.writeRequests, 0);
    expect(h.bridge.snapshot.revision, 0);
    expect(h.events.whereType<BridgeError>().last.code,
        BridgeErrorCode.mappingFailure);
  });
  test(
      'navigation and source presentation changes do not increment semantic revision; lifecycle does',
      () async {
    final h = await harness();
    expect(
        await h.bridge.apply(
            const NavigateAction(
                target: FieldNavigationTarget(fieldId: 'consent')),
            context: h.context()),
        isA<ActionApplied>());
    expect(h.store.snapshot.state.focusedStorageKey, 'CONSENT_YN');
    expect(h.bridge.snapshot.activeFieldId, 'consent');
    expect(h.bridge.snapshot.revision, 0);
    h.store.showSpinner(true);
    expect(h.bridge.snapshot.revision, 0);
    expect(h.events.whereType<StateChanged>(), isEmpty);
    h.store.manualFocus('AGE');
    expect(h.bridge.snapshot.activeFieldId, 'age');
    expect(h.bridge.snapshot.revision, 0);
    expect(h.events.whereType<ActiveFieldChanged>().last.origin,
        ChangeOrigin.external);
    h.store.setLifecycle(FormLifecycle.readOnly);
    expect(h.bridge.snapshot.lifecycle, FormLifecycle.readOnly);
    expect(h.bridge.snapshot.revision, 1);
    rejection(await h.bridge.apply(age(22), context: h.context()),
        ActionRejectionCode.readOnly);
    expect(h.events.whereType<StateChanged>().last.changes, isEmpty);
  });
  test(
      'stale proposals, concurrent writes and multiple bridges respect authoritative CAS',
      () async {
    final h = await harness();
    h.store.commitBarrier = Completer();
    final other = ProjectExampleExternalStateBridge(
        form: h.form, schema: h.schema, store: h.store);
    addTearDown(other.dispose);
    final first = h.bridge.apply(age(22), context: h.context(expected: 0));
    final second = other.apply(age(30),
        context: const ApplyContext(
            expectedRevision: 0,
            interactionId: 'other',
            operationId: 'other-op',
            origin: ActionOrigin.user));
    await pump();
    h.store.commitBarrier!.complete();
    expect(await first, isA<ActionApplied>());
    rejection(await second, ActionRejectionCode.staleRevision);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(22));
    expect(other.snapshot.values, h.bridge.snapshot.values);
    rejection(await h.bridge.apply(age(30), context: h.context(expected: 0)),
        ActionRejectionCode.staleRevision);
  });
  test(
      'atomic batch commits once, validates all first, and rollback never reaches source',
      () async {
    final h = await harness();
    final rejected = await h.bridge.applyBatch(
        [age(22), const ClearValueAction(fieldId: 'missing')],
        context: h.context(), mode: BatchApplyMode.atomic);
    expect(rejected.status, BatchStatus.rejected);
    expect(h.store.writeRequests, 0);
    expect(h.bridge.snapshot.revision, 0);
    rejection(rejected.results.first, ActionRejectionCode.atomicBatchAborted);
    final result = await h.bridge.applyBatch([
      age(22),
      const SetValueAction(fieldId: 'consent', value: BooleanValue(true))
    ], context: h.context(), mode: BatchApplyMode.atomic);
    expect(result.status, BatchStatus.applied);
    expect(result.finalRevision, 1);
    expect(h.store.writeRequests, 1);
    expect(h.events.whereType<StateChanged>().single.changes.length, 2);
    for (final applied in result.results.cast<ActionApplied>()) {
      expect(applied.previousRevision, 0);
      expect(applied.revision, 1);
      expect(applied.snapshot, result.snapshot);
    }
    final noop = await h.bridge.applyBatch([age(23), age(22)],
        context: h.context(), mode: BatchApplyMode.atomic);
    expect(noop.status, BatchStatus.noOp);
    expect(noop.finalRevision, 1);
    expect(h.store.writeRequests, 1);
  });
  test(
      'best effort partially succeeds, serializes logical batch and defensively copies actions',
      () async {
    final h = await harness();
    final actions = <FormAction>[
      age(22),
      const ClearValueAction(fieldId: 'missing'),
      const SetValueAction(fieldId: 'score', value: IntegerValue(3))
    ];
    final pending = h.bridge.applyBatch(actions, context: h.context());
    actions.clear();
    final competing = h.bridge.apply(age(30), context: h.context(expected: 0));
    final result = await pending;
    expect(result.status, BatchStatus.partiallyApplied);
    expect(result.finalRevision, 2);
    rejection(result.results[1], ActionRejectionCode.unknownField);
    rejection(await competing, ActionRejectionCode.staleRevision);
    expect(result.results.clear, throwsUnsupportedError);
    expect(h.events.whereType<BatchCompleted>().length, 1);
  });
  test(
      'external change during a batch stops remaining writes rather than reusing stale context',
      () async {
    final h = await harness();
    h.bridge.events.listen((event) {
      if (event is ActionCompleted && event.result.action == age(22)) {
        h.store.manualSet('SCORE', 9);
      }
    });
    final result = await h.bridge.applyBatch([
      age(22),
      const SetValueAction(fieldId: 'score', value: IntegerValue(3))
    ], context: h.context());
    expect(result.status, BatchStatus.partiallyApplied);
    rejection(result.results.last, ActionRejectionCode.staleRevision);
    expect(h.store.snapshot.state.answers['SCORE'], 9);
    expect(h.store.writeRequests, 1);
  });
  test('unsupported atomic batches and history are rejected without emulation',
      () async {
    final h = await harness(atomic: false);
    expect(h.bridge.capabilities.supportsAtomicBatch, isFalse);
    final result = await h.bridge.applyBatch([age(22)],
        context: h.context(), mode: BatchApplyMode.atomic);
    expect(result.rejection!.code, BatchRejectionCode.atomicBatchUnsupported);
    expect(result.mode, BatchApplyMode.atomic);
    expect(h.store.writeRequests, 0);
    expect(h.bridge.capabilities.supportsUndo, isFalse);
    expect(h.bridge.capabilities.supportsRedo, isFalse);
    rejection(await h.bridge.undo(context: h.context()),
        ActionRejectionCode.capabilityUnavailable);
    rejection(await h.bridge.redo(context: h.context()),
        ActionRejectionCode.capabilityUnavailable);
  });
  test('ordered snapshot publication, completion trace and out-of-order echoes',
      () async {
    final h = await harness();
    final old = h.store.snapshot;
    final context = h.context();
    h.bridge.events.listen((event) {
      if (event is StateChanged) {
        expect(h.bridge.snapshot.revision, event.revision);
        for (final change in event.changes) {
          expect(h.bridge.snapshot.values[change.fieldId], change.value);
        }
      }
    });
    await h.bridge.apply(age(22), context: context);
    expect(h.events.map((e) => e.runtimeType),
        [BridgeInitialized, StateChanged, ActionCompleted]);
    final completed = h.events.whereType<ActionCompleted>().single;
    expect(completed.operationId, context.operationId);
    expect(completed.interactionId, context.interactionId);
    expect(completed.proposalId, context.proposalId);
    h.store.emitOld(old);
    h.store.echoLatest();
    expect(h.bridge.snapshot.revision, 1);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(22));
  });
  test(
      'dispose unsubscribes, cancels pending waits, and leaves manual form usable',
      () async {
    final h = await harness();
    final barrier = Completer<void>();
    h.store.commitBarrier = barrier;
    final pending = h.bridge.apply(age(22), context: h.context());
    await pump();
    final disposal = h.bridge.dispose();
    expect(identical(disposal, h.bridge.dispose()), isTrue);
    await disposal;
    rejection(await pending, ActionRejectionCode.disposed);
    expect(h.store.hasSubscribers, isFalse);
    expect(h.events.last, isA<BridgeDisposed>());
    final count = h.events.length;
    h.store.manualSet('AGE', 30);
    barrier.complete();
    await pump();
    expect(h.store.snapshot.state.answers['AGE'], 30);
    expect(h.events.length, count);
    rejection(await h.bridge.apply(age(40), context: h.context()),
        ActionRejectionCode.disposed);
    expect(
        (await h.bridge.applyBatch([], context: h.context())).rejection!.code,
        BatchRejectionCode.disposed);
  });
  test('subscription failure blocks unsafe writes', () async {
    final h = await harness();
    h.store.subscriptionError(StateError('Subscription failed'));
    await pump();
    rejection(await h.bridge.apply(age(22), context: h.context()),
        ActionRejectionCode.capabilityUnavailable);
    expect(h.store.writeRequests, 0);
    expect(h.events.whereType<BridgeError>().last.code,
        BridgeErrorCode.externalStoreFailure);
  });

  test(
      'presentation-only source race still rejects at the authoritative CAS boundary',
      () async {
    final h = await harness();
    h.store.commitBarrier = Completer();
    final pending = h.bridge.apply(age(22), context: h.context());
    await pump();
    h.store.showSpinner(true);
    expect(h.bridge.snapshot.revision, 0);
    h.store.commitBarrier!.complete();
    rejection(await pending, ActionRejectionCode.staleRevision);
    expect(h.bridge.snapshot.values, isEmpty);
    expect(h.store.snapshot.state.answers, isEmpty);
    expect(h.events.whereType<StateChanged>(), isEmpty);
  });
  test('lost acknowledgement cannot turn a retry into a stale force-write',
      () async {
    final h = await harness(timeout: const Duration(milliseconds: 20));
    h.store.suppressEcho = true;
    h.store.receiptBarrier = Completer();
    rejection(await h.bridge.apply(age(42), context: h.context()),
        ActionRejectionCode.conflict);
    expect(h.store.snapshot.state.answers['AGE'], 42);
    expect(h.bridge.snapshot.revision, 0);
    rejection(await h.bridge.apply(age(30), context: h.context()),
        ActionRejectionCode.staleRevision);
    expect(h.bridge.snapshot.values['age'], const IntegerValue(42));
    expect(h.events.whereType<StateChanged>().single.origin,
        ChangeOrigin.external);
    h.store.receiptBarrier!.complete();
    await pump();
    expect(h.bridge.snapshot.revision, 1);
    expect(h.store.snapshot.state.answers['AGE'], 42);
  });
  test(
      'read-only/navigation/batch capabilities and source shutdown are enforced',
      () async {
    final caps = const FormStateBridgeCapabilities(
        writable: false,
        supportsBatch: false,
        supportsAtomicBatch: false,
        supportsUndo: false,
        supportsRedo: false,
        supportsExternalChanges: true,
        supportsActiveField: false,
        supportsNavigation: false);
    final h = await harness(capabilities: caps);
    rejection(await h.bridge.apply(age(22), context: h.context()),
        ActionRejectionCode.readOnly);
    rejection(
        await h.bridge.apply(
            const NavigateAction(target: NextNavigationTarget()),
            context: h.context()),
        ActionRejectionCode.capabilityUnavailable);
    expect(
        (await h.bridge.applyBatch([age(22)], context: h.context()))
            .rejection!
            .code,
        BatchRejectionCode.batchUnsupported);
    expect(h.store.writeRequests, 0);
    await h.store.dispose();
    rejection(await h.bridge.apply(age(22), context: h.context()),
        ActionRejectionCode.capabilityUnavailable);
    expect(h.events.whereType<BridgeError>().last.code,
        BridgeErrorCode.externalStoreFailure);
  });
  test('source schema and initial source encodings are strict', () async {
    final schema = exampleSchema();
    final form = await ProjectExampleFormAdapter().compile(schema);
    for (final answers in [
      <String, Object?>{'CONSENT_YN': true},
      <String, Object?>{'COLOR_KEY': 'Red'},
      <String, Object?>{'AGE': '21'}
    ]) {
      final store =
          ExistingFormStore(initialState: ExistingFormState(answers: answers));
      addTearDown(store.dispose);
      expect(
          () => ProjectExampleExternalStateBridge(
              form: form, schema: schema, store: store),
          throwsFormatException);
      expect(store.hasSubscribers, isFalse);
    }
    final duplicate = ExistingFormSchema(
        canonicalId: 'profile',
        fields: [schema.fields.first, schema.fields.first]);
    await expectLater(
        ProjectExampleFormAdapter().compile(duplicate), throwsArgumentError);
  });
  test(
      'source error emitted by an initialization observer is queued without stream reentrancy',
      () async {
    final h = await harness();
    h.bridge.events.listen((event) {
      if (event is BridgeInitialized) {
        h.store
            .subscriptionError(StateError('Observer reported source failure'));
      }
    });
    rejection(await h.bridge.apply(age(22), context: h.context()),
        ActionRejectionCode.capabilityUnavailable);
    expect(h.events.map((e) => e.runtimeType),
        [BridgeInitialized, BridgeError, ActionCompleted]);
  });
  test(
      '1000 mixed assistant/external operations preserve revision, event and store invariants',
      () async {
    final h = await harness();
    final random = Random(2026);
    var expected = <String, FormValue>{};
    var revision = 0;
    var replay = <String, FormValue>{};
    var eventRevision = 0;
    h.bridge.events.listen((event) {
      if (event is StateChanged) {
        expect(event.previousRevision, eventRevision);
        expect(event.revision, eventRevision + 1);
        eventRevision = event.revision;
        for (final change in event.changes) {
          expect(replay[change.fieldId], change.previousValue);
          if (change.value == null) {
            replay.remove(change.fieldId);
          } else {
            replay[change.fieldId] = change.value!;
          }
        }
        expect(replay, h.bridge.snapshot.values);
        expect(h.bridge.snapshot.revision, eventRevision);
      }
    });
    Map<String, FormValue> project(
        Map<String, FormValue> values, FormAction action) {
      final next = Map<String, FormValue>.of(values);
      if (action is SetValueAction) {
        next[action.fieldId] = action.value;
      } else if (action is ClearValueAction) {
        next.remove(action.fieldId);
      }
      return next;
    }

    void commit(Map<String, FormValue> next) {
      if (!jsonEquals(expected, next)) {
        expected = next;
        revision++;
      }
    }

    for (var i = 0; i < 1000; i++) {
      final id = random.nextBool() ? 'age' : 'score';
      final key = id == 'age' ? 'AGE' : 'SCORE';
      final value = random.nextInt(100);
      switch (random.nextInt(7)) {
        case 0:
          commit(project(expected,
              SetValueAction(fieldId: id, value: IntegerValue(value))));
          await h.bridge.apply(
              SetValueAction(fieldId: id, value: IntegerValue(value)),
              context: h.context());
        case 1:
          commit(project(expected,
              SetValueAction(fieldId: id, value: IntegerValue(value))));
          h.store.manualSet(key, value);
        case 2:
          commit(project(expected, ClearValueAction(fieldId: id)));
          h.store.manualSet(key, null, clear: true);
        case 3:
          commit(project(expected, ClearValueAction(fieldId: id)));
          await h.bridge
              .apply(ClearValueAction(fieldId: id), context: h.context());
        case 4:
          final actions = [
            age(value),
            SetValueAction(fieldId: 'score', value: IntegerValue(value))
          ];
          var next = Map<String, FormValue>.of(expected);
          for (final action in actions) {
            next = project(next, action);
          }
          commit(next);
          await h.bridge.applyBatch(actions,
              context: h.context(), mode: BatchApplyMode.atomic);
        case 5:
          final stale = await h.bridge.apply(age(value),
              context: h.context(expected: h.bridge.snapshot.revision - 1));
          rejection(stale, ActionRejectionCode.staleRevision);
        case 6:
          h.store.showSpinner(random.nextBool());
      }
      h.store.echoLatest();
      await pump();
      expect(h.bridge.snapshot.values, expected, reason: 'operation $i');
      expect(h.bridge.snapshot.revision, revision, reason: 'operation $i');
      expect(replay, expected);
      expect(eventRevision, revision);
      expect(
          mapExistingSnapshot(h.schema, h.store.snapshot.state, revision)
              .values,
          expected);
    }
  });
}

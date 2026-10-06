import 'dart:async';
import 'dart:math';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

FormField field(String id, ValueDefinition value,
        {FieldConstraints? constraints, List<FormOption>? options}) =>
    FormField(
        id: id,
        value: value,
        semantics: FieldSemantics(label: id),
        constraints: constraints,
        options: options);
FormIR basicForm() => FormIR(id: 'test', fields: [
      field('a', const IntegerDefinition()),
      field('b', const IntegerDefinition())
    ]);
ApplyContext context(int revision,
        {String operation = 'op', ActionOrigin origin = ActionOrigin.user}) =>
    ApplyContext(
        expectedRevision: revision,
        interactionId: 'interaction',
        operationId: operation,
        proposalId: 'proposal',
        origin: origin);
SetValueAction set(String id, int value) =>
    SetValueAction(fieldId: id, value: IntegerValue(value));
FormStateBridgeCapabilities capabilities(
        {bool writable = true,
        bool batch = true,
        bool atomic = true,
        bool undo = true,
        bool redo = true,
        bool navigation = true}) =>
    FormStateBridgeCapabilities(
        writable: writable,
        supportsBatch: batch,
        supportsAtomicBatch: atomic,
        supportsUndo: undo,
        supportsRedo: redo,
        supportsExternalChanges: false,
        supportsActiveField: navigation,
        supportsNavigation: navigation);
void rejected(ActionResult result, ActionRejectionCode code) {
  expect(result, isA<ActionRejected>());
  expect((result as ActionRejected).rejection.code, code);
}

void main() {
  test('set/clear, no-ops, immutable old snapshots and revision progression',
      () async {
    final initial = <String, FormValue>{'a': const IntegerValue(1)};
    final bridge =
        LocalFormStateBridge(form: basicForm(), initialValues: initial);
    addTearDown(bridge.dispose);
    initial.clear();
    final before = bridge.snapshot;
    expect(before.values, {'a': const IntegerValue(1)});
    expect(before.values.clear, throwsUnsupportedError);
    expect(await bridge.apply(set('a', 1), context: context(0)),
        isA<ActionNoOp>());
    expect(
        await bridge.apply(const ClearValueAction(fieldId: 'b'),
            context: context(0)),
        isA<ActionNoOp>());
    final result = await bridge.apply(set('a', 2), context: context(0));
    expect(result, isA<ActionApplied>());
    expect((result as ActionApplied).previousRevision, 0);
    expect(result.revision, 1);
    expect(identical(result.snapshot, bridge.snapshot), isTrue);
    expect(before.values['a'], const IntegerValue(1));
    await bridge.apply(const ClearValueAction(fieldId: 'a'),
        context: context(1));
    expect(bridge.snapshot.values, isEmpty);
    expect(bridge.snapshot.revision, 2);
  });
  test('stale concurrent writes cannot overwrite the winner', () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final results = await Future.wait([
      bridge.apply(set('a', 1), context: context(0)),
      bridge.apply(set('a', 2), context: context(0))
    ]);
    expect(results.first, isA<ActionApplied>());
    rejected(results.last, ActionRejectionCode.staleRevision);
    expect(bridge.snapshot.values['a'], const IntegerValue(1));
    expect(bridge.snapshot.revision, 1);
    rejected(await bridge.apply(set('a', 9), context: context(-1)),
        ActionRejectionCode.staleRevision);
  });
  test(
      'atomic batch validates all, rolls back state/focus/history and never emits speculative changes',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm(), activeFieldId: 'a');
    addTearDown(bridge.dispose);
    final events = <FormStateBridgeEvent>[];
    bridge.events.listen(events.add);
    final before = bridge.snapshot;
    final result = await bridge.applyBatch([
      set('a', 2),
      const NavigateAction(target: FieldNavigationTarget(fieldId: 'b')),
      set('missing', 3)
    ], context: context(0), mode: BatchApplyMode.atomic);
    expect(result.status, BatchStatus.rejected);
    expect(identical(before, bridge.snapshot), isTrue);
    rejected(result.results.first, ActionRejectionCode.atomicBatchAborted);
    rejected(result.results.last, ActionRejectionCode.unknownField);
    expect(events.whereType<StateChanged>(), isEmpty);
    expect(events.whereType<ActiveFieldChanged>(), isEmpty);
    rejected(await bridge.undo(context: context(0)),
        ActionRejectionCode.capabilityUnavailable);
  });
  test(
      'atomic batch commits once, returns one final snapshot and undoes as one unit',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final events = <FormStateBridgeEvent>[];
    bridge.events.listen(events.add);
    final result = await bridge.applyBatch([set('a', 1), set('b', 2)],
        context: context(0), mode: BatchApplyMode.atomic);
    expect(result.status, BatchStatus.applied);
    expect(result.baseRevision, 0);
    expect(result.finalRevision, 1);
    for (final applied in result.results.cast<ActionApplied>()) {
      expect(applied.previousRevision, 0);
      expect(applied.revision, 1);
      expect(identical(applied.snapshot, result.snapshot), isTrue);
    }
    expect(events.whereType<StateChanged>().length, 1);
    expect(events.whereType<StateChanged>().single.changes.length, 2);
    final undo = await bridge.undo(context: context(1));
    expect(undo, isA<ActionApplied>());
    expect(bridge.snapshot.values, isEmpty);
    expect(bridge.snapshot.revision, 2);
    await bridge.redo(context: context(2));
    expect(bridge.snapshot.values,
        {'a': const IntegerValue(1), 'b': const IntegerValue(2)});
    expect(bridge.snapshot.revision, 3);
  });
  test('atomic net no-op and empty batches do not increment or create history',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final result = await bridge.applyBatch(
        [set('a', 1), const ClearValueAction(fieldId: 'a')],
        context: context(0), mode: BatchApplyMode.atomic);
    expect(result.status, BatchStatus.noOp);
    expect(result.finalRevision, 0);
    expect(bridge.snapshot.values, isEmpty);
    rejected(await bridge.undo(context: context(0)),
        ActionRejectionCode.capabilityUnavailable);
    for (final mode in BatchApplyMode.values) {
      final empty =
          await bridge.applyBatch([], context: context(0), mode: mode);
      expect(empty.status, BatchStatus.noOp);
      expect(empty.results, isEmpty);
      expect(empty.finalRevision, 0);
    }
  });
  test(
      'best effort partially succeeds, reports no-ops, and retains history per commit',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final result = await bridge.applyBatch(
        [set('a', 1), set('missing', 3), set('a', 1), set('b', 2)],
        context: context(0));
    expect(result.status, BatchStatus.partiallyApplied);
    expect(result.finalRevision, 2);
    expect(result.results[0], isA<ActionApplied>());
    rejected(result.results[1], ActionRejectionCode.unknownField);
    expect(result.results[2], isA<ActionNoOp>());
    expect(result.results[3], isA<ActionApplied>());
    expect(result.results.clear, throwsUnsupportedError);
    await bridge.undo(context: context(2));
    expect(bridge.snapshot.values, {'a': const IntegerValue(1)});
    await bridge.undo(context: context(3));
    expect(bridge.snapshot.values, isEmpty);
  });
  test('logical batch is serialized and owns a defensive action-list copy',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final actions = <FormAction>[set('a', 1), set('b', 2)];
    final batch = bridge.applyBatch(actions, context: context(0));
    actions.clear();
    final competing = bridge.apply(set('a', 9), context: context(0));
    expect((await batch).finalRevision, 2);
    rejected(await competing, ActionRejectionCode.staleRevision);
    final stale = await bridge.applyBatch([set('a', 9)],
        context: context(0), mode: BatchApplyMode.atomic);
    expect(stale.rejection!.code, BatchRejectionCode.staleRevision);
    expect(stale.results, isEmpty);
  });
  test(
      'capability restrictions reject atomic without downgrading, batches, navigation and history',
      () async {
    final bridge = LocalFormStateBridge(
        form: basicForm(),
        capabilities: capabilities(
            atomic: false, undo: false, redo: false, navigation: false));
    addTearDown(bridge.dispose);
    final result = await bridge.applyBatch([set('a', 1)],
        context: context(0), mode: BatchApplyMode.atomic);
    expect(result.mode, BatchApplyMode.atomic);
    expect(result.rejection!.code, BatchRejectionCode.atomicBatchUnsupported);
    expect(bridge.snapshot.values, isEmpty);
    rejected(
        await bridge.apply(const NavigateAction(target: NextNavigationTarget()),
            context: context(0)),
        ActionRejectionCode.capabilityUnavailable);
    await bridge.apply(set('a', 1), context: context(0));
    rejected(await bridge.undo(context: context(1)),
        ActionRejectionCode.capabilityUnavailable);
    rejected(await bridge.redo(context: context(1)),
        ActionRejectionCode.capabilityUnavailable);
    final noBatch = LocalFormStateBridge(
        form: basicForm(),
        capabilities: capabilities(batch: false, atomic: false));
    addTearDown(noBatch.dispose);
    expect(
        (await noBatch.applyBatch([set('a', 1)], context: context(0)))
            .rejection!
            .code,
        BatchRejectionCode.batchUnsupported);
  });
  test(
      'read-only and completed state reject writes and history but allow supported navigation',
      () async {
    for (final lifecycle in [FormLifecycle.readOnly, FormLifecycle.completed]) {
      final bridge =
          LocalFormStateBridge(form: basicForm(), lifecycle: lifecycle);
      addTearDown(bridge.dispose);
      rejected(await bridge.apply(set('a', 1), context: context(0)),
          ActionRejectionCode.readOnly);
      rejected(
          await bridge.undo(context: context(0)), ActionRejectionCode.readOnly);
      final result =
          await bridge.applyBatch([set('a', 1)], context: context(0));
      expect(result.status, BatchStatus.rejected);
      expect(
          await bridge.apply(
              const NavigateAction(target: NextNavigationTarget()),
              context: context(0)),
          isA<ActionApplied>());
      expect(bridge.snapshot.revision, 0);
    }
    final bridge = LocalFormStateBridge(
        form: basicForm(), capabilities: capabilities(writable: false));
    addTearDown(bridge.dispose);
    rejected(await bridge.apply(set('a', 1), context: context(0)),
        ActionRejectionCode.readOnly);
  });
  test(
      'navigation boundaries/focus no-ops never change semantic revision or history',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final events = <FormStateBridgeEvent>[];
    bridge.events.listen(events.add);
    for (final target in [
      const NextNavigationTarget(),
      const NextNavigationTarget(),
      const NextNavigationTarget(),
      const PreviousNavigationTarget(),
      const PreviousNavigationTarget()
    ]) {
      await bridge.apply(NavigateAction(target: target), context: context(0));
    }
    expect(bridge.snapshot.activeFieldId, 'a');
    expect(bridge.snapshot.revision, 0);
    expect(events.whereType<ActiveFieldChanged>().length, 3);
    expect(events.whereType<StateChanged>(), isEmpty);
    rejected(
        await bridge.apply(
            const NavigateAction(
                target: FieldNavigationTarget(fieldId: 'missing')),
            context: context(0)),
        ActionRejectionCode.unknownField);
    rejected(await bridge.undo(context: context(0)),
        ActionRejectionCode.capabilityUnavailable);
    final empty = LocalFormStateBridge(form: FormIR(id: 'empty', fields: []));
    addTearDown(empty.dispose);
    expect(
        await empty.apply(const NavigateAction(target: NextNavigationTarget()),
            context: context(0)),
        isA<ActionNoOp>());
  });
  test(
      'snapshot is visible during events; provenance, ordering and reentrant operations survive',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final events = <FormStateBridgeEvent>[];
    Future<ActionResult>? reentrant;
    bridge.events.listen((event) {
      events.add(event);
      if (event is StateChanged) {
        expect(bridge.snapshot.revision, event.revision);
        for (final change in event.changes) {
          expect(bridge.snapshot.values[change.fieldId], change.value);
        }
        expect(event.interactionId, 'interaction');
        expect(event.proposalId, 'proposal');
        expect(() => event.changes.clear(), throwsUnsupportedError);
        if (event.operationId == 'first') {
          reentrant = bridge.apply(set('b', 2),
              context: context(event.revision, operation: 'second'));
        }
      }
    });
    await bridge.apply(set('a', 1),
        context:
            context(0, operation: 'first', origin: ActionOrigin.intelligence));
    await reentrant!;
    expect(events.map((e) => e.runtimeType).toList(), [
      BridgeInitialized,
      StateChanged,
      ActionCompleted,
      StateChanged,
      ActionCompleted
    ]);
    expect(events.whereType<StateChanged>().first.origin,
        ChangeOrigin.intelligence);
    final completed = events.whereType<ActionCompleted>().first;
    expect(completed.operationId, 'first');
    expect(completed.interactionId, 'interaction');
    expect(completed.proposalId, 'proposal');
    expect((completed.result as ActionApplied).snapshot.revision, 1);
    await bridge.apply(set('b', 2), context: context(2));
    expect(events.whereType<StateChanged>().length, 2);
  });
  test(
      'undo/redo origins, stale guards, no-op preservation and redo invalidation',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final events = <FormStateBridgeEvent>[];
    bridge.events.listen(events.add);
    await bridge.apply(set('a', 1), context: context(0));
    rejected(await bridge.undo(context: context(0)),
        ActionRejectionCode.staleRevision);
    await bridge.undo(context: context(1));
    expect(events.whereType<StateChanged>().last.origin, ChangeOrigin.undo);
    expect(
        await bridge.apply(const ClearValueAction(fieldId: 'a'),
            context: context(2)),
        isA<ActionNoOp>());
    await bridge.redo(context: context(2));
    expect(events.whereType<StateChanged>().last.origin, ChangeOrigin.redo);
    await bridge.undo(context: context(3));
    await bridge.apply(set('b', 2), context: context(4));
    rejected(await bridge.redo(context: context(5)),
        ActionRejectionCode.capabilityUnavailable);
    expect(bridge.snapshot.values, {'b': const IntegerValue(2)});
  });
  test(
      'dispose is ordered and idempotent; subsequent writes and batches are rejected',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    final events = <FormStateBridgeEvent>[];
    final done = Completer<void>();
    bridge.events.listen(events.add, onDone: done.complete);
    final pending = bridge.apply(set('a', 1), context: context(0));
    final disposal = bridge.dispose();
    expect(identical(disposal, bridge.dispose()), isTrue);
    expect(await pending, isA<ActionApplied>());
    await disposal;
    await done.future;
    expect(events.last, isA<BridgeDisposed>());
    expect(events.whereType<BridgeDisposed>().length, 1);
    rejected(await bridge.apply(set('a', 2), context: context(1)),
        ActionRejectionCode.disposed);
    rejected(
        await bridge.undo(context: context(1)), ActionRejectionCode.disposed);
    rejected(
        await bridge.redo(context: context(1)), ActionRejectionCode.disposed);
    expect((await bridge.applyBatch([], context: context(1))).rejection!.code,
        BatchRejectionCode.disposed);
    expect(bridge.snapshot.revision, 1);
  });
  test('invalid canonical schema/initial state rejected at construction', () {
    expect(
        () => LocalFormStateBridge(
            form: basicForm(),
            initialValues: {'missing': const IntegerValue(1)}),
        throwsArgumentError);
    expect(
        () => LocalFormStateBridge(
            form: basicForm(), initialValues: {'a': const StringValue('1')}),
        throwsArgumentError);
    expect(
        () => LocalFormStateBridge(form: basicForm(), activeFieldId: 'missing'),
        throwsArgumentError);
    expect(
        () => LocalFormStateBridge(
                form: FormIR(id: 'x', fields: [
              field('a', const IntegerDefinition()),
              field('a', const IntegerDefinition())
            ])),
        throwsArgumentError);
    expect(
        () => LocalFormStateBridge(
                form: FormIR(id: 'x', fields: [
              field('a', const StringDefinition(),
                  constraints: FieldConstraints(pattern: '['))
            ])),
        throwsFormatException);
    expect(
        () => LocalFormStateBridge(
                form: FormIR(id: 'x', fields: [
              field('a', const IntegerDefinition(),
                  constraints: FieldConstraints(min: 9, max: 1))
            ])),
        throwsArgumentError);
  });
  test('all value kinds and constraints validated against canonical FormIR',
      () async {
    final form = FormIR(id: 'validation', fields: [
      field('str', const StringDefinition(),
          constraints: FieldConstraints(
              required: true,
              minLength: 2,
              maxLength: 4,
              pattern: r'^[a-z]+$')),
      field('int', const IntegerDefinition(),
          constraints: FieldConstraints(min: 1, max: 3)),
      field('num', const NumberDefinition(),
          constraints: FieldConstraints(min: 1, max: 3)),
      field('bool', const BooleanDefinition()),
      field('date', const DateDefinition()),
      field('choice', const ChoiceDefinition(multiple: false),
          options: [FormOption(id: 'option', label: 'Display label')]),
      field('multi', const ChoiceDefinition(multiple: true),
          constraints: FieldConstraints(required: true),
          options: [FormOption(id: 'option', label: 'Display label')]),
    ]);
    final bridge = LocalFormStateBridge(form: form);
    addTearDown(bridge.dispose);
    final invalid = <SetValueAction>[
      SetValueAction(fieldId: 'str', value: const StringValue('')),
      SetValueAction(fieldId: 'str', value: const StringValue('a')),
      SetValueAction(fieldId: 'str', value: const StringValue('abcde')),
      SetValueAction(fieldId: 'str', value: const StringValue('ABC')),
      set('int', 0),
      set('int', 4),
      SetValueAction(fieldId: 'num', value: NumberValue(0)),
      SetValueAction(fieldId: 'num', value: NumberValue(4)),
      SetValueAction(fieldId: 'choice', value: ChoiceValue('Display label')),
      SetValueAction(fieldId: 'multi', value: MultiChoiceValue(['missing'])),
      SetValueAction(fieldId: 'multi', value: MultiChoiceValue([])),
      SetValueAction(fieldId: 'int', value: NumberValue(2)),
      set('num', 2),
      SetValueAction(fieldId: 'bool', value: const StringValue('true')),
      SetValueAction(fieldId: 'date', value: const StringValue('2024-02-29')),
      SetValueAction(fieldId: 'multi', value: ChoiceValue('option')),
    ];
    for (final action in invalid) {
      final result = await bridge.apply(action, context: context(0));
      expect(result, isA<ActionRejected>());
      expect(
          (result as ActionRejected).rejection.details['issues'], isNotEmpty);
    }
    rejected(
        await bridge.apply(const ClearValueAction(fieldId: 'str'),
            context: context(0)),
        ActionRejectionCode.validationFailed);
    expect(bridge.snapshot.revision, 0);
    final valid = [
      SetValueAction(fieldId: 'str', value: const StringValue('abc')),
      set('int', 2),
      SetValueAction(fieldId: 'num', value: NumberValue(2)),
      SetValueAction(fieldId: 'bool', value: const BooleanValue(false)),
      SetValueAction(fieldId: 'date', value: DateValue('2024-02-29')),
      SetValueAction(fieldId: 'choice', value: ChoiceValue('option')),
      SetValueAction(fieldId: 'multi', value: MultiChoiceValue(['option']))
    ];
    final result = await bridge.applyBatch(valid,
        context: context(0), mode: BatchApplyMode.atomic);
    expect(result.status, BatchStatus.applied);
    expect(result.finalRevision, 1);
    expect(result.snapshot.values.length, 7);
    rejected(
        await bridge.apply(
            RequestClarificationAction(reason: ClarificationReason.ambiguous),
            context: context(1)),
        ActionRejectionCode.unsupportedAction);
  });

  test(
      'listener attaching after write enqueue receives initialization before changes',
      () async {
    final bridge = LocalFormStateBridge(form: basicForm());
    addTearDown(bridge.dispose);
    final pending = bridge.apply(set('a', 1), context: context(0));
    final events = <FormStateBridgeEvent>[];
    bridge.events.listen((event) {
      events.add(event);
      if (event is BridgeInitialized) {
        expect(event.snapshot.revision, 0);
        expect(bridge.snapshot.revision, 0);
      }
    });
    await pending;
    expect(events.map((e) => e.runtimeType).toList(),
        [BridgeInitialized, StateChanged, ActionCompleted]);
  });
  for (final seed in [0, 1, 7, 42, 2026]) {
    test(
        'randomized replay preserves state/history/event invariants seed $seed (1000 operations)',
        () async {
      final random = Random(seed);
      final bridge = LocalFormStateBridge(form: basicForm());
      addTearDown(bridge.dispose);
      var expected = <String, FormValue>{};
      var revision = 0;
      final undo = <Map<String, FormValue>>[];
      final redo = <Map<String, FormValue>>[];
      var replay = <String, FormValue>{};
      var eventRevision = 0;
      bridge.events.listen((event) {
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
          expect(replay, bridge.snapshot.values);
          expect(bridge.snapshot.revision, eventRevision);
        }
      });
      FormAction randomAction() => random.nextBool()
          ? set(random.nextBool() ? 'a' : 'b', random.nextInt(5))
          : ClearValueAction(fieldId: random.nextBool() ? 'a' : 'b');
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
          undo.add(Map.of(expected));
          redo.clear();
          expected = next;
          revision++;
        }
      }

      for (var i = 0; i < 1000; i++) {
        final kind = random.nextInt(8);
        switch (kind) {
          case 0:
          case 1:
            final action = randomAction();
            commit(project(expected, action));
            await bridge.apply(action,
                context: context(bridge.snapshot.revision));
          case 2:
            final actions = List<FormAction>.generate(3, (_) => randomAction());
            var candidate = Map<String, FormValue>.of(expected);
            for (final action in actions) {
              candidate = project(candidate, action);
            }
            commit(candidate);
            await bridge.applyBatch(actions,
                context: context(bridge.snapshot.revision),
                mode: BatchApplyMode.atomic);
          case 3:
            final actions = List<FormAction>.generate(3, (_) => randomAction());
            final base = bridge.snapshot.revision;
            for (final action in actions) {
              commit(project(expected, action));
            }
            await bridge.applyBatch(actions, context: context(base));
          case 4:
            final result =
                await bridge.undo(context: context(bridge.snapshot.revision));
            if (undo.isEmpty) {
              rejected(result, ActionRejectionCode.capabilityUnavailable);
            } else {
              redo.add(Map.of(expected));
              expected = undo.removeLast();
              revision++;
              expect(result, isA<ActionApplied>());
            }
          case 5:
            final result =
                await bridge.redo(context: context(bridge.snapshot.revision));
            if (redo.isEmpty) {
              rejected(result, ActionRejectionCode.capabilityUnavailable);
            } else {
              undo.add(Map.of(expected));
              expected = redo.removeLast();
              revision++;
              expect(result, isA<ActionApplied>());
            }
          case 6:
            rejected(
                await bridge.apply(randomAction(),
                    context: context(bridge.snapshot.revision - 1)),
                ActionRejectionCode.staleRevision);
          case 7:
            final result = await bridge.applyBatch(
                [randomAction(), set('missing', 1)],
                context: context(bridge.snapshot.revision),
                mode: BatchApplyMode.atomic);
            expect(result.status, BatchStatus.rejected);
        }
        expect(bridge.snapshot.values, expected, reason: 'operation $i');
        expect(bridge.snapshot.revision, revision, reason: 'operation $i');
        expect(replay, expected);
        expect(eventRevision, revision);
      }
    });
  }
}

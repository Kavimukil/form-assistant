import 'dart:async';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/form_assistant_function_gemma.dart';
import 'package:test/test.dart';
import 'strict_extraction_test.dart' show native;

void main() {
  for (final relevant in [true, false]) {
    test(
        'pending extraction: ${relevant ? 'relevant change reruns' : 'unrelated change revalidates'}',
        () async {
      final form = FormIR(id: 'f', fields: [
        for (final id in ['age', 'other'])
          FormField(
              id: id,
              value: const IntegerDefinition(),
              semantics: FieldSemantics(label: id))
      ]);
      final bridge = LocalFormStateBridge(form: form, activeFieldId: 'age');
      // Start at revision 17 without changing source contracts.
      for (var i = 0; i < 17; i++) {
        await bridge.apply(
            SetValueAction(fieldId: 'other', value: IntegerValue(i)),
            context: ApplyContext(
                expectedRevision: i,
                interactionId: 'seed$i',
                operationId: 'seed$i',
                origin: ActionOrigin.user));
      }
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final prompts = <String>[];
      final adapter = FunctionGemmaAdapter(inference: (prompt, token) async {
        prompts.add(prompt);
        if (++calls == 1) {
          started.complete();
          await release.future;
        }
        return FunctionGemmaOutput(
            native('set_integer', 'field_id:<escape>age<escape>,value:32'));
      });
      final runtime = FormAssistantRuntime(
          form: form,
          bridge: bridge,
          intelligence: adapter,
          contextBudget: ContextBudget(maxFields: 1));
      final events = <RuntimeEvent>[];
      runtime.events.listen(events.add);
      final pending = runtime.submit(const UserInput(text: 'Age thirty two'),
          trace: const TraceContext(
              interactionId: 'i', requestId: 'r', operationId: 'o'));
      await started.future;
      await bridge.apply(
          SetValueAction(
              fieldId: relevant ? 'age' : 'other',
              value: const IntegerValue(40)),
          context: const ApplyContext(
              expectedRevision: 17,
              interactionId: 'external',
              operationId: 'external',
              origin: ActionOrigin.user));
      release.complete();
      final result = await pending;
      expect(result.errorCode, isNull);
      expect(result.snapshot.values['age'], const IntegerValue(32));
      expect(calls, relevant ? 2 : 1);
      expect(result.proposal!.baseRevision, relevant ? 18 : 17);
      expect(result.snapshot.revision, 19);
      if (relevant) {
        expect(prompts.last, contains('"current":40'));
        expect(events.whereType<ProposalDiscarded>(), hasLength(1));
      } else {
        expect(events.whereType<ProposalRevalidated>(), hasLength(1));
      }
      await runtime.dispose();
      await bridge.dispose();
    });
  }
}

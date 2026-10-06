import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/form_assistant_function_gemma.dart';
import 'package:form_assistant_function_gemma/src/extraction_quality.dart';
import 'package:test/test.dart';
import 'extraction_adapter_test.dart' show extractionRequest;
import 'strict_extraction_test.dart' show native;

void main() {
  test(
      'empty calls clarify deterministically; invalid constraints never become mutations',
      () async {
    final field = FormField(
        id: 'age',
        value: const IntegerDefinition(),
        semantics: FieldSemantics(label: 'Age'),
        constraints: FieldConstraints(min: 18, max: 100));
    final r = IntelligenceRequest(
        input: const UserInput(text: 'Age one hundred fifty'),
        context: SemanticContext(
            formId: 'f', revision: 0, fields: [FormFieldContext(field: field)]),
        allowedActionTypes: ['set_value'],
        trace: const TraceContext(
            interactionId: 'i', requestId: 'r', operationId: 'o'));
    for (final output in [
      '',
      native('set_integer', 'field_id:<escape>age<escape>,value:150')
    ]) {
      final result = await FunctionGemmaAdapter(
          inference: (_, __) async => FunctionGemmaOutput(output)).interpret(r);
      expect(result.quality, QualityOutcome.clarify);
      expect(result.proposal.actions.single.action,
          isA<RequestClarificationAction>());
    }
  });
  test('provider-neutral gate enforces writable and conflicting writes', () {
    final r = extractionRequest();
    final writes = [
      ProposedAction(
          id: 'a',
          action:
              const SetValueAction(fieldId: 'age', value: IntegerValue(31))),
      ProposedAction(
          id: 'b',
          action: const SetValueAction(fieldId: 'age', value: IntegerValue(32)))
    ];
    expect(
        QualityGate().evaluate(r, writes, rejectConflictingWrites: true).reason,
        'conflicting_writes');
    expect(
        QualityGate()
            .evaluate(
                r,
                [
                  writes.first,
                  ProposedAction(id: 'c', action: writes.first.action)
                ],
                rejectConflictingWrites: true)
            .actions,
        hasLength(1));
    expect(
        QualityGate().evaluate(r, [
          const ProposedAction(
              id: 'locked',
              action:
                  SetValueAction(fieldId: 'locked', value: StringValue('x')))
        ]).reason,
        'non_writable_field');
    expect(
        FunctionGemmaQualityGate(QualityGate())
            .reject(const FormatException('malformed'))
            .outcome,
        ExtractionQualityOutcome.reject);
  });
  test('native extraction emits trace/events and uses authoritative bridge',
      () async {
    final form = FormIR(id: 'f', fields: [
      FormField(
          id: 'age',
          value: const IntegerDefinition(),
          semantics: FieldSemantics(label: 'Age')),
      FormField(
          id: 'consent',
          value: const BooleanDefinition(),
          semantics: FieldSemantics(label: 'Consent'))
    ]);
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'age');
    final adapter = FunctionGemmaAdapter(
        inference: (_, __) async => FunctionGemmaOutput(native(
                'set_integer', 'field_id:<escape>age<escape>,value:32') +
            native(
                'set_boolean', 'field_id:<escape>consent<escape>,value:true')));
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: adapter);
    final events = <RuntimeEvent>[];
    runtime.events.listen(events.add);
    final result = await runtime.submit(extractionRequest().input,
        trace: extractionRequest().trace, contextFieldIds: ['age', 'consent']);
    expect(result.snapshot.values,
        {'age': const IntegerValue(32), 'consent': const BooleanValue(true)});
    expect(result.errorCode, isNull);
    expect(events.whereType<IntelligenceQualityEvaluated>().single.outcome,
        QualityOutcome.accept);
    expect(result.actions.every((a) => a.trace.actionId != null), isTrue);
    await runtime.dispose();
    await bridge.dispose();
  });
}

import 'dart:async';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

IntelligenceRequest request() => IntelligenceRequest(
    input: const UserInput(text: 'please set answers'),
    context: SemanticContext(formId: 'form', revision: 2, fields: [
      FormFieldContext(
          field: FormField(
              id: 'age',
              value: const IntegerDefinition(),
              semantics: FieldSemantics(label: 'Age'),
              constraints: FieldConstraints(max: 120)))
    ], values: {}),
    allowedActionTypes: ['set_value', 'request_clarification'],
    trace: const TraceContext(
        interactionId: 'i', requestId: 'r', operationId: 'o'));
void main() {
  test(
      'quality preserves valid multi-action portion and clarifies invalid value',
      () {
    final decision = QualityGate().evaluate(request(), [
      const ProposedAction(
          id: 'a',
          action: SetValueAction(fieldId: 'age', value: IntegerValue(25))),
      const ProposedAction(
          id: 'b',
          action: SetValueAction(fieldId: 'age', value: IntegerValue(200)))
    ]);
    expect(decision.outcome, QualityOutcome.clarify);
    expect(decision.actions.first.action, isA<SetValueAction>());
    expect(decision.actions.last.action, isA<RequestClarificationAction>());
    expect(decision.actions.clear, throwsUnsupportedError);
  });
  test('quality thresholds finite and model confidence validation strict', () {
    expect(
        () => QualityGate(minimumConfidence: double.nan), throwsArgumentError);
    expect(() => QualityGate().evaluate(request(), [], confidence: 1.1),
        throwsFormatException);
    expect(QualityGate().evaluate(request(), [], confidence: 0.2).reason,
        'low_confidence');
    expect(QualityGate().evaluate(request(), []).reason, 'no_answer');
  });
  test(
      'pre-cancelled mock never invokes handler and cancellation listeners detach',
      () async {
    final token = CancellationToken();
    var calls = 0;
    final detach = token.listen(() {
      calls++;
    });
    detach();
    token.cancel();
    token.cancel();
    expect(calls, 0);
    final mock = MockIntelligenceAdapter(handler: (_) {
      calls++;
      throw StateError('unexpected');
    });
    await expectLater(
        mock.interpret(request(),
            options: IntelligenceOptions(cancellation: token)),
        throwsA(isA<IntelligenceCancelled>()));
    expect(calls, 0);
    expect(mock.requests, isEmpty);
  });
  test('mock timeout ignores late errors; invalid timeout rejected', () async {
    final held = Completer<IntelligenceResult>();
    final mock = MockIntelligenceAdapter(handler: (_) => held.future);
    await expectLater(
        mock.interpret(request(),
            options:
                const IntelligenceOptions(timeout: Duration(milliseconds: 10))),
        throwsA(isA<TimeoutException>()));
    held.completeError(StateError('late'));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
        mock.interpret(request(),
            options: const IntelligenceOptions(timeout: Duration.zero)),
        throwsArgumentError);
  });
  test('runtime cancellation before submit bypasses router, model and bridge',
      () async {
    final form =
        FormIR(id: 'form', fields: [request().context.fields.single.field]);
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'age');
    final mock =
        MockIntelligenceAdapter(handler: (_) => throw StateError('unexpected'));
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: mock);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    final token = CancellationToken()..cancel();
    final result = await runtime.submit(const UserInput(text: 'twenty'),
        trace: request().trace,
        options: IntelligenceOptions(cancellation: token));
    expect(result.errorCode, 'runtime.cancelled');
    expect(mock.requests, isEmpty);
    expect(bridge.snapshot.values, isEmpty);
  });
}

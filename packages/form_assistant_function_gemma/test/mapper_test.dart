import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/tools/mapper.dart';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';
import 'package:form_assistant_function_gemma/src/tools/validator.dart';
import 'package:test/test.dart';
import 'strict_extraction_test.dart' show strictContext;

void main() {
  test('all eight mappings preserve canonical action codecs', () {
    final cases = {
      'set_string': ['name', 'Mukil'],
      'set_integer': ['age', 32],
      'set_number': ['weight', 72.5],
      'set_boolean': ['consent', false],
      'set_date': ['date', '1992-08-14'],
      'set_choice': ['promotion', 'fall'],
      'set_multi_choice': [
        'tech',
        ['java', 'fall']
      ],
      'clear_field': ['age']
    };
    for (final entry in cases.entries) {
      final call = FunctionGemmaToolCall(name: entry.key, arguments: {
        'field_id': entry.value.first,
        if (entry.value.length > 1) 'value': entry.value[1]
      });
      final action = mapFunctionGemmaCall(call);
      expect(FormActionCodec.decode(action.toJson()), action);
      expect(
          action,
          entry.key == 'clear_field'
              ? isA<ClearValueAction>()
              : isA<SetValueAction>());
      if (action is SetValueAction) {
        expect(action.value.toJson()['type'], extractionToolTypes[entry.key]);
      }
    }
  });
  test('proposal preserves model order, context revision and provenance', () {
    final calls = [
      FunctionGemmaToolCall(
          name: 'set_boolean',
          arguments: {'field_id': 'consent', 'value': true}),
      FunctionGemmaToolCall(
          name: 'set_integer', arguments: {'field_id': 'age', 'value': 32})
    ];
    final request = IntelligenceRequest(
        input: const UserInput(text: 'Consent yes, age thirty two'),
        context: strictContext(),
        allowedActionTypes: ['set_value'],
        trace: const TraceContext(
            interactionId: 'i', requestId: 'r', operationId: 'o'));
    final proposal = extractionProposal(
        FunctionGemmaToolCallValidator().validate(calls, request.context),
        request);
    expect(proposal.baseRevision, 17);
    expect(proposal.actions.map((a) => (a.action as SetValueAction).fieldId),
        ['consent', 'age']);
    expect(proposal.provenance.trace, request.trace);
    expect(proposal.provenance.adapterId, 'function_gemma');
  });
}

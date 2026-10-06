import 'package:form_assistant_core/form_assistant_core.dart';
import 'protocol.dart';
import 'validator.dart';

FormAction mapFunctionGemmaCall(FunctionGemmaToolCall call) {
  final id = requiredId(call.arguments, 'field_id');
  if (call.name == 'clear_field') return ClearValueAction(fieldId: id);
  return SetValueAction(
      fieldId: id,
      value: FormValueCodec.decode({
        'type': extractionToolTypes[call.name],
        'value': call.arguments['value']
      }));
}

ActionProposal extractionProposal(
        FunctionGemmaValidation validated, IntelligenceRequest request,
        {String adapterId = 'function_gemma',
        String adapterVersion = '0.2.0',
        double? confidence}) =>
    ActionProposal(
        id: '${request.trace.requestId}/function-gemma',
        baseRevision: request.context.revision,
        actions: [
          for (var i = 0; i < validated.calls.length; i++)
            ProposedAction(
                id: '${request.trace.requestId}/action/$i',
                action: mapFunctionGemmaCall(validated.calls[i]))
        ],
        provenance: ActionProvenance(
            trace: request.trace,
            adapterId: adapterId,
            adapterVersion: adapterVersion),
        confidence: confidence);

import 'package:form_assistant_core/form_assistant_core.dart';
import 'protocol.dart';
import 'schema.dart';

final class FunctionGemmaValidation {
  final List<FunctionGemmaToolCall> calls;
  final int identicalDuplicates;
  FunctionGemmaValidation(
      List<FunctionGemmaToolCall> calls, this.identicalDuplicates)
      : calls = List.unmodifiable(calls);
}

final class FunctionGemmaToolCallValidator {
  FunctionGemmaValidation validate(
      List<FunctionGemmaToolCall> calls, SemanticContext context,
      {List<String>? allowedActionTypes}) {
    final fields = {for (final f in context.fields) f.id: f};
    final seen = <String, FunctionGemmaToolCall>{};
    final accepted = <FunctionGemmaToolCall>[];
    var duplicates = 0;
    for (final call in calls) {
      final id = requiredId(call.arguments, 'field_id');
      final field = fields[id];
      if (field == null) throw const FormatException('Unknown context field');
      if (!field.writable) throw const FormatException('Non-writable field');
      final clear = call.name == 'clear_field';
      if (allowedActionTypes != null &&
          !allowedActionTypes.contains(clear ? 'clear_value' : 'set_value')) {
        throw const FormatException('Disallowed mutation');
      }
      if (!clear && extractionToolTypes[call.name] != semanticType(field)) {
        throw const FormatException('Wrong setter for field type');
      }
      if (call.name == 'set_choice' || call.name == 'set_multi_choice') {
        final ids = call.name == 'set_choice'
            ? [requiredString(call.arguments, 'value')]
            : stringList(call.arguments['value']);
        if (ids.any((id) => !optionIds(field).contains(id))) {
          throw const FormatException('Unknown canonical option');
        }
      }
      final previous = seen[id];
      if (previous != null) {
        final equivalent = call.name == previous.name &&
            (call.name == 'set_multi_choice'
                ? jsonEquals(
                    canonicalStrings(stringList(call.arguments['value'])),
                    canonicalStrings(stringList(previous.arguments['value'])))
                : jsonEquals(call.arguments, previous.arguments));
        if (!equivalent) {
          throw const FormatException('Conflicting same-field writes');
        }
        duplicates++;
        continue;
      }
      seen[id] = call;
      accepted.add(call);
    }
    return FunctionGemmaValidation(accepted, duplicates);
  }
}

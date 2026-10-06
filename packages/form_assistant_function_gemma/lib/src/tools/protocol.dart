import 'package:form_assistant_core/form_assistant_core.dart';

const toolProtocolVersion = '1.0';
const extractionToolTypes = <String, String>{
  'set_string': 'string',
  'set_integer': 'integer',
  'set_number': 'number',
  'set_boolean': 'boolean',
  'set_date': 'date',
  'set_choice': 'choice',
  'set_multi_choice': 'multi_choice',
  'clear_field': 'clear',
};

final class FunctionGemmaToolCall {
  final String name;
  final Map<String, Object?> arguments;
  FunctionGemmaToolCall(
      {required this.name, required Map<String, Object?> arguments})
      : arguments = jsonObject(arguments) {
    final kind = extractionToolTypes[name];
    if (kind == null) throw const FormatException('Unknown extraction tool');
    final expected = kind == 'clear' ? ['field_id'] : ['field_id', 'value'];
    if (arguments.length != expected.length ||
        !expected.every(arguments.containsKey)) {
      throw const FormatException('Unexpected tool arguments');
    }
    requiredId(arguments, 'field_id');
    if (kind != 'clear') {
      if (kind == 'multi_choice') {
        final ids = stringList(arguments['value'], nonEmpty: true);
        if (ids.toSet().length != ids.length) {
          throw const FormatException('Duplicate multi-choice IDs');
        }
      }
      FormValueCodec.decode({'type': kind, 'value': arguments['value']});
    }
  }
  Map<String, Object?> toJson() => {'name': name, 'arguments': arguments};
  factory FunctionGemmaToolCall.fromJson(Object? input) {
    final j = jsonObject(input);
    if (j.length != 2 ||
        !j.containsKey('name') ||
        !j.containsKey('arguments')) {
      throw const FormatException('Unexpected call envelope');
    }
    return FunctionGemmaToolCall(
        name: requiredString(j, 'name'), arguments: jsonObject(j['arguments']));
  }
}

Map<String, Object?> primitiveArgumentsSchema(String name) {
  final kind = extractionToolTypes[name];
  if (kind == null) throw const FormatException('Unknown extraction tool');
  final value = switch (kind) {
    'multi_choice' => <String, Object?>{
        'type': 'array',
        'uniqueItems': true,
        'items': {'type': 'string', 'minLength': 1}
      },
    'choice' => <String, Object?>{'type': 'string', 'minLength': 1},
    'date' => <String, Object?>{
        'type': 'string',
        'format': 'date',
        'pattern': r'^\d{4}-\d{2}-\d{2}$'
      },
    _ => <String, Object?>{'type': kind},
  };
  return {
    'type': 'object',
    'additionalProperties': false,
    'required': ['field_id', if (kind != 'clear') 'value'],
    'properties': {
      'field_id': {'type': 'string', 'minLength': 1},
      if (kind != 'clear') 'value': value
    }
  };
}

Map<String, Object?> extractionProtocolSchema() => {
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'title': 'FunctionGemma Extraction Tool Call v1',
      'oneOf': [
        for (final name in extractionToolTypes.keys)
          {
            'type': 'object',
            'additionalProperties': false,
            'required': ['name', 'arguments'],
            'properties': {
              'name': {'const': name},
              'arguments': primitiveArgumentsSchema(name)
            },
          }
      ],
    };

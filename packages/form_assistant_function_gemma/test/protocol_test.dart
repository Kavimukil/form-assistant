import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';
import 'package:test/test.dart';

void main() {
  test('frozen eight tool schema matches golden', () {
    expect(extractionToolTypes.keys, [
      'set_string',
      'set_integer',
      'set_number',
      'set_boolean',
      'set_date',
      'set_choice',
      'set_multi_choice',
      'clear_field'
    ]);
    expect(
        extractionProtocolSchema(),
        jsonDecode(File('test/fixtures/extraction_protocol.v1.json')
            .readAsStringSync()));
  });
  test('strict call DTO rejects extra envelope/arguments and wrong primitives',
      () {
    for (final j in [
      {
        'name': 'navigate',
        'arguments': {'field_id': 'age'}
      },
      {
        'name': 'set_integer',
        'arguments': {'field_id': 'age', 'value': '32'}
      },
      {
        'name': 'set_boolean',
        'arguments': {'field_id': 'consent', 'value': 'yes'}
      },
      {
        'name': 'clear_field',
        'arguments': {'field_id': 'age', 'value': 1}
      },
      {
        'name': 'set_multi_choice',
        'arguments': {
          'field_id': 'tech',
          'value': ['java', 'java']
        }
      },
      {
        'name': 'clear_field',
        'arguments': {'field_id': 'age'},
        'extra': true
      },
    ]) {
      expect(() => FunctionGemmaToolCall.fromJson(j), throwsFormatException);
    }
    final j = {
      'name': 'set_integer',
      'arguments': {'field_id': 'age', 'value': 32}
    };
    expect(FunctionGemmaToolCall.fromJson(j).toJson(), j);
  });
}

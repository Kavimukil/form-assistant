import 'dart:convert';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'protocol.dart';

final class FunctionGemmaToolDefinition {
  final String name;
  final Map<String, Object?> parameters;
  FunctionGemmaToolDefinition(this.name, Map<String, Object?> parameters)
      : parameters = jsonObject(parameters);
  Map<String, Object?> toJson() => {'name': name, 'parameters': parameters};
}

final class FunctionGemmaToolSet {
  final List<FunctionGemmaToolDefinition> definitions;
  FunctionGemmaToolSet(List<FunctionGemmaToolDefinition> definitions)
      : definitions = List.unmodifiable(definitions);
  List<Object?> toJson() => definitions.map((d) => d.toJson()).toList();
  String get fingerprint => semanticFingerprint(toJson());
  String get canonicalJson => fingerprint.substring('canonical-json:'.length);
}

final class FunctionGemmaToolSchemaBuilder {
  static const version = '1.0';
  FunctionGemmaToolSet build(SemanticContext context,
      {List<String>? allowedActionTypes}) {
    final selected = context.fields.where((f) => f.writable).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final tools = <FunctionGemmaToolDefinition>[];
    for (final entry in extractionToolTypes.entries) {
      final clear = entry.key == 'clear_field';
      if (allowedActionTypes != null &&
          !allowedActionTypes.contains(clear ? 'clear_value' : 'set_value')) {
        continue;
      }
      final fields = selected
          .where((f) => clear || semanticType(f) == entry.value)
          .toList();
      if (fields.isEmpty) continue;
      final properties = <String, Object?>{
        'field_id': {'type': 'string', 'enum': fields.map((f) => f.id).toList()}
      };
      if (!clear) {
        properties['value'] = (primitiveArgumentsSchema(entry.key)['properties']
            as Map<String, Object?>)['value'];
      }
      final parameters = <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': ['field_id', if (!clear) 'value'],
        'properties': properties
      };
      if (entry.value == 'choice' || entry.value == 'multi_choice') {
        // Correlated branches are strict JSON schema. Native schema encoder uses
        // this same structure; validator independently enforces field membership.
        parameters['oneOf'] = [
          for (final field in fields)
            {
              'properties': {
                'field_id': {'const': field.id},
                'value': entry.value == 'choice'
                    ? {'type': 'string', 'enum': optionIds(field)}
                    : {
                        'type': 'array',
                        'uniqueItems': true,
                        'items': {'type': 'string', 'enum': optionIds(field)}
                      },
              },
            }
        ];
      }
      tools.add(FunctionGemmaToolDefinition(entry.key, parameters));
    }
    return FunctionGemmaToolSet(tools);
  }
}

String semanticType(FormFieldContext f) =>
    f.type == SemanticValueType.multiChoice ? 'multi_choice' : f.type.name;
List<String> optionIds(FormFieldContext f) =>
    f.options.map((o) => o.id).toList()..sort();
String encodeToolSchema(FunctionGemmaToolSet tools) =>
    jsonEncode(jsonDecode(tools.canonicalJson));

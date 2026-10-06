import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_function_gemma/src/tools/schema.dart';
import '../test/schema_test.dart' show schemaContext;

void main() => File('test/fixtures/specialized_schema.v1.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(FunctionGemmaToolSchemaBuilder().build(schemaContext()).toJson())}\n');

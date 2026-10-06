import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';

void main() => File('test/fixtures/extraction_protocol.v1.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(extractionProtocolSchema())}\n');

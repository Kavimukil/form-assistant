import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';

void main() {
  for (final file
      in Directory('../../benchmarks/function_gemma_phase6r/contexts')
          .listSync()
          .whereType<File>()) {
    final j = jsonObject(jsonDecode(file.readAsStringSync()));
    final context = SemanticContext(
        formId: requiredString(j, 'formId'),
        revision: requireType<int>(j['revision']),
        activeFieldId: requiredString(j, 'activeFieldId'),
        locale: requiredString(j, 'locale'),
        fields: requireType<List<Object?>>(j['fields'])
            .map(FormFieldContext.fromJson)
            .toList());
    file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(context.toJson())}\n');
  }
}

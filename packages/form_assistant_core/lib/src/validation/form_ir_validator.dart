import '../contracts/form_action.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_value.dart';
import '../contracts/validation_metadata.dart';

/// Validates one canonical edit. Missing answers in an unfinished form are
/// permitted; clearing a required field is rejected as an invalid edit.
List<ValidationIssue> validateFieldAction(
    FormField field, FormMutationAction action) {
  final issues = <ValidationIssue>[];
  void issue(String code) => issues.add(ValidationIssue(
      code: code, severity: ValidationSeverity.error, fieldId: field.id));
  final constraints = field.constraints;
  if (action is ClearValueAction) {
    if (constraints?.required ?? false) issue('value.required');
    return List.unmodifiable(issues);
  }
  final value = (action as SetValueAction).value;
  final correct = switch (field.value) {
    StringDefinition() => value is StringValue,
    IntegerDefinition() => value is IntegerValue,
    NumberDefinition() => value is NumberValue,
    BooleanDefinition() => value is BooleanValue,
    DateDefinition() => value is DateValue,
    ChoiceDefinition(:final multiple) =>
      multiple ? value is MultiChoiceValue : value is ChoiceValue,
  };
  if (!correct) {
    issue('value.type_mismatch');
    return List.unmodifiable(issues);
  }
  if (value is ChoiceValue || value is MultiChoiceValue) {
    final ids = value is ChoiceValue
        ? [value.optionId]
        : (value as MultiChoiceValue).optionIds;
    final allowed =
        (field.options ?? const <FormOption>[]).map((o) => o.id).toSet();
    if (ids.any((id) => !allowed.contains(id))) issue('value.option_unknown');
    if ((constraints?.required ?? false) && ids.isEmpty) {
      issue('value.required');
    }
  }
  if (value is StringValue) {
    final length = value.value.runes.length;
    if ((constraints?.required ?? false) && value.value.isEmpty) {
      issue('value.required');
    }
    if (constraints?.minLength case final int min) {
      if (length < min) issue('value.below_min_length');
    }
    if (constraints?.maxLength case final int max) {
      if (length > max) issue('value.above_max_length');
    }
    if (constraints?.pattern case final String pattern) {
      if (!RegExp(pattern).hasMatch(value.value)) {
        issue('value.pattern_mismatch');
      }
    }
  }
  final numeric = switch (value) {
    IntegerValue(:final value) => value,
    NumberValue(:final value) => value,
    _ => null,
  };
  if (numeric != null) {
    if (constraints?.min case final num min) {
      if (numeric < min) issue('value.below_minimum');
    }
    if (constraints?.max case final num max) {
      if (numeric > max) issue('value.above_maximum');
    }
  }
  return List.unmodifiable(issues);
}

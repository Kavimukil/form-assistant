import 'canonical_json.dart';
import 'form_value.dart';
import 'structural_contract.dart';
import 'form_action.dart';

enum ValidationStatus { notValidated, valid, invalid }

enum ValidationSeverity { info, warning, error }

final class ValidationIssue with StructuralContract {
  final String code;
  final ValidationSeverity severity;
  final FieldId? fieldId;
  final String? message;
  final Map<String, Object?> metadata;
  ValidationIssue(
      {required this.code,
      required this.severity,
      this.fieldId,
      this.message,
      Map<String, Object?> metadata = const {}})
      : metadata = jsonObject(metadata) {}
  @override
  Map<String, Object?> toJson() => {
        'code': code,
        'severity': severity.name,
        if (fieldId != null) 'fieldId': fieldId,
        if (message != null) 'message': message,
        'metadata': metadata,
      };
  factory ValidationIssue.fromJson(Object? input) {
    final j = jsonObject(input);
    return ValidationIssue(
      code: requireType<String>(j['code']),
      severity: ValidationSeverity.values.firstWhere(
          (v) => v.name == requiredString(j, 'severity'),
          orElse: () => throw const FormatException('Unknown severity')),
      fieldId:
          j.containsKey('fieldId') ? requireType<String>(j['fieldId']) : null,
      message:
          j.containsKey('message') ? requireType<String>(j['message']) : null,
      metadata:
          j.containsKey('metadata') ? jsonObject(j['metadata']) : const {},
    );
  }
}

final class ActionValidationMetadata with StructuralContract {
  final ValidationStatus status;
  final List<ValidationIssue> issues;
  final Revision? validatedAgainstRevision;
  ActionValidationMetadata(
      {required this.status,
      List<ValidationIssue> issues = const [],
      this.validatedAgainstRevision})
      : issues = List.unmodifiable(issues) {}
  @override
  Map<String, Object?> toJson() => {
        'status': status == ValidationStatus.notValidated
            ? 'not_validated'
            : status.name,
        'issues': issues.map((v) => v.toJson()).toList(),
        if (validatedAgainstRevision != null)
          'validatedAgainstRevision': validatedAgainstRevision,
      };
  factory ActionValidationMetadata.fromJson(Object? input) {
    final j = jsonObject(input);
    return ActionValidationMetadata(
      status: ValidationStatus.values.firstWhere(
          (v) =>
              (v == ValidationStatus.notValidated ? 'not_validated' : v.name) ==
              requiredString(j, 'status'),
          orElse: () => throw const FormatException('Unknown status')),
      issues: j.containsKey('issues')
          ? requireType<List<Object?>>(j['issues'])
              .map(ValidationIssue.fromJson)
              .toList()
          : const [],
      validatedAgainstRevision: j.containsKey('validatedAgainstRevision')
          ? requireType<int>(j['validatedAgainstRevision'])
          : null,
    );
  }
}

final class ProposedAction {
  final String id;
  final FormAction action;
  final ActionValidationMetadata? validation;
  const ProposedAction(
      {required this.id, required this.action, this.validation});
}

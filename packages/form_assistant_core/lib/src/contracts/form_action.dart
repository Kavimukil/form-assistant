import 'canonical_json.dart';
import 'form_value.dart';

enum ActionClassification { mutation, navigation, assistantControl, privileged }

sealed class FormAction implements CanonicalSerializable {
  const FormAction();
  String get type;
  ActionClassification get classification;
}

sealed class FormMutationAction extends FormAction {
  const FormMutationAction();
  FieldId get fieldId;
  @override
  ActionClassification get classification => ActionClassification.mutation;
}

final class SetValueAction extends FormMutationAction {
  @override
  final FieldId fieldId;
  final FormValue value;
  const SetValueAction({required this.fieldId, required this.value});
  @override
  String get type => 'set_value';
  @override
  Map<String, Object?> toJson() =>
      {'type': type, 'fieldId': fieldId, 'value': value.toJson()};
  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      o is SetValueAction && o.fieldId == fieldId && o.value == value;
  @override
  int get hashCode => Object.hash(type, fieldId, value);
}

final class ClearValueAction extends FormMutationAction {
  @override
  final FieldId fieldId;
  const ClearValueAction({required this.fieldId});
  @override
  String get type => 'clear_value';
  @override
  Map<String, Object?> toJson() => {'type': type, 'fieldId': fieldId};
  @override
  bool operator ==(Object o) =>
      identical(this, o) || o is ClearValueAction && o.fieldId == fieldId;
  @override
  int get hashCode => Object.hash(type, fieldId);
}

sealed class FormNavigationAction extends FormAction {
  const FormNavigationAction();
  @override
  ActionClassification get classification => ActionClassification.navigation;
}

sealed class NavigationTarget implements CanonicalSerializable {
  const NavigationTarget();
  String get type;
}

final class FieldNavigationTarget extends NavigationTarget {
  final FieldId fieldId;
  const FieldNavigationTarget({required this.fieldId});
  @override
  String get type => 'field';
  @override
  Map<String, Object?> toJson() => {'type': type, 'fieldId': fieldId};
  @override
  bool operator ==(Object o) =>
      o is FieldNavigationTarget && o.fieldId == fieldId;
  @override
  int get hashCode => Object.hash(type, fieldId);
}

final class NextNavigationTarget extends NavigationTarget {
  const NextNavigationTarget();
  @override
  String get type => 'next';
  @override
  Map<String, Object?> toJson() => {'type': type};
  @override
  bool operator ==(Object o) => o is NextNavigationTarget;
  @override
  int get hashCode => type.hashCode;
}

final class PreviousNavigationTarget extends NavigationTarget {
  const PreviousNavigationTarget();
  @override
  String get type => 'previous';
  @override
  Map<String, Object?> toJson() => {'type': type};
  @override
  bool operator ==(Object o) => o is PreviousNavigationTarget;
  @override
  int get hashCode => type.hashCode;
}

final class NavigateAction extends FormNavigationAction {
  final NavigationTarget target;
  const NavigateAction({required this.target});
  @override
  String get type => 'navigate';
  @override
  Map<String, Object?> toJson() => {'type': type, 'target': target.toJson()};
  @override
  bool operator ==(Object o) => o is NavigateAction && o.target == target;
  @override
  int get hashCode => Object.hash(type, target);
}

sealed class AssistantControlAction extends FormAction {
  const AssistantControlAction();
  @override
  ActionClassification get classification =>
      ActionClassification.assistantControl;
}

enum ClarificationReason {
  ambiguous,
  missingInformation,
  invalidValue,
  lowConfidence
}

final class RequestClarificationAction extends AssistantControlAction {
  final List<FieldId> fieldIds; // MUST be deduplicated + sorted
  final ClarificationReason reason;
  final String? detail;
  RequestClarificationAction({
    Iterable<FieldId> fieldIds = const [],
    required this.reason,
    this.detail,
  }) : fieldIds = List.unmodifiable(canonicalStrings(fieldIds, nonEmpty: true));

  @override
  String get type => 'request_clarification';
  @override
  Map<String, Object?> toJson() => {
        'type': type,
        if (fieldIds.isNotEmpty) 'fieldIds': fieldIds,
        'reason': switch (reason) {
          ClarificationReason.ambiguous => 'ambiguous',
          ClarificationReason.missingInformation => 'missing_information',
          ClarificationReason.invalidValue => 'invalid_value',
          ClarificationReason.lowConfidence => 'low_confidence',
        },
        if (detail != null) 'detail': detail,
      };
  @override
  bool operator ==(Object o) =>
      o is RequestClarificationAction &&
      jsonEquals(fieldIds, o.fieldIds) &&
      reason == o.reason &&
      detail == o.detail;
  @override
  int get hashCode =>
      Object.hash(type, Object.hashAll(fieldIds), reason, detail);
}

abstract final class FormActionCodec {
  static FormAction decode(Object? input) {
    final j = jsonObject(input);
    try {
      return switch (requiredString(j, 'type')) {
        'set_value' => SetValueAction(
            fieldId: requiredId(j, 'fieldId'),
            value: FormValueCodec.decode(j['value'])),
        'clear_value' => ClearValueAction(fieldId: requiredId(j, 'fieldId')),
        'navigate' => NavigateAction(target: decodeTarget(j['target'])),
        'request_clarification' => RequestClarificationAction(
            fieldIds: j.containsKey('fieldIds')
                ? stringList(j['fieldIds'], nonEmpty: true)
                : const [],
            reason: switch (requiredString(j, 'reason')) {
              'ambiguous' => ClarificationReason.ambiguous,
              'missing_information' => ClarificationReason.missingInformation,
              'invalid_value' => ClarificationReason.invalidValue,
              'low_confidence' => ClarificationReason.lowConfidence,
              _ => throw const FormatException('Unknown clarification reason'),
            },
            detail: optional<String>(j, 'detail')),
        _ => throw const FormatException('Unknown FormAction type'),
      };
    } on ArgumentError catch (e) {
      throw FormatException('Invalid action: $e');
    }
  }

  static NavigationTarget decodeTarget(Object? input) {
    final j = jsonObject(input);
    return switch (requiredString(j, 'type')) {
      'field' => FieldNavigationTarget(fieldId: requiredId(j, 'fieldId')),
      'next' => const NextNavigationTarget(),
      'previous' => const PreviousNavigationTarget(),
      _ => throw const FormatException('Unknown navigation target'),
    };
  }

  static Map<String, Object?> encode(FormAction action) => action.toJson();
}

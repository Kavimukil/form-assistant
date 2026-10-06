import 'canonical_json.dart';

typedef FormId = String;
typedef FieldId = String;
typedef Revision = int;
typedef InteractionId = String;
typedef ProposalId = String;
typedef OperationId = String;

abstract interface class CanonicalSerializable {
  Map<String, Object?> toJson();
}

enum FormValueKind {
  string,
  integer,
  number,
  boolean,
  date,
  choice,
  multiChoice,
}

sealed class FormValue implements CanonicalSerializable {
  const FormValue();
  FormValueKind get kind;
  Object get rawValue;
}

final class StringValue extends FormValue {
  final String value;
  const StringValue(this.value);
  @override
  FormValueKind get kind => FormValueKind.string;
  @override
  String get rawValue => value;
  @override
  Map<String, Object?> toJson() => {'type': 'string', 'value': value};
  @override
  bool operator ==(Object o) =>
      identical(this, o) || o is StringValue && o.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
}

final class IntegerValue extends FormValue {
  final int value;
  const IntegerValue(this.value);
  @override
  FormValueKind get kind => FormValueKind.integer;
  @override
  int get rawValue => value;
  @override
  Map<String, Object?> toJson() => {'type': 'integer', 'value': value};
  @override
  bool operator ==(Object o) =>
      identical(this, o) || o is IntegerValue && o.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
}

final class NumberValue extends FormValue {
  final double value;
  NumberValue(this.value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
  }
  @override
  FormValueKind get kind => FormValueKind.number;
  @override
  double get rawValue => value;
  @override
  Map<String, Object?> toJson() => {'type': 'number', 'value': value};
  @override
  bool operator ==(Object o) =>
      identical(this, o) || o is NumberValue && o.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
}

final class BooleanValue extends FormValue {
  final bool value;
  const BooleanValue(this.value);
  @override
  FormValueKind get kind => FormValueKind.boolean;
  @override
  bool get rawValue => value;
  @override
  Map<String, Object?> toJson() => {'type': 'boolean', 'value': value};
  @override
  bool operator ==(Object o) =>
      identical(this, o) || o is BooleanValue && o.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
}

final class DateValue extends FormValue {
  /// Strict YYYY-MM-DD calendar date. Not DateTime/timestamp.
  final String value;
  DateValue(this.value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw ArgumentError.value(value);
    }
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    if (date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2]) {
      throw ArgumentError.value(value);
    }
  }
  @override
  FormValueKind get kind => FormValueKind.date;
  @override
  String get rawValue => value;
  @override
  Map<String, Object?> toJson() => {'type': 'date', 'value': value};
  @override
  bool operator ==(Object o) =>
      identical(this, o) || o is DateValue && o.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
}

final class ChoiceValue extends FormValue {
  final String optionId;
  ChoiceValue(this.optionId) {
    if (optionId.isEmpty) throw ArgumentError.value(optionId, 'optionId');
  }
  @override
  FormValueKind get kind => FormValueKind.choice;
  @override
  String get rawValue => optionId;
  @override
  Map<String, Object?> toJson() => {'type': 'choice', 'value': optionId};
  @override
  bool operator ==(Object o) =>
      identical(this, o) || o is ChoiceValue && o.optionId == optionId;
  @override
  int get hashCode => Object.hash(kind, optionId);
}

final class MultiChoiceValue extends FormValue {
  final List<String> optionIds;
  MultiChoiceValue(Iterable<String> values)
      : optionIds = List.unmodifiable(canonicalStrings(values, nonEmpty: true));
  @override
  FormValueKind get kind => FormValueKind.multiChoice;
  @override
  List<String> get rawValue => optionIds;
  @override
  Map<String, Object?> toJson() => {'type': 'multi_choice', 'value': optionIds};
  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      o is MultiChoiceValue && jsonEquals(optionIds, o.optionIds);
  @override
  int get hashCode => Object.hashAll([kind, ...optionIds]);
}

abstract final class FormValueCodec {
  static FormValue decode(Object? input) {
    final j = jsonObject(input);
    final value = j['value'];
    try {
      return switch (requiredString(j, 'type')) {
        'string' => StringValue(requireType<String>(value)),
        'integer' => IntegerValue(requireType<int>(value)),
        'number' => NumberValue(requireType<num>(value).toDouble()),
        'boolean' => BooleanValue(requireType<bool>(value)),
        'date' => DateValue(requireType<String>(value)),
        'choice' => ChoiceValue(requireType<String>(value)),
        'multi_choice' => MultiChoiceValue(stringList(value)),
        _ => throw const FormatException('Unknown FormValue type'),
      };
    } on ArgumentError catch (e) {
      throw FormatException('Invalid FormValue: $e');
    }
  }

  static Map<String, Object?> encode(FormValue value) => value.toJson();
}

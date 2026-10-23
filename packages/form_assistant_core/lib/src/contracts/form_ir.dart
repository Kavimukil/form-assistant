import 'canonical_json.dart';
import 'form_value.dart';
import 'structural_contract.dart';

final class FormIR with StructuralContract {
  final String specVersion;
  final FormId id;
  final List<FormField> fields;
  final List<String> requiredCapabilities;
  final Map<String, Object?> extensions;
  FormIR(
      {this.specVersion = protocolSpecVersion,
      required this.id,
      required List<FormField> fields,
      List<String> requiredCapabilities = const [],
      Map<String, Object?> extensions = const {}})
      : fields = List.unmodifiable(fields),
        requiredCapabilities = canonicalStrings(requiredCapabilities),
        extensions = jsonObject(extensions) {
    if (!RegExp(r'^1\.\d+$').hasMatch(specVersion)) {
      throw ArgumentError('Unsupported specVersion');
    }
  }
  @override
  Map<String, Object?> toJson() => {
        'specVersion': specVersion,
        'id': id,
        'fields': fields.map((v) => v.toJson()).toList(),
        'requiredCapabilities': requiredCapabilities,
        'extensions': extensions,
      };
  factory FormIR.fromJson(Object? input) {
    final j = jsonObject(input);
    return FormIR(
      specVersion: requiredString(j, 'specVersion'),
      id: requireType<String>(j['id']),
      fields: requireType<List<Object?>>(j['fields'])
          .map(FormField.fromJson)
          .toList(),
      requiredCapabilities: j.containsKey('requiredCapabilities')
          ? stringList(j['requiredCapabilities'])
          : const [],
      extensions:
          j.containsKey('extensions') ? jsonObject(j['extensions']) : const {},
    );
  }
}

final class FormField with StructuralContract {
  final FieldId id;
  final ValueDefinition value;
  final FieldSemantics semantics;
  final FieldConstraints? constraints;
  final List<FormOption>? options;
  final Map<String, Object?> extensions;
  FormField(
      {required this.id,
      required this.value,
      required this.semantics,
      this.constraints,
      List<FormOption>? options,
      Map<String, Object?> extensions = const {}})
      : options = options == null ? null : List.unmodifiable(options),
        extensions = jsonObject(extensions) {}
  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'value': value.toJson(),
        'semantics': semantics.toJson(),
        if (constraints != null) 'constraints': constraints!.toJson(),
        if (options != null)
          'options': options!.map((v) => v.toJson()).toList(),
        'extensions': extensions,
      };
  factory FormField.fromJson(Object? input) {
    final j = jsonObject(input);
    return FormField(
      id: requireType<String>(j['id']),
      value: ValueDefinition.fromJson(j['value']),
      semantics: FieldSemantics.fromJson(j['semantics']),
      constraints: j.containsKey('constraints')
          ? FieldConstraints.fromJson(j['constraints'])
          : null,
      options: j.containsKey('options')
          ? requireType<List<Object?>>(j['options'])
              .map(FormOption.fromJson)
              .toList()
          : null,
      extensions:
          j.containsKey('extensions') ? jsonObject(j['extensions']) : const {},
    );
  }
}

final class FieldSemantics with StructuralContract {
  final String label;
  final String? description;
  final String? concept;
  final List<String> aliases;
  final Map<String, String> localizedLabels;
  final Map<String, List<String>> localizedAliases;
  FieldSemantics(
      {required this.label,
      this.description,
      this.concept,
      List<String> aliases = const [],
      Map<String, String> localizedLabels = const <String, String>{},
      Map<String, List<String>> localizedAliases =
          const <String, List<String>>{}})
      : aliases = canonicalStrings(aliases),
        localizedLabels = _localeStrings(localizedLabels),
        localizedAliases = _localeAliases(localizedAliases) {}

  /// Display label for [locale]. The field id stays the canonical identity.
  String labelFor(String locale) => _textFor(locale, localizedLabels) ?? label;

  List<String> aliasesFor(String locale) =>
      _aliasesFor(locale, localizedAliases) ?? aliases;

  @override
  Map<String, Object?> toJson() => {
        'label': label,
        if (description != null) 'description': description,
        if (concept != null) 'concept': concept,
        'aliases': aliases,
        if (localizedLabels.isNotEmpty) 'localizedLabels': localizedLabels,
        if (localizedAliases.isNotEmpty)
          'localizedAliases': {
            for (final entry in localizedAliases.entries)
              entry.key: entry.value,
          },
      };
  factory FieldSemantics.fromJson(Object? input) {
    final j = jsonObject(input);
    return FieldSemantics(
      label: requireType<String>(j['label']),
      description: j.containsKey('description')
          ? requireType<String>(j['description'])
          : null,
      concept:
          j.containsKey('concept') ? requireType<String>(j['concept']) : null,
      aliases: j.containsKey('aliases') ? stringList(j['aliases']) : const [],
      localizedLabels: j.containsKey('localizedLabels')
          ? _readLocaleStrings(j['localizedLabels'])
          : const <String, String>{},
      localizedAliases: j.containsKey('localizedAliases')
          ? _readLocaleAliases(j['localizedAliases'])
          : const <String, List<String>>{},
    );
  }
}

final class FieldConstraints with StructuralContract {
  final bool required;
  final num? min;
  final num? max;
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  FieldConstraints(
      {this.required = false,
      this.min,
      this.max,
      this.minLength,
      this.maxLength,
      this.pattern}) {
    if (min != null && !min!.isFinite) throw ArgumentError("Non-finite min");
    if (max != null && !max!.isFinite) throw ArgumentError("Non-finite max");
  }
  @override
  Map<String, Object?> toJson() => {
        'required': required,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (minLength != null) 'minLength': minLength,
        if (maxLength != null) 'maxLength': maxLength,
        if (pattern != null) 'pattern': pattern,
      };
  factory FieldConstraints.fromJson(Object? input) {
    final j = jsonObject(input);
    return FieldConstraints(
      required:
          j.containsKey('required') ? requireType<bool>(j['required']) : false,
      min: j.containsKey('min') ? requireType<num>(j['min']) : null,
      max: j.containsKey('max') ? requireType<num>(j['max']) : null,
      minLength:
          j.containsKey('minLength') ? requireType<int>(j['minLength']) : null,
      maxLength:
          j.containsKey('maxLength') ? requireType<int>(j['maxLength']) : null,
      pattern:
          j.containsKey('pattern') ? requireType<String>(j['pattern']) : null,
    );
  }
}

final class FormOption with StructuralContract {
  final String id;
  final String label;
  final List<String> aliases;
  final Map<String, String> localizedLabels;
  final Map<String, List<String>> localizedAliases;
  final Map<String, Object?> extensions;
  FormOption(
      {required this.id,
      required this.label,
      List<String> aliases = const [],
      Map<String, String> localizedLabels = const <String, String>{},
      Map<String, List<String>> localizedAliases =
          const <String, List<String>>{},
      Map<String, Object?> extensions = const {}})
      : aliases = canonicalStrings(aliases),
        localizedLabels = _localeStrings(localizedLabels),
        localizedAliases = _localeAliases(localizedAliases),
        extensions = jsonObject(extensions) {}

  String labelFor(String locale) => _textFor(locale, localizedLabels) ?? label;

  List<String> aliasesFor(String locale) =>
      _aliasesFor(locale, localizedAliases) ?? aliases;

  /// Id plus the names for [locale]. A localized label replaces the base label
  /// for that locale; the option id remains the written value.
  List<String> namesFor(String locale) {
    final key = _localeKey(locale);
    final language = key.split('-').first;
    final has = localizedLabels.containsKey(key) ||
        localizedLabels.containsKey(language) ||
        localizedAliases.containsKey(key) ||
        localizedAliases.containsKey(language);
    if (!has) return [id, label, ...aliases];
    return [id, labelFor(locale), ...aliasesFor(locale)];
  }

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'aliases': aliases,
        if (localizedLabels.isNotEmpty) 'localizedLabels': localizedLabels,
        if (localizedAliases.isNotEmpty)
          'localizedAliases': {
            for (final entry in localizedAliases.entries)
              entry.key: entry.value,
          },
        'extensions': extensions,
      };
  factory FormOption.fromJson(Object? input) {
    final j = jsonObject(input);
    return FormOption(
      id: requireType<String>(j['id']),
      label: requireType<String>(j['label']),
      aliases: j.containsKey('aliases') ? stringList(j['aliases']) : const [],
      localizedLabels: j.containsKey('localizedLabels')
          ? _readLocaleStrings(j['localizedLabels'])
          : const <String, String>{},
      localizedAliases: j.containsKey('localizedAliases')
          ? _readLocaleAliases(j['localizedAliases'])
          : const <String, List<String>>{},
      extensions:
          j.containsKey('extensions') ? jsonObject(j['extensions']) : const {},
    );
  }
}

sealed class ValueDefinition with StructuralContract {
  const ValueDefinition();
  factory ValueDefinition.fromJson(Object? input) {
    final j = jsonObject(input);
    return switch (requiredString(j, 'type')) {
      'string' => const StringDefinition(),
      'integer' => const IntegerDefinition(),
      'number' => const NumberDefinition(),
      'boolean' => const BooleanDefinition(),
      'date' => const DateDefinition(),
      'choice' => ChoiceDefinition(multiple: requireType<bool>(j['multiple'])),
      _ => throw const FormatException('Unknown value definition'),
    };
  }
}

final class StringDefinition extends ValueDefinition {
  const StringDefinition();
  @override
  Map<String, Object?> toJson() => {'type': 'string'};
}

final class IntegerDefinition extends ValueDefinition {
  const IntegerDefinition();
  @override
  Map<String, Object?> toJson() => {'type': 'integer'};
}

final class NumberDefinition extends ValueDefinition {
  const NumberDefinition();
  @override
  Map<String, Object?> toJson() => {'type': 'number'};
}

final class BooleanDefinition extends ValueDefinition {
  const BooleanDefinition();
  @override
  Map<String, Object?> toJson() => {'type': 'boolean'};
}

final class DateDefinition extends ValueDefinition {
  const DateDefinition();
  @override
  Map<String, Object?> toJson() => {'type': 'date'};
}

final class ChoiceDefinition extends ValueDefinition {
  final bool multiple;
  const ChoiceDefinition({required this.multiple});
  @override
  Map<String, Object?> toJson() => {'type': 'choice', 'multiple': multiple};
}

String _localeKey(String locale) {
  final key = locale.trim().replaceAll('_', '-').toLowerCase();
  if (key.isEmpty) throw ArgumentError('Invalid locale');
  return key;
}

Map<String, String> _localeStrings(Map<String, String> input) {
  final out = <String, String>{};
  for (final entry in input.entries) {
    if (entry.value.trim().isEmpty) {
      throw ArgumentError('Empty localized label');
    }
    out[_localeKey(entry.key)] = entry.value;
  }
  final keys = out.keys.toList()..sort();
  return Map.unmodifiable({for (final key in keys) key: out[key]!});
}

Map<String, List<String>> _localeAliases(Map<String, List<String>> input) {
  final out = <String, List<String>>{};
  for (final entry in input.entries) {
    final aliases = canonicalStrings(entry.value);
    if (aliases.isEmpty) throw ArgumentError('Empty localized aliases');
    out[_localeKey(entry.key)] = aliases;
  }
  final keys = out.keys.toList()..sort();
  return Map.unmodifiable({for (final key in keys) key: out[key]!});
}

Map<String, String> _readLocaleStrings(Object? input) {
  final raw = jsonObject(input);
  return _localeStrings({
    for (final entry in raw.entries) entry.key: requireType<String>(entry.value)
  });
}

Map<String, List<String>> _readLocaleAliases(Object? input) {
  final raw = jsonObject(input);
  return _localeAliases(
      {for (final entry in raw.entries) entry.key: stringList(entry.value)});
}

String? _textFor(String locale, Map<String, String> labels) {
  final key = _localeKey(locale);
  return labels[key] ?? labels[key.split('-').first];
}

List<String>? _aliasesFor(String locale, Map<String, List<String>> aliases) {
  final key = _localeKey(locale);
  return aliases[key] ?? aliases[key.split('-').first];
}

abstract final class FormIRCodec {
  static FormIR decode(Object? input) {
    try {
      return FormIR.fromJson(input);
    } on ArgumentError catch (e) {
      throw FormatException('Invalid FormIR: $e');
    }
  }

  static Map<String, Object?> encode(FormIR form) => form.toJson();
}

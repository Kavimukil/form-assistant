import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

void main() {
  final values = <FormValue>[
    const StringValue('  MiXeD  '),
    const IntegerValue(4),
    NumberValue(4.0),
    const BooleanValue(true),
    DateValue('2024-02-29'),
    ChoiceValue('canonical_id'),
    MultiChoiceValue(['z', 'a', 'z']),
  ];
  final actions = <FormAction>[
    for (final v in values) SetValueAction(fieldId: 'field', value: v),
    const ClearValueAction(fieldId: 'field'),
    const NavigateAction(target: FieldNavigationTarget(fieldId: 'field')),
    const NavigateAction(target: NextNavigationTarget()),
    const NavigateAction(target: PreviousNavigationTarget()),
    for (final reason in ClarificationReason.values)
      RequestClarificationAction(fieldIds: ['z', 'a', 'z'], reason: reason),
  ];
  for (final v in values) {
    test('value round trip ${v.kind}', () {
      final result = FormValueCodec.decode(jsonDecode(jsonEncode(v.toJson())));
      expect(result, v);
      expect(result.hashCode, v.hashCode);
    });
  }
  for (var i = 0; i < actions.length; i++) {
    test('action round trip $i', () {
      final a = actions[i];
      final result = FormActionCodec.decode(jsonDecode(jsonEncode(a.toJson())));
      expect(result, a);
      expect(result.hashCode, a.hashCode);
      expect(result.classification, a.classification);
    });
  }
  test('canonical golden values/actions', () {
    final golden =
        jsonDecode(File('test/fixtures/contracts.json').readAsStringSync());
    expect({
      'values': values.map((v) => v.toJson()).toList(),
      'actions': actions.map((a) => a.toJson()).toList()
    }, golden);
  });
  test('value invariants', () {
    expect(const IntegerValue(4), isNot(NumberValue(4)));
    expect((values.first as StringValue).value, '  MiXeD  ');
    for (final n in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(() => NumberValue(n), throwsArgumentError);
      expect(() => FormValueCodec.decode({'type': 'number', 'value': n}),
          throwsFormatException);
    }
    for (final d in [
      '2023-02-29',
      '1900-02-29',
      '2024-04-31',
      '2024-00-01',
      '2024-13-01',
      '2024-01-00',
      '2024-1-01',
      '2024-01-01T00:00:00Z'
    ]) {
      expect(() => DateValue(d), throwsArgumentError);
      expect(() => FormValueCodec.decode({'type': 'date', 'value': d}),
          throwsFormatException);
    }
    expect(DateValue('2000-02-29').value, '2000-02-29');
    expect(() => ChoiceValue(''), throwsArgumentError);
    final multi = MultiChoiceValue(['z', 'a', 'z']);
    expect(multi.optionIds, ['a', 'z']);
    expect(multi, MultiChoiceValue(['a', 'z']));
    expect(() => multi.optionIds.add('x'), throwsUnsupportedError);
  });
  test('malformed values rejected without coercion', () {
    for (final bad in [
      null,
      <Object?>[],
      <String, Object?>{},
      {'type': 'unknown', 'value': 1},
      {'type': 'integer', 'value': '4'},
      {'type': 'integer', 'value': 4.0},
      {'type': 'string', 'value': true},
      {'type': 'boolean', 'value': 1},
      {'type': 'number', 'value': '4'},
      {'type': 'choice', 'value': ''},
      {
        'type': 'multi_choice',
        'value': ['']
      },
      {
        'type': 'multi_choice',
        'value': [1]
      }
    ]) {
      expect(() => FormValueCodec.decode(bad), throwsFormatException);
    }
  });
  test('malformed actions and targets rejected', () {
    for (final bad in [
      null,
      <String, Object?>{},
      {'type': 'unknown'},
      {'type': 'set_value', 'fieldId': 'f'},
      {'type': 'clear_value', 'fieldId': 4},
      {'type': 'clear_value', 'fieldId': ''},
      {
        'type': 'navigate',
        'target': {'type': 'unknown'}
      },
      {'type': 'request_clarification', 'reason': 'unknown'},
      {'type': 'request_clarification', 'reason': 'ambiguous', 'detail': null},
      {
        'type': 'request_clarification',
        'reason': 'ambiguous',
        'fieldIds': [4]
      }
    ]) {
      expect(() => FormActionCodec.decode(bad), throwsFormatException);
    }
    expect(
        FormActionCodec.decode(
            {'type': 'clear_value', 'fieldId': 'f', 'future': true}),
        const ClearValueAction(fieldId: 'f'));
    expect(actions.first.classification, ActionClassification.mutation);
    expect(actions[8].classification, ActionClassification.navigation);
    expect(actions.last.classification, ActionClassification.assistantControl);
  });
  test('JSON safety, cycles, copying and map order equality', () {
    final cyclic = <Object?>[];
    cyclic.add(cyclic);
    for (final bad in [
      Object(),
      {1: 'bad'},
      double.nan,
      {
        'deep': [Object()]
      },
      cyclic
    ]) {
      expect(() => validateJsonSafe(bad), throwsFormatException);
    }
    expect(
        jsonEquals({
          'a': 1,
          'b': [true]
        }, {
          'b': [true],
          'a': 1
        }),
        isTrue);
    expect(
        jsonHash({
          'a': 1,
          'b': [true]
        }),
        jsonHash({
          'b': [true],
          'a': 1
        }));
  });
  test('validation metadata round trip, immutability, optional omission', () {
    final source = <String, Object?>{
      'nested': <Object?>[true, null, 3]
    };
    final issue = ValidationIssue(
        code: 'value.type_mismatch',
        severity: ValidationSeverity.error,
        metadata: source);
    (source['nested'] as List<Object?>).clear();
    expect(issue.metadata['nested'], [true, null, 3]);
    expect(() => (issue.metadata['nested'] as List<Object?>).add(4),
        throwsUnsupportedError);
    expect(issue.toJson().containsKey('fieldId'), isFalse);
    for (final status in ValidationStatus.values) {
      final m = ActionValidationMetadata(
          status: status, issues: [issue], validatedAgainstRevision: 7);
      final decoded = ActionValidationMetadata.fromJson(m.toJson());
      expect(decoded, m);
      expect(decoded.hashCode, m.hashCode);
      expect(decoded.validatedAgainstRevision, 7);
      expect(decoded.issues.clear, throwsUnsupportedError);
    }
    expect(
        () => ValidationIssue(
            code: 'x',
            severity: ValidationSeverity.info,
            metadata: {'bad': Object()}),
        throwsFormatException);
  });
  test(
      'FormIR golden, all definitions, extensions, compatibility and immutability',
      () {
    final input =
        jsonDecode(File('test/fixtures/form_ir.json').readAsStringSync());
    final ir = FormIRCodec.decode(input);
    expect(ir.toJson(), input);
    final other = FormIRCodec.decode(ir.toJson());
    expect(other, ir);
    expect(other.hashCode, ir.hashCode);
    expect(ir.specVersion, protocolSpecVersion);
    expect(ir.fields.clear, throwsUnsupportedError);
    expect(ir.extensions.clear, throwsUnsupportedError);
    expect(() => ir.fields.first.semantics.aliases.clear(),
        throwsUnsupportedError);
    expect(() => ir.fields.last.options!.clear(), throwsUnsupportedError);
    final future = Map<String, Object?>.from(ir.toJson())
      ..['specVersion'] = '1.1'
      ..['optionalFuture'] = true;
    expect(FormIRCodec.decode(future).specVersion, '1.1');
    for (final change in [
      {'specVersion': '2.0'},
      {'fields': true},
      {'id': 1},
      {
        'extensions': {'bad': Object()}
      },
      {
        'fields': [
          {
            'id': 'x',
            'value': {'type': 'object'},
            'semantics': {'label': 'x'}
          }
        ]
      }
    ]) {
      expect(() => FormIRCodec.decode({...ir.toJson(), ...change}),
          throwsFormatException);
    }
  });
  test('metadata golden and strict envelope types', () {
    final fixture =
        jsonDecode(File('test/fixtures/validation.json').readAsStringSync());
    final metadata = ActionValidationMetadata.fromJson(fixture);
    expect(metadata.toJson(), fixture);
    for (final bad in [
      {'status': 'unknown'},
      {'status': 'valid', 'validatedAgainstRevision': '7'},
      {
        'status': 'valid',
        'issues': [
          {'code': 'x', 'severity': 'unknown'}
        ]
      },
      {
        'status': 'valid',
        'issues': [
          {'code': 4, 'severity': 'error'}
        ]
      },
    ]) {
      expect(
          () => ActionValidationMetadata.fromJson(bad), throwsFormatException);
    }
  });
  test(
      'FormIR required version, malformed nested contracts and defensive copies',
      () {
    final fields = <FormField>[];
    final ir = FormIR(id: 'f', fields: fields);
    fields.add(FormField(
        id: 'x',
        value: const ChoiceDefinition(multiple: false),
        semantics: FieldSemantics(label: 'Choice')));
    expect(ir.fields, isEmpty);
    final missingVersion = ir.toJson()..remove('specVersion');
    expect(() => FormIRCodec.decode(missingVersion), throwsFormatException);
    for (final definition in [
      const ChoiceDefinition(multiple: false),
      const ChoiceDefinition(multiple: true)
    ]) {
      expect(ValueDefinition.fromJson(definition.toJson()), definition);
    }
    for (final invalid in [
      {'required': 'true'},
      {'min': '1'},
      {'max': double.infinity},
      {'minLength': 1.5},
      {'pattern': false},
    ]) {
      expect(() => FieldConstraints.fromJson(invalid), throwsFormatException);
    }
    final constraints = FieldConstraints(
        required: true,
        min: 1,
        max: 9,
        minLength: 1,
        maxLength: 9,
        pattern: 'x');
    expect(FieldConstraints.fromJson(constraints.toJson()), constraints);
    final aliases = ['z', 'a', 'z'];
    final semantics = FieldSemantics(
        label: 'Label',
        description: 'Description',
        concept: 'concept_id',
        aliases: aliases);
    aliases.clear();
    expect(semantics.aliases, ['a', 'z']);
    expect(FieldSemantics.fromJson(semantics.toJson()), semantics);
    final clarification =
        RequestClarificationAction(reason: ClarificationReason.ambiguous);
    expect(clarification.toJson().containsKey('detail'), isFalse);
    expect(clarification.toJson().containsKey('fieldIds'), isFalse);
    expect(() => clarification.fieldIds.add('x'), throwsUnsupportedError);
  });
}

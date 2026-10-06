import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_core/src/runtime/context_compiler.dart';
import 'package:test/test.dart';

void main() {
  final field = FormField(
      id: 'age',
      value: const IntegerDefinition(),
      semantics: FieldSemantics(label: 'Age'));
  SemanticContext context(
          {int revision = 17,
          int value = 31,
          bool writable = true,
          String locale = 'en_IN'}) =>
      SemanticContext(
          formId: 'f',
          revision: revision,
          activeFieldId: 'age',
          fields: [FormFieldContext(field: field, writable: writable)],
          values: {'age': IntegerValue(value)},
          locale: locale);
  test('v1.1 round trip preserves typed current value and legacy accessors',
      () {
    final c = context();
    final decoded = SemanticContext.fromJson(c.toJson());
    expect(decoded.toJson(), c.toJson());
    expect(decoded.fields.single.currentValue, const IntegerValue(31));
    expect(decoded.values['age'], decoded.fields.single.currentValue);
    expect(decoded.locale, 'en-in');
    expect(
        () => SemanticContext.fromJson({...c.toJson(), 'specVersion': '1.0'}),
        throwsFormatException);
    expect(
        () => SemanticContext.fromJson(
            {...c.toJson(), 'fingerprint': 'tampered'}),
        throwsFormatException);
  });
  test('semantic identity includes values/writable/locale, excludes revision',
      () {
    expect(context().fingerprint, context(revision: 18).fingerprint);
    expect(context().fingerprint, isNot(context(value: 32).fingerprint));
    expect(context().fingerprint, isNot(context(writable: false).fingerprint));
    expect(context().fingerprint, isNot(context(locale: 'fr').fingerprint));
  });
  test('compiler caps aliases/options and projects read-only lifecycle', () {
    final f = FormIR(id: 'f', fields: [
      FormField(
          id: 'choice',
          value: const ChoiceDefinition(multiple: false),
          semantics: FieldSemantics(
              label: 'Choice', aliases: List.generate(20, (i) => 'alias$i')),
          options: List.generate(
              50, (i) => FormOption(id: 'o$i', label: 'Option $i')))
    ]);
    final result = ContextCompiler(
            form: f,
            budget: ContextBudget(maxAliasesPerField: 2, maxOptionsPerField: 3))
        .compile(
            snapshot: FormStateSnapshot(
                formId: 'f',
                revision: 17,
                values: {},
                activeFieldId: 'choice',
                lifecycle: FormLifecycle.readOnly),
            input: const UserInput(text: 'hello'));
    final c = result.context;
    expect(c.revision, 17);
    expect(c.fields.single.writable, false);
    expect(c.fields.single.aliases, hasLength(2));
    expect(c.fields.single.options, hasLength(3));
    expect(c.fields.single.optionsTruncated, true);
    expect(SemanticContext.fromJson(c.toJson()).fingerprint, c.fingerprint);
  });
}

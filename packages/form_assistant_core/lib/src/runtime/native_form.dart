import '../contracts/form_action.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_state.dart';
import '../contracts/form_state_bridge.dart';
import '../contracts/form_value.dart';
import '../contracts/intelligence.dart';
import '../contracts/trace.dart';
import '../contracts/validation_metadata.dart';

/// The target field is visible only when [whenFieldId] currently equals [equals].
final class FieldVisibilityRule {
  final FieldId fieldId;
  final FieldId whenFieldId;
  final FormValue equals;
  const FieldVisibilityRule(
      {required this.fieldId, required this.whenFieldId, required this.equals});
}

/// Ordered groups of canonical field ids. Every field appears in one step.
final class FormWorkflow {
  final List<List<FieldId>> steps;
  FormWorkflow(List<List<FieldId>> steps)
      : steps = List.unmodifiable(
            [for (final step in steps) List<FieldId>.unmodifiable(step)]);

  int get length => steps.length;
}

/// A field as the renderer should paint it. Values stay canonical.
final class NativeFieldView {
  final FieldId id;
  final String label;
  final bool visible;
  final bool required;
  final FormValue? value;
  final int stepIndex;
  const NativeFieldView(
      {required this.id,
      required this.label,
      required this.visible,
      required this.required,
      required this.value,
      required this.stepIndex});
}

/// Projection of a native form at one snapshot. This is not a widget.
final class NativeFormView {
  final int stepIndex;
  final int stepCount;
  final List<NativeFieldView> fields;
  NativeFormView(
      {required this.stepIndex,
      required this.stepCount,
      required List<NativeFieldView> fields})
      : fields = List.unmodifiable(fields);

  List<NativeFieldView> get currentFields => List.unmodifiable(
      fields.where((field) => field.visible && field.stepIndex == stepIndex));
}

/// True when any visibility rule for [fieldId] fails against [snapshot].
bool fieldIsHidden(FieldId fieldId, FormStateSnapshot snapshot,
    Iterable<FieldVisibilityRule> rules) {
  for (final rule in rules) {
    if (rule.fieldId != fieldId) continue;
    if (snapshot.values[rule.whenFieldId] != rule.equals) return true;
  }
  return false;
}

/// Canonical form plus visibility rules and a step workflow.
///
/// No new value types are introduced. The local bridge remains the state.
final class NativeForm {
  final FormIR form;
  final List<FieldVisibilityRule> rules;
  final FormWorkflow workflow;
  NativeForm(
      {required this.form,
      List<FieldVisibilityRule> rules = const [],
      FormWorkflow? workflow})
      : rules = List.unmodifiable(rules),
        workflow = workflow ??
            FormWorkflow([
              [for (final field in form.fields) field.id]
            ]) {
    final ids = form.fields.map((field) => field.id).toSet();
    if (ids.length != form.fields.length) {
      throw ArgumentError('Duplicate form field id');
    }
    for (final rule in this.rules) {
      if (rule.fieldId == rule.whenFieldId ||
          !ids.contains(rule.fieldId) ||
          !ids.contains(rule.whenFieldId)) {
        throw ArgumentError('Visibility rule references an invalid field');
      }
    }
    final seen = <FieldId>{};
    if (this.workflow.steps.isEmpty) {
      throw ArgumentError('Workflow has no steps');
    }
    for (final step in this.workflow.steps) {
      if (step.isEmpty) {
        throw ArgumentError('Workflow step is empty');
      }
      for (final id in step) {
        if (!ids.contains(id) || !seen.add(id)) {
          throw ArgumentError('Workflow field $id is missing or repeated');
        }
      }
    }
    if (seen.length != ids.length) {
      throw ArgumentError('Workflow does not cover every field');
    }
  }

  NativeFormView project(FormStateSnapshot snapshot, {String locale = 'en'}) {
    if (snapshot.formId != form.id) {
      throw ArgumentError('Snapshot is for a different form');
    }
    final stepOf = <FieldId, int>{};
    for (var index = 0; index < workflow.length; index++) {
      for (final id in workflow.steps[index]) {
        stepOf[id] = index;
      }
    }
    final fields = <NativeFieldView>[
      for (final field in form.fields)
        NativeFieldView(
            id: field.id,
            label: field.semantics.labelFor(locale),
            visible: !fieldIsHidden(field.id, snapshot, rules),
            required: field.constraints?.required ?? false,
            value: snapshot.values[field.id],
            stepIndex: stepOf[field.id]!),
    ];
    return NativeFormView(
        stepIndex: _stepIndex(fields),
        stepCount: workflow.length,
        fields: fields);
  }

  int _stepIndex(List<NativeFieldView> fields) {
    for (var index = 0; index < workflow.length; index++) {
      final incomplete = fields.any((field) =>
          field.stepIndex == index &&
          field.visible &&
          field.required &&
          field.value == null);
      if (incomplete) return index;
    }
    for (var index = workflow.length - 1; index >= 0; index--) {
      if (fields.any((field) => field.stepIndex == index && field.visible)) {
        return index;
      }
    }
    return 0;
  }
}

/// A manual edit proposal. [FormAssistantRuntime.commitNative] runs it through
/// the same action path as an accepted model proposal.
ActionProposal nativeManualProposal(
    {required FormAction action,
    required FormStateSnapshot basedOn,
    required TraceContext trace}) {
  final id = '${trace.requestId}/native';
  return ActionProposal(
      id: id,
      baseRevision: basedOn.revision,
      actions: [ProposedAction(id: '$id/action', action: action)],
      provenance: ActionProvenance(
          trace: trace,
          adapterId: 'native_form',
          adapterVersion: '0.1.0',
          origin: ActionOrigin.user));
}

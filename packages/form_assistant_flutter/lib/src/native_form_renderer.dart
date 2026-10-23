import 'dart:async';

import 'package:flutter/material.dart' hide FormField;
import 'package:form_assistant_core/form_assistant_core.dart';

/// Paints a [NativeFormView]. Edits leave through [onAction] so manual input
/// uses the same runtime path as an accepted proposal. This widget has no model.
class NativeFormRenderer extends StatefulWidget {
  final NativeForm form;
  final FormStateBridge bridge;
  final Future<void> Function(FormAction action) onAction;
  final String locale;
  const NativeFormRenderer(
      {super.key,
      required this.form,
      required this.bridge,
      required this.onAction,
      this.locale = 'en'});

  @override
  State<NativeFormRenderer> createState() => _NativeFormRendererState();
}

class _NativeFormRendererState extends State<NativeFormRenderer> {
  final Map<FieldId, TextEditingController> _text = {};
  StreamSubscription<FormStateBridgeEvent>? _events;

  @override
  void initState() {
    super.initState();
    for (final field in widget.form.form.fields) {
      if (_isText(field)) {
        _text[field.id] = TextEditingController(
            text: _display(widget.bridge.snapshot.values[field.id]));
      }
    }
    _events = widget.bridge.events.listen((_) {
      if (!mounted) return;
      _syncText();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _isText(FormField field) => switch (field.value) {
        BooleanDefinition() => false,
        ChoiceDefinition() => false,
        _ => true,
      };

  String _display(FormValue? value) => switch (value) {
        StringValue(:final value) => value,
        IntegerValue(:final value) => '$value',
        NumberValue(:final value) => '$value',
        DateValue(:final value) => value,
        _ => '',
      };

  void _syncText() {
    final snapshot = widget.bridge.snapshot;
    for (final entry in _text.entries) {
      final next = _display(snapshot.values[entry.key]);
      if (entry.value.text != next) entry.value.text = next;
    }
  }

  FormValue? _parse(FormField field, String text) {
    try {
      return switch (field.value) {
        StringDefinition() => StringValue(text),
        IntegerDefinition() =>
          int.tryParse(text) == null ? null : IntegerValue(int.parse(text)),
        NumberDefinition() => double.tryParse(text) == null
            ? null
            : NumberValue(double.parse(text)),
        DateDefinition() => DateValue(text),
        _ => null,
      };
    } on ArgumentError {
      return null;
    }
  }

  void _commitText(FormField field) {
    final text = _text[field.id]?.text ?? '';
    final current = widget.bridge.snapshot.values[field.id];
    if (text.isEmpty) {
      if (current != null) {
        widget.onAction(ClearValueAction(fieldId: field.id));
      }
      return;
    }
    final value = _parse(field, text);
    if (value == null || value == current) return;
    widget.onAction(SetValueAction(fieldId: field.id, value: value));
  }

  @override
  Widget build(BuildContext context) {
    final view =
        widget.form.project(widget.bridge.snapshot, locale: widget.locale);
    final byId = {for (final field in widget.form.form.fields) field.id: field};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Step ${view.stepIndex + 1} of ${view.stepCount}',
          key: const Key('native_step')),
      for (final field in view.currentFields) _control(byId[field.id]!, field),
    ]);
  }

  Widget _control(FormField field, NativeFieldView view) {
    final definition = field.value;
    if (definition is BooleanDefinition) {
      final checked = view.value == const BooleanValue(true);
      return SwitchListTile(
          key: Key('native_field_${field.id}'),
          title: Text(view.label),
          value: checked,
          onChanged: (selected) {
            widget.onAction(SetValueAction(
                fieldId: field.id, value: BooleanValue(selected)));
          });
    }
    if (definition is ChoiceDefinition && !definition.multiple) {
      final selected = view.value is ChoiceValue
          ? (view.value as ChoiceValue).optionId
          : null;
      return DropdownButtonFormField<String>(
          key: Key('native_field_${field.id}'),
          initialValue: selected,
          decoration: InputDecoration(labelText: view.label),
          items: [
            for (final option in field.options ?? const <FormOption>[])
              DropdownMenuItem(value: option.id, child: Text(option.label)),
          ],
          onChanged: (id) {
            if (id == null) return;
            widget.onAction(
                SetValueAction(fieldId: field.id, value: ChoiceValue(id)));
          });
    }
    if (definition is ChoiceDefinition && definition.multiple) {
      final selected = view.value is MultiChoiceValue
          ? (view.value as MultiChoiceValue).optionIds.toSet()
          : <String>{};
      return Column(children: [
        Text(view.label),
        for (final option in field.options ?? const <FormOption>[])
          CheckboxListTile(
              key: Key('native_option_${field.id}_${option.id}'),
              title: Text(option.label),
              value: selected.contains(option.id),
              onChanged: (checked) {
                final next = {...selected};
                if (checked ?? false) {
                  next.add(option.id);
                } else {
                  next.remove(option.id);
                }
                widget.onAction(SetValueAction(
                    fieldId: field.id,
                    value: MultiChoiceValue(next.toList()..sort())));
              }),
      ]);
    }
    return TextFormField(
        key: Key('native_field_${field.id}'),
        controller: _text[field.id],
        decoration: InputDecoration(labelText: view.label),
        onEditingComplete: () => _commitText(field));
  }
}

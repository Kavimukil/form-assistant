import 'dart:async';

import 'package:flutter/material.dart';
import 'package:form_assistant_external_example/existing_form_store.dart';

/// Source form field. Accent is optional decoration from the host app.
class ExistingAgeForm extends StatefulWidget {
  final ExistingFormStore store;
  final Color? accent;
  const ExistingAgeForm({super.key, required this.store, this.accent});

  static const fieldKey = Key('existing_age_field');

  @override
  State<ExistingAgeForm> createState() => _ExistingAgeFormState();
}

class _ExistingAgeFormState extends State<ExistingAgeForm> {
  late final TextEditingController _text;
  StreamSubscription<Object>? _storeEvents;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _stored());
    _storeEvents = widget.store.changes.listen((_) {
      if (!mounted) return;
      final stored = _stored();
      if (_text.text != stored) _text.text = stored;
      setState(() {});
    });
  }

  String _stored() => widget.store.snapshot.state.answers['AGE']?.toString() ?? '';

  @override
  void dispose() {
    _storeEvents?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return TextFormField(
        key: ExistingAgeForm.fieldKey,
        controller: _text,
        decoration: InputDecoration(
            labelText: 'Age',
            enabledBorder: accent == null
                ? null
                : OutlineInputBorder(borderSide: BorderSide(color: accent))),
        onChanged: (value) => widget.store.manualSet('AGE', value));
  }
}

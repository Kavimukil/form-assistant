import 'package:flutter/material.dart';
import 'package:flutter_existing_form/existing_age_form.dart';
import 'package:form_assistant_external_example/existing_form_store.dart';
import 'package:form_assistant_flutter/form_assistant_flutter.dart';

/// Voice and clarification chrome beside the existing age field.
class AssistantShell extends StatelessWidget {
  final ExistingFormStore store;
  final FormAssistantController controller;
  const AssistantShell(
      {super.key, required this.store, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AssistantChrome(
        controller: controller,
        buildForm: (_) =>
            ExistingAgeForm(store: store, accent: controller.accentFor('age')));
  }
}

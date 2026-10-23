import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_existing_form/existing_age_form.dart';
import 'package:form_assistant_external_example/existing_form_store.dart';

void main() {
  testWidgets('the existing form edits its store with no assistant package',
      (tester) async {
    final store = ExistingFormStore();
    addTearDown(() => _settle(store.dispose()));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ExistingAgeForm(store: store))));
    await tester.enterText(find.byKey(ExistingAgeForm.fieldKey), '41');
    expect(store.snapshot.state.answers['AGE'], '41');
    expect(find.byType(TextFormField), findsOneWidget);
  });
}

/// Widget-test tearDown runs after the fake-async flush, so dispose futures
/// would otherwise never complete.
Future<void> _settle(Future<void> pending) async {
  final binding = WidgetsBinding.instance;
  if (binding is TestWidgetsFlutterBinding && binding.inTest) {
    binding.asyncBarrier();
  }
  await pending;
}

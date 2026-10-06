import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/form_assistant_function_gemma.dart'
    hide FunctionGemmaAdapter;
import 'package:form_assistant_function_gemma/src/legacy_adapter.dart'
    show FunctionGemmaAdapter;

FormIR evaluationForm() => FormIR(id: 'profile', fields: [
      FormField(
          id: 'age',
          value: const IntegerDefinition(),
          semantics: FieldSemantics(label: 'Age'),
          constraints: FieldConstraints(min: 0, max: 120)),
      FormField(
          id: 'consent',
          value: const BooleanDefinition(),
          semantics: FieldSemantics(label: 'Consent')),
      FormField(
          id: 'name',
          value: const StringDefinition(),
          semantics: FieldSemantics(label: 'Name')),
    ]);
Map<String, FormValue> values(Object? input) =>
    (input as Map<String, dynamic>).map((id, value) => MapEntry(
        id,
        id == 'age'
            ? IntegerValue(value as int) as FormValue
            : BooleanValue(value as bool)));
Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final index = args.indexOf(name);
    return index < 0 ? fallback : args[index + 1];
  }

  final binary = option('--binary', 'llama-completion');
  final model = File(option('--model', '../../functiongemma-270m-it-q8_0.gguf'))
      .absolute
      .path;
  final report =
      File(option('--report', '../../docs/evaluation/P6_GGUF_EVALUATION.json'));
  final category = option('--category', 'all');
  final sha = await Process.run('sha256sum', [model]);
  if (sha.exitCode != 0) throw StateError('Cannot read model');
  final version = await Process.run(binary, ['--version']);
  final fixtures =
      jsonDecode(await File('test/fixtures/evaluation.json').readAsString())
          as List<dynamic>;
  final cases = <Map<String, Object?>>[];
  for (final raw in fixtures) {
    final fixture = raw as Map<String, dynamic>;
    final name = fixture['category'] as String;
    if (category != 'all' && category != name) continue;
    final generations = <Map<String, Object?>>[];
    final directory =
        await Directory.systemTemp.createTemp('form-assistant-eval-');
    final form = evaluationForm();
    final bridge = LocalFormStateBridge(
        form: form,
        initialValues: values(fixture['initial']),
        activeFieldId: 'age');
    final adapter =
        FunctionGemmaAdapter(inference: (prompt, cancellation) async {
      final promptFile =
          File('${directory.path}/prompt-${generations.length}.txt');
      await promptFile.writeAsString(prompt);
      cancellation.throwIfCancelled();
      final flags = [
        '-m',
        model,
        '-f',
        promptFile.path,
        '-no-cnv',
        '--no-display-prompt',
        '--no-escape',
        '--special',
        '--temp',
        '0',
        '--seed',
        '42',
        '--threads',
        '1',
        '--ctx-size',
        '8192',
        '--n-predict',
        '512',
        '--no-warmup',
        '--reverse-prompt',
        '<start_function_response>'
      ];
      final watch = Stopwatch()..start();
      final process = await Process.start(binary, flags);
      final detach = cancellation.listen(process.kill);
      try {
        final stdoutFuture = process.stdout.transform(utf8.decoder).join();
        final stderrFuture = process.stderr.transform(utf8.decoder).join();
        final code = await process.exitCode;
        final rawOutput = await stdoutFuture;
        // llama-completion appends this UI marker; it is not a model token.
        final output = rawOutput
            .replaceFirst(RegExp(r' \[end of text\]\s*$'), '')
            .replaceFirst(RegExp(r'<start_function_response>\s*$'), '');
        final stderr = await stderrFuture;
        generations.add({
          'prompt': prompt,
          'output': output,
          'transportOutput': rawOutput,
          'stderr': stderr,
          'exitCode': code,
          'durationMs': watch.elapsedMilliseconds
        });
        cancellation.throwIfCancelled();
        if (code != 0) {
          throw StateError('llama-completion failed ($code): $stderr');
        }
        return FunctionGemmaOutput(output);
      } finally {
        detach();
      }
    });
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: adapter);
    final events = <RuntimeEvent>[];
    runtime.events.listen(events.add);
    final watch = Stopwatch()..start();
    try {
      final result = await runtime.submit(
          UserInput(text: fixture['input'] as String),
          trace: TraceContext(
              interactionId: name,
              requestId: '$name/request',
              operationId: '$name/operation'),
          contextFieldIds: ['age', 'consent', 'name'],
          options: const IntelligenceOptions(timeout: Duration(minutes: 2)));
      final expected = values(fixture['expected']);
      final stateCorrect = result.snapshot.values.length == expected.length &&
          expected.entries
              .every((e) => result.snapshot.values[e.key] == e.value);
      final clarificationCorrect =
          (runtime.state.phase == RuntimePhase.awaitingClarification) ==
              fixture['clarification'];
      final passed =
          stateCorrect && clarificationCorrect && result.errorCode == null;
      cases.add({
        'category': name,
        'passed': passed,
        'stateCorrect': stateCorrect,
        'clarificationCorrect': clarificationCorrect,
        'expectedValues': fixture['expected'],
        'actualValues':
            result.snapshot.values.map((id, v) => MapEntry(id, v.toJson())),
        'proposedActions': result.proposal?.actions
                .map((a) => {'id': a.id, 'action': a.action.toJson()})
                .toList() ??
            [],
        'expectedClarification': fixture['clarification'],
        'phase': runtime.state.phase.name,
        'errorCode': result.errorCode,
        'durationMs': watch.elapsedMilliseconds,
        'qualityReasons': events
            .whereType<IntelligenceQualityEvaluated>()
            .map((e) => e.reason)
            .toList(),
        'generations': generations
      });
      stdout.writeln(
          '$name: ${passed ? 'PASS' : 'FAIL'} (state=$stateCorrect, clarification=$clarificationCorrect, error=${result.errorCode})');
    } finally {
      await runtime.dispose();
      await bridge.dispose();
      await directory.delete(recursive: true);
    }
  }
  final passed = cases.where((c) => c['passed'] == true).length;
  final result = {
    'model': model,
    'modelSha256': (sha.stdout as String).split(' ').first,
    'runnerVersion': '${version.stdout}${version.stderr}'.trim(),
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sampling': {
      'temperature': 0,
      'seed': 42,
      'threads': 1,
      'contextTokens': 8192,
      'maxOutputTokens': 512,
      'stop': '<start_function_response>'
    },
    'fineTuned': false,
    'scriptedOutputs': false,
    'passed': passed,
    'total': cases.length,
    'finalStateAccuracy': cases.isEmpty
        ? 0
        : cases.where((c) => c['stateCorrect'] == true).length / cases.length,
    'completeCaseAccuracy': cases.isEmpty ? 0 : passed / cases.length,
    'cases': cases
  };
  await report.parent.create(recursive: true);
  await report
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  stdout.writeln(
      'Live model evaluation: $passed/${cases.length}; report ${report.path}');
  if (cases.isEmpty || passed != cases.length) exitCode = 1;
}

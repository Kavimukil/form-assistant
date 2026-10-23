// Standalone experiment; does not alter the production adapter or Phase 6R.
import 'dart:convert';
import 'dart:io';

import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/src/format.dart';
import 'package:form_assistant_function_gemma/src/tools/schema.dart';
import 'package:form_assistant_function_gemma/src/tools/parser.dart';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';
import 'package:form_assistant_function_gemma/src/tools/validator.dart';
import 'package:form_assistant_function_gemma/src/tools/mapper.dart';
import 'package:form_assistant_function_gemma/src/evaluation/benchmark.dart'
    show normalizedCalls;

Future<void> main() async {
  const binary = '/tmp/form-assistant-llama/llama-b11429/llama-completion';
  final model = File('functiongemma-270m-it-q8_0.gguf').absolute.path;
  final root = Directory('benchmarks/function_gemma_phase6r');
  final fixtures = File('${root.path}/corpus.v1.jsonl')
      .readAsLinesSync()
      .map((s) => jsonObject(jsonDecode(s)))
      .toList();
  final specs = [
    ('A', 'string_name', ['set_string']),
    ('B', 'boolean_consent', ['set_boolean']),
    ('B', 'negation_consent', ['set_boolean']),
    ('C', 'boolean_consent', ['set_boolean', 'clear_field']),
    ('C', 'negation_consent', ['set_boolean', 'clear_field']),
    ('D', 'integer_registers', ['set_integer']),
    ('E', 'compound_age_consent_001', ['set_integer', 'set_boolean']),
  ];
  final sha = await Process.run('sha256sum', [model]);
  final version = await Process.run(binary, ['--version']);
  final commit = await Process.run('git', ['rev-parse', 'HEAD']);
  final cases = <Map<String, Object?>>[];
  final report = File('benchmarks/function_gemma_ablation/results.json');
  for (final (group, fixtureId, names) in specs) {
    final fixture = fixtures.singleWhere((f) => f['id'] == fixtureId);
    final context = SemanticContext.fromJson(
      jsonDecode(
        File('${root.path}/contexts/${fixture['contextFixture']}')
            .readAsStringSync(),
      ),
    );
    final allowed = [
      'set_value',
      if (names.contains('clear_field')) 'clear_value',
    ];
    final request = IntelligenceRequest(
      input: UserInput(text: requiredString(fixture, 'input')),
      context: context,
      allowedActionTypes: allowed,
      trace: TraceContext(
        interactionId: '$group/$fixtureId',
        requestId: 'ablation',
        operationId: 'ablation',
      ),
    );
    final all = FunctionGemmaToolSchemaBuilder().build(
      context,
      allowedActionTypes: allowed,
    );
    final tools = FunctionGemmaToolSet(
      all.definitions.where((d) => names.contains(d.name)).toList(),
    );
    if (tools.definitions.length != names.length) {
      throw StateError('Unexpected tool surface');
    }
    final prompt = formatPrompt(request, tools: tools);
    final expected = requireType<List<Object?>>(fixture['expectedCalls'])
        .map(FunctionGemmaToolCall.fromJson)
        .toList();
    final runs = <Map<String, Object?>>[];
    for (var repeat = 1; repeat <= 5; repeat++) {
      final directory = await Directory.systemTemp.createTemp(
        'functiongemma-ablation-',
      );
      try {
        final file = File('${directory.path}/prompt.txt');
        await file.writeAsString(prompt);
        final flags = [
          '-m',
          model,
          '-f',
          file.path,
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
          '<start_function_response>',
        ];
        final watch = Stopwatch()..start();
        final process = await Process.run(
          binary,
          flags,
        ).timeout(const Duration(minutes: 2));
        final transport = process.stdout as String;
        final output = transport
            .replaceFirst(RegExp(r' \[end of text\]\s*$'), '')
            .replaceFirst(RegExp(r'<start_function_response>\s*$'), '');
        List<Map<String, Object?>> envelopes = [];
        List<FunctionGemmaToolCall> calls = [];
        String? parseError;
        String? validationError;
        String? quality;
        String? qualityReason;
        List<Map<String, Object?>> actions = [];
        try {
          final parser = FunctionGemmaToolCallParser();
          envelopes = parser.parseEnvelopes(output);
          calls = parser.parse(output);
        } catch (e) {
          parseError = e.toString();
        }
        if (parseError == null) {
          try {
            if (calls.any((c) => !names.contains(c.name))) {
              throw const FormatException('Tool not exposed in this ablation');
            }
            final validated = FunctionGemmaToolCallValidator().validate(
              calls,
              context,
              allowedActionTypes: allowed,
            );
            final proposal = extractionProposal(validated, request);
            final decision = QualityGate().evaluate(
              request,
              proposal.actions,
              rejectConflictingWrites: true,
            );
            quality = decision.outcome.name;
            qualityReason = decision.reason;
            actions = decision.actions.map((a) => a.action.toJson()).toList();
          } catch (e) {
            validationError = e.toString();
          }
        }
        final correct = process.exitCode == 0 &&
            parseError == null &&
            validationError == null &&
            jsonEquals(normalizedCalls(calls), normalizedCalls(expected));
        runs.add({
          'repeat': repeat,
          'rawOutput': output,
          'transportOutput': transport,
          'stderr': process.stderr,
          'exitCode': process.exitCode,
          'durationMs': watch.elapsedMilliseconds,
          'parsedEnvelopes': envelopes,
          'parsedCalls': calls.map((c) => c.toJson()).toList(),
          'parseError': parseError,
          'validation': {
            'valid': process.exitCode == 0 &&
                parseError == null &&
                validationError == null,
            'error': validationError,
            'quality': quality,
            'qualityReason': qualityReason,
            'canonicalActions': actions,
          },
          'expectedOutput': expected.map((c) => c.toJson()).toList(),
          'exactExpectedOutput': correct,
        });
        stdout.writeln(
          '$group $fixtureId $repeat: ${correct ? 'PASS' : 'FAIL'} ${output.trim()}',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    }
    cases.add({
      'group': group,
      'fixtureId': fixtureId,
      'input': request.input.text,
      'context': context.toJson(),
      'exposedTools': names,
      'specializedTools': tools.toJson(),
      'prompt': prompt,
      'expectedOutput': expected.map((c) => c.toJson()).toList(),
      'correctRuns': runs.where((r) => r['exactExpectedOutput'] == true).length,
      'distinctRawOutputs': runs.map((r) => r['rawOutput']).toSet().length,
      'runs': runs,
    });
    await report.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
            'status': 'RUNNING',
            'cases': cases
          })}\n',
    );
  }
  await report.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
          'status': 'COMPLETE',
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'commit': (commit.stdout as String).trim(),
          'model': model,
          'modelSha256': (sha.stdout as String).split(' ').first,
          'runnerVersion': '${version.stdout}${version.stderr}'.trim(),
          'sampling': {
            'temperature': 0,
            'seed': 42,
            'threads': 1,
            'contextTokens': 8192,
            'maxOutputTokens': 512,
            'stop': '<start_function_response>'
          },
          'repeatsPerCase': 5,
          'productionBehaviorChanged': false,
          'phase6rChanged': false,
          'cases': cases,
        })}\n',
  );
}

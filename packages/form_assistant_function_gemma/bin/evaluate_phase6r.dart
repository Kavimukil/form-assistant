import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_function_gemma/form_assistant_function_gemma.dart';
import 'package:form_assistant_function_gemma/src/evaluation/benchmark.dart';

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final i = args.indexOf(name);
    return i < 0 ? fallback : args[i + 1];
  }

  final root =
      Directory(option('--corpus', '../../benchmarks/function_gemma_phase6r'))
          .absolute;
  final binary = option('--binary', 'llama-completion');
  final model = File(option('--model', '../../functiongemma-270m-it-q8_0.gguf'))
      .absolute
      .path;
  final report =
      File(option('--report', '${root.path}/reports/latest.v1.json'));
  final artifact = await Process.run('sha256sum', [model]);
  if (artifact.exitCode != 0) throw StateError('Model artifact unavailable');
  final corpus = File('${root.path}/corpus.v1.jsonl');
  final corpusHash = await Process.run('sha256sum', [corpus.path]);
  final version = await Process.run(binary, ['--version']);
  final commit = await Process.run('git', ['rev-parse', 'HEAD']);
  final config = jsonObject(
      jsonDecode(await File('${root.path}/gate.v1.json').readAsString()));
  final fixtures = (await corpus.readAsLines())
      .where((line) => line.trim().isNotEmpty)
      .map((line) => jsonObject(jsonDecode(line)))
      .toList();
  final cases = <Map<String, Object?>>[];
  for (final fixture in fixtures) {
    final context = SemanticContext.fromJson(jsonDecode(
        await File('${root.path}/contexts/${fixture['contextFixture']}')
            .readAsString()));
    final dir = await Directory.systemTemp.createTemp('phase6r-');
    final generations = <Map<String, Object?>>[];
    try {
      final result = await evaluateExtractionCase(fixture, context,
          (prompt, cancel) async {
        final promptFile = File('${dir.path}/prompt.txt');
        await promptFile.writeAsString(prompt);
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
        int? firstByteMs;
        final process =
            await Process.start('/usr/bin/time', ['-v', binary, ...flags]);
        final detach = cancel.listen(process.kill);
        try {
          final stdoutFuture = process.stdout
              .map((chunk) {
                firstByteMs ??= watch.elapsedMilliseconds;
                return chunk;
              })
              .transform(utf8.decoder)
              .join();
          final stderrFuture = process.stderr.transform(utf8.decoder).join();
          final code = await process.exitCode;
          final transport = await stdoutFuture;
          final stderr = await stderrFuture;
          final output = transport
              .replaceFirst(RegExp(r' \[end of text\]\s*$'), '')
              .replaceFirst(RegExp(r'<start_function_response>\s*$'), '');
          int? captured(String regex) {
            final match = RegExp(regex).firstMatch(stderr);
            return match == null ? null : int.parse(match[1]!);
          }

          final inputTokens =
              captured(r'prompt eval time\s*=.*?/\s*(\d+) tokens');
          final totalTokens = captured(r'total time\s*=.*?/\s*(\d+) tokens');
          generations.add({
            'prompt': prompt,
            'output': output,
            'transportOutput': transport,
            'stderr': stderr,
            'exitCode': code,
            'ttftMs': firstByteMs,
            'ttftMeasurement':
                'first stdout byte including process/model loading; not tokenizer-level timing',
            'durationMs': watch.elapsedMilliseconds,
            'inputTokens': inputTokens,
            'outputTokens': inputTokens == null || totalTokens == null
                ? null
                : totalTokens - inputTokens,
            'peakRssKb':
                captured(r'Maximum resident set size \(kbytes\):\s*(\d+)')
          });
          cancel.throwIfCancelled();
          if (code != 0) throw StateError('llama-completion exit $code');
          return FunctionGemmaOutput(output);
        } finally {
          detach();
          if (cancel.isCancelled) process.kill();
        }
      });
      result['generations'] = generations;
      cases.add(result);
      stdout.writeln(
          '${fixture['id']}: ${result['passed'] == true ? 'PASS' : 'FAIL'} (${result['failureCategory'] ?? 'exact'})');
      // Preserve each completed case if a later runner invocation is interrupted.
      await report.parent.create(recursive: true);
      await report.writeAsString('${const JsonEncoder.withIndent('  ').convert({
            'status': 'RUNNING',
            'cases': cases
          })}\n');
    } finally {
      await dir.delete(recursive: true);
    }
  }
  double? percentile(List<num> values, double q) {
    if (values.isEmpty) return null;
    values.sort();
    return values[((values.length - 1) * q).ceil()].toDouble();
  }

  final generations = cases
      .expand((c) => requireType<List<Object?>>(c['generations']))
      .map(jsonObject)
      .toList();
  final latency =
      generations.map((g) => g['durationMs']).whereType<num>().toList();
  final ttft = generations.map((g) => g['ttftMs']).whereType<num>().toList();
  final memory =
      generations.map((g) => g['peakRssKb']).whereType<num>().toList();
  final summary = summarizeBenchmark(cases, config);
  final result = {
    'status': 'COMPLETE',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'commit': (commit.stdout as String).trim(),
    'model': model,
    'modelSha256': (artifact.stdout as String).split(' ').first,
    'runnerVersion': '${version.stdout}${version.stderr}'.trim(),
    'corpusVersion': '1',
    'corpusSha256': (corpusHash.stdout as String).split(' ').first,
    'thresholds': config,
    'runtime':
        'CPU llama.cpp b11429; process per case; managed Linux x86_64; not target Zebra',
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
    'workflowTools': false,
    'cloudFallback': false,
    ...summary,
    'p50LatencyMs': percentile(latency, .5),
    'p95LatencyMs': percentile(latency, .95),
    'p50TtftMs': percentile(ttft, .5),
    'p95TtftMs': percentile(ttft, .95),
    'peakRssKb': memory.isEmpty ? null : memory.reduce((a, b) => a > b ? a : b),
    'targetDeviceMeasured': false,
    'baselineComparison': {
      'legacyCorpusCases': 12,
      'legacyCompleteCases': 2,
      'legacyPersonaCompleteCases': 1,
      'directlyComparable': false,
      'reason':
          'New frozen contexts, categories, surface and exact-action scoring; shared critical utterance compared separately.'
    },
    'failureCounts': {
      for (final kind in failureTaxonomy)
        kind: cases.where((c) => c['failureCategory'] == kind).length
    },
    'cases': cases
  };
  await report
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  await File('${report.path}.csv').writeAsString(benchmarkCsv(cases));
  stdout.writeln(
      '6R benchmark: ${summary['passed']}/${summary['total']}; thresholds pass=${summary['qualityThresholdsPassed']}');
  if (summary['qualityThresholdsPassed'] != true) exitCode = 1;
}

import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_qwen3vl/form_assistant_qwen3vl.dart';
import 'package:form_assistant_function_gemma/src/evaluation/benchmark.dart';

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final i = args.indexOf(name);
    return i < 0 ? fallback : args[i + 1];
  }

  final binary = option('--binary', 'llama-completion');
  final model = File(option('--model', '../../Qwen3VL-2B-Instruct-Q4_K_M.gguf'))
      .absolute
      .path;
  // Qwen3.8's chat template opens `<think>` unless enable_thinking is false.
  // Closing that block is the template's non-thinking prefix. The JSON
  // contract, corpus, and gate stay unchanged.
  final disableThinking = args.contains('--disable-thinking');
  final corpusRoot =
      Directory('../../benchmarks/function_gemma_phase6r').absolute;
  final report = File(option(
      '--report', '../../benchmarks/qwen3vl_phase6r/reports/qwen3vl.v1.json'));
  final config = jsonObject(
      jsonDecode(await File('${corpusRoot.path}/gate.v1.json').readAsString()));
  final corpus = File('${corpusRoot.path}/corpus.v1.jsonl');
  final fixtures = (await corpus.readAsLines())
      .where((line) => line.trim().isNotEmpty)
      .map((line) => jsonObject(jsonDecode(line)))
      .toList();
  Future<String> hash(String path) async {
    final result = await Process.run('sha256sum', [path]);
    if (result.exitCode != 0) throw StateError('Cannot hash artifact $path');
    return (result.stdout as String).split(' ').first;
  }

  final modelHash = await hash(model);
  final binaryHash = await hash(binary);
  final corpusHash = await hash(corpus.path);
  final configHash = await hash('${corpusRoot.path}/gate.v1.json');
  final contextHashes = <String, String>{};
  for (final f in fixtures) {
    final path = requiredString(f, 'contextFixture');
    contextHashes[path] = await hash('${corpusRoot.path}/contexts/$path');
  }
  final version = await Process.run(binary, ['--version']);
  final commit = await Process.run('git', ['rev-parse', 'HEAD']);
  final cases = <Map<String, Object?>>[];
  for (final fixture in fixtures) {
    final context = SemanticContext.fromJson(jsonDecode(
        await File('${corpusRoot.path}/contexts/${fixture['contextFixture']}')
            .readAsString()));
    final dir = await Directory.systemTemp.createTemp('qwen3vl-eval-');
    final raw = <String>[];
    final generations = <Map<String, Object?>>[];
    final adapter = Qwen3VlAdapter(inference: (request, cancel) async {
      final promptFile = File('${dir.path}/prompt.txt');
      final prompt = disableThinking
          ? '${request.prompt}<think>\n\n</think>\n\n'
          : request.prompt;
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
        qwenStopToken,
      ];
      final watch = Stopwatch()..start();
      int? firstByteMs;
      // Prefer GNU time -v when available; otherwise run the binary directly
      // (macOS /usr/bin/time lacks -v and reports RSS differently).
      final useGnuTime = await File('/usr/bin/time').exists() &&
          (await Process.run('/usr/bin/time', ['-v', 'true'])).exitCode == 0;
      final binaryDir = File(binary).parent.path;
      final environment = Map<String, String>.from(Platform.environment);
      final existingDyld = environment['DYLD_LIBRARY_PATH'];
      environment['DYLD_LIBRARY_PATH'] =
          existingDyld == null || existingDyld.isEmpty
              ? binaryDir
              : '$binaryDir:$existingDyld';
      final process = useGnuTime
          ? await Process.start('/usr/bin/time', ['-v', binary, ...flags],
              environment: environment)
          : await Process.start(binary, flags, environment: environment);
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
        var output = transport.trimRight();
        output = output.replaceFirst(RegExp(r'\s*\[end of text\]\s*$'), '');
        if (output.endsWith(qwenStopToken)) {
          output = output.substring(0, output.length - qwenStopToken.length);
        }
        output = output.trim();
        int? captured(String regex) {
          final match = RegExp(regex).firstMatch(stderr);
          return match == null ? null : int.parse(match[1]!);
        }

        final inputTokens =
            captured(r'prompt eval time\s*=.*?/\s*(\d+) tokens');
        final totalTokens = captured(r'total time\s*=.*?/\s*(\d+) tokens');
        raw.add(output);
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
        if (code != 0) {
          throw StateError('llama-completion exit $code: $stderr');
        }
        return Qwen3VlOutput(output);
      } finally {
        detach();
        if (cancel.isCancelled) process.kill();
      }
    });
    try {
      final result = await evaluateAdapterCase(fixture, context,
          adapter: adapter,
          rawOutputs: raw,
          decodeEnvelopes: qwenCallEnvelopes);
      result['generations'] = generations;
      cases.add(result);
      stdout.writeln(
          '${fixture['id']}: ${result['passed'] == true ? 'PASS' : 'FAIL'} (${result['failureCategory'] ?? 'exact'})');
      await report.parent.create(recursive: true);
      await report.writeAsString('${const JsonEncoder.withIndent('  ').convert({
            'status': 'RUNNING',
            'cases': cases
          })}\n');
    } finally {
      await dir.delete(recursive: true);
    }
  }
  if (corpusHash != await hash(corpus.path) ||
      configHash != await hash('${corpusRoot.path}/gate.v1.json')) {
    throw StateError('Frozen corpus/config changed');
  }
  for (final e in contextHashes.entries) {
    if (e.value != await hash('${corpusRoot.path}/contexts/${e.key}')) {
      throw StateError('Frozen context changed');
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
    'model': File(model).uri.pathSegments.last,
    'artifact': model,
    'modelSha256': modelHash,
    'binary': binary,
    'binarySha256': binaryHash,
    'runnerVersion': '${version.stdout}${version.stderr}'.trim(),
    'corpusVersion': '1',
    'corpusSha256': corpusHash,
    'gateConfigSha256': configHash,
    'contextHashes': contextHashes,
    'thresholds': config,
    'runtime': 'CPU llama.cpp; process per case; host eval; not target Zebra',
    'sampling': {
      'temperature': 0,
      'seed': 42,
      'threads': 1,
      'contextTokens': 8192,
      'maxOutputTokens': 512,
      'stop': qwenStopToken,
      'chatTemplate': disableThinking
          ? 'qwen-im_start manual; text-only; no images; enable_thinking=false prefix'
          : 'qwen-im_start manual; text-only; no images',
      'thinkingDisabled': disableThinking
    },
    'fineTuned': false,
    'scriptedOutputs': false,
    'workflowTools': false,
    'cloudFallback': false,
    'adapterRepairs': false,
    ...summary,
    'p50LatencyMs': percentile(latency, .5),
    'p95LatencyMs': percentile(latency, .95),
    'p50TtftMs': percentile(ttft, .5),
    'p95TtftMs': percentile(ttft, .95),
    'peakRssKb': memory.isEmpty ? null : memory.reduce((a, b) => a > b ? a : b),
    'targetDeviceMeasured': false,
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
      'Qwen3VL benchmark: ${summary['passed']}/${summary['total']}; quality=${summary['qualityThresholdsPassed']}');
  if (summary['qualityThresholdsPassed'] != true) exitCode = 1;
}

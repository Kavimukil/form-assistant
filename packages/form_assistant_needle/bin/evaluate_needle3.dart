import 'dart:convert';
import 'dart:io';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:form_assistant_needle/form_assistant_needle.dart';
import 'package:form_assistant_needle/src/native.dart';
import 'package:form_assistant_function_gemma/src/evaluation/benchmark.dart';
import 'package:form_assistant_function_gemma/src/tools/protocol.dart';

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final i = args.indexOf(name);
    return i < 0 ? fallback : args[i + 1];
  }

  final binary = option('--binary', '/tmp/form-assistant-needle3/needle');
  final model = option('--model', '/tmp/form-assistant-needle3/needle3.cact');
  final corpusRoot =
      Directory('../../benchmarks/function_gemma_phase6r').absolute;
  final report = File(option(
      '--report', '../../benchmarks/needle3_phase6r/reports/needle3.v1.json'));
  final config = jsonObject(
      jsonDecode(await File('${corpusRoot.path}/gate.v1.json').readAsString()));
  final corpus = File('${corpusRoot.path}/corpus.v1.jsonl');
  final fixtures = (await corpus.readAsLines())
      .map((s) => jsonObject(jsonDecode(s)))
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
  final cases = <Map<String, Object?>>[];
  for (final fixture in fixtures) {
    final context = SemanticContext.fromJson(jsonDecode(
        await File('${corpusRoot.path}/contexts/${fixture['contextFixture']}')
            .readAsString()));
    final dir = await Directory.systemTemp.createTemp('needle3-eval-');
    final raw = <String>[];
    final generations = <Map<String, Object?>>[];
    final adapter = NeedleAdapter(inference: (request, cancel) async {
      final tools = File('${dir.path}/tools.json');
      final system = File('${dir.path}/system.txt');
      await tools.writeAsString(request.toolsJson);
      await system.writeAsString(request.systemFacts);
      final flags = [
        '--model',
        model,
        '--tools',
        tools.path,
        '--system',
        system.path,
        '--prompt',
        request.input,
        '--threads',
        '1',
        '--max',
        '512',
        '--fail-input-overflow'
      ];
      final watch = Stopwatch()..start();
      int? firstByte;
      final process = await Process.start(
          '/usr/bin/time', ['-v', binary, ...flags],
          environment: {'NEEDLE_TELEMETRY': '0', 'DO_NOT_TRACK': '1'});
      final detach = cancel.listen(process.kill);
      try {
        final stdoutFuture = process.stdout
            .map((chunk) {
              firstByte ??= watch.elapsedMilliseconds;
              return chunk;
            })
            .transform(utf8.decoder)
            .join();
        final stderrFuture = process.stderr.transform(utf8.decoder).join();
        final code = await process.exitCode;
        final output = await stdoutFuture;
        final stderr = await stderrFuture;
        raw.add(output);
        final rss = RegExp(r'Maximum resident set size \(kbytes\):\s*(\d+)')
            .firstMatch(stderr);
        Map<String, Object?>? envelope;
        try {
          envelope = needleEnvelope(output);
        } catch (_) {}
        generations.add({
          'systemFacts': request.systemFacts,
          'tools': jsonDecode(request.toolsJson),
          'toolsJson': request.toolsJson,
          'input': request.input,
          'output': output,
          'transportOutput': output,
          'stderr': stderr,
          'exitCode': code,
          'durationMs': watch.elapsedMilliseconds,
          'ttftMs': firstByte,
          'ttftMeasurement':
              'first stdout byte; JSON emitted after generation; NOT model TTFT',
          'peakRssKb': rss == null ? null : int.parse(rss[1]!),
          'inputTokens': null,
          'outputTokens': null,
          'tokenMeasurement': 'official CLI does not expose token counts',
          'prefillTps': envelope?['prefill_tps'],
          'decodeTps': envelope?['decode_tps']
        });
        cancel.throwIfCancelled();
        if (code != 0) throw StateError('Needle exit $code: $stderr');
        return NeedleOutput(output);
      } finally {
        detach();
        if (cancel.isCancelled) process.kill();
      }
    });
    try {
      final result = await evaluateAdapterCase(fixture, context,
          adapter: adapter,
          rawOutputs: raw,
          decodeEnvelopes: needleCallEnvelopes);
      result['generations'] = generations;
      result['modelConfidence'] = null;
      result['suppressedCalls'] = <Object?>[];
      result['candidateExactIncludingSuppressed'] = false;
      if (raw.isNotEmpty) {
        try {
          final envelope = needleEnvelope(raw.single);
          result['modelConfidence'] = envelope['confidence'];
          result['engineValidation'] = envelope['validation'];
          final suppressed = envelope['suppressed_calls'] == null
              ? const <Object?>[]
              : requireType<List<Object?>>(envelope['suppressed_calls']);
          result['suppressedCalls'] = suppressed;
          final candidates = [
            ...requireType<List<Object?>>(envelope['function_calls']),
            ...suppressed
          ].map(FunctionGemmaToolCall.fromJson).toList();
          final expected = requireType<List<Object?>>(fixture['expectedCalls'])
              .map(FunctionGemmaToolCall.fromJson)
              .toList();
          result['candidateExactIncludingSuppressed'] = jsonEquals(
              normalizedCalls(candidates), normalizedCalls(expected));
        } catch (e) {
          result['candidateDiagnosticError'] = e.toString();
        }
      }
      cases.add(result);
      stdout.writeln(
          '${fixture['id']}: ${result['passed'] == true ? 'PASS' : 'FAIL'} (exact=${result['exactActionSet']}, confidence=${result['modelConfidence']}, ${result['failureCategory']})');
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
  final summary = summarizeBenchmark(cases, config);
  double? percentile(List<num> values, double q) {
    if (values.isEmpty) return null;
    values.sort();
    return values[((values.length - 1) * q).ceil()].toDouble();
  }

  final allGenerations = cases
      .expand((c) => requireType<List<Object?>>(c['generations']))
      .map(jsonObject)
      .toList();
  final latency =
      allGenerations.map((g) => g['durationMs']).whereType<num>().toList();
  final memory =
      allGenerations.map((g) => g['peakRssKb']).whereType<num>().toList();
  final commit = await Process.run('git', ['rev-parse', 'HEAD']);
  final result = {
    'status': 'COMPLETE',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'commit': (commit.stdout as String).trim(),
    'model': 'Needle 3 full-depth base .cact',
    'artifact': model,
    'modelSha256': modelHash,
    'binary': binary,
    'binarySha256': binaryHash,
    'officialArtifactRevision': '2ae11323dc000f5e70c49f7403efa6af12ba9e67',
    'artifactSource':
        'https://huggingface.co/Cactus-Compute/needle3/tree/2ae11323dc000f5e70c49f7403efa6af12ba9e67',
    'corpusVersion': '1',
    'corpusSha256': corpusHash,
    'gateConfigSha256': configHash,
    'contextHashes': contextHashes,
    'thresholds': config,
    'inference': {
      'threads': 1,
      'maxOutputTokens': 512,
      'depth': 'full',
      'decoding': 'official CLI defaults; no exposed temperature/seed flags',
      'forced': false,
      'failInputOverflow': true,
      'telemetry': false,
      'autoDateInjection': false,
      'engineGrammarConstrained': true,
      'engineNativeGroundingRepair':
          'shipped engine may apply documented deterministic grounding; pre-repair output is not exposed',
      'adapterRepairs': false,
      'engineSuppressedCallsPromoted': false,
      'coreMinimumConfidence': .8
    },
    'fineTuned': false,
    'cloudFallback': false,
    'scriptedOutputs': false,
    'targetDeviceMeasured': false,
    ...summary,
    'candidateExactIncludingSuppressed':
        accuracy(cases, (_) => true, 'candidateExactIncludingSuppressed'),
    'p50LatencyMs': percentile(latency, .5),
    'p95LatencyMs': percentile(latency, .95),
    'modelTtftMs': null,
    'peakRssKb': memory.isEmpty ? null : memory.reduce((a, b) => a > b ? a : b),
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
      'Needle 3 complete benchmark: ${summary['passed']}/${summary['total']}; quality=${summary['qualityThresholdsPassed']}');
  if (summary['qualityThresholdsPassed'] != true) exitCode = 1;
}

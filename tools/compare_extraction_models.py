"""Compare recorded models without changing or reinterpreting the frozen gate."""
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def read(path):
    return json.loads((ROOT / path).read_text())
def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()

fg_path = 'benchmarks/function_gemma_phase6r/reports/simple_native.v1.json'
needle_path = 'benchmarks/needle3_phase6r/reports/needle3.v1.json'
qwen_path = 'benchmarks/qwen3vl_phase6r/reports/qwen3vl.v1.json'
f, n, q = read(fg_path), read(needle_path), read(qwen_path)
assert f['status'] == n['status'] == q['status'] == 'COMPLETE'
corpus_sha = sha('benchmarks/function_gemma_phase6r/corpus.v1.jsonl')
assert f['corpusSha256'] == n['corpusSha256'] == q['corpusSha256'] == corpus_sha
assert f['thresholds'] == n['thresholds'] == q['thresholds']
assert n['gateConfigSha256'] == q['gateConfigSha256'] == sha(
    'benchmarks/function_gemma_phase6r/gate.v1.json')
for name, digest in q['contextHashes'].items():
    assert digest == sha('benchmarks/function_gemma_phase6r/contexts/' + name)
assert len(f['cases']) == len(n['cases']) == len(q['cases']) == 31
rows = []
for a, b, c in zip(f['cases'], n['cases'], q['cases']):
    for key in ('id', 'category', 'input', 'expectedCalls', 'expectedValues',
                'contextFingerprint'):
        assert a[key] == b[key] == c[key], (a['id'], key)
    rows.append({
        'id': a['id'], 'input': a['input'], 'expectedCalls': a['expectedCalls'],
        **{label: {key: case.get(key) for key in (
            'rawOutput', 'parsedCalls', 'validationError', 'decodingError',
            'quality', 'qualityReason', 'canonicalActions', 'passed',
            'failureCategory', 'modelConfidence', 'suppressedCalls',
            'candidateExactIncludingSuppressed')}
           for label, case in [
               ('functionGemma', a), ('needle3', b), ('qwen3vl', c)]}})
models = {}
for label, report, path in [
    ('functionGemma', f, fg_path),
    ('needle3', n, needle_path),
    ('qwen3vl', q, qwen_path),
]:
    assert not report['qualityThresholdsPassed']
    models[label] = {
        'decision': 'MODEL_NO_GO', 'source': path, 'sourceSha256': sha(path),
        **{key: report.get(key) for key in (
            'model', 'modelSha256', 'passed', 'total', 'metrics', 'checks',
            'p50LatencyMs', 'p95LatencyMs', 'peakRssKb',
            'candidateExactIncludingSuppressed', 'failureCounts')},
        'criticalPassed': sum(
            c['passed'] for c in report['cases']
            if c['id'].startswith('compound_age_consent_'))}
out = ROOT / 'benchmarks/model_comparison'
out.mkdir(parents=True, exist_ok=True)
result = {
    'corpusSha256': f['corpusSha256'], 'thresholds': f['thresholds'],
    'corpusAndExpectedOutputsUnchanged': True, 'phase7': 'BLOCKED',
    'ablationSource': 'benchmarks/function_gemma_ablation/results.json',
    'ablationSha256': sha('benchmarks/function_gemma_ablation/results.json'),
    'models': models, 'cases': rows,
    'limitations': [
        'Needle native engine applies grammar, grounding and suppression; '
        'pre-repair tokens unavailable.',
        'Needle suppressed candidates never count as primary successes; '
        'QualityGate remains 0.8.',
        'Qwen3VL host eval is text-only (no images); llama.cpp CPU build '
        'b11445 / commit 58cb913; macOS host peak RSS unavailable without '
        'GNU time -v.',
        'Host cold process timings only; no Zebra measurement.',
    ]}
(out / 'comparison.v1.json').write_text(json.dumps(result, indent=2) + '\n')
with (out / 'comparison.v1.csv').open('w', newline='') as stream:
    writer = csv.writer(stream)
    writer.writerow([
        'id', 'input', 'expected_calls',
        'functiongemma_calls', 'functiongemma_passed',
        'needle_calls', 'needle_suppressed', 'needle_passed',
        'needle_quality_reason',
        'qwen3vl_calls', 'qwen3vl_passed', 'qwen3vl_failure'])
    for row in rows:
        a, b, c = row['functionGemma'], row['needle3'], row['qwen3vl']
        writer.writerow([
            row['id'], row['input'], json.dumps(row['expectedCalls']),
            json.dumps(a['parsedCalls']), a['passed'],
            json.dumps(b['parsedCalls']), json.dumps(b['suppressedCalls']),
            b['passed'], b['qualityReason'],
            json.dumps(c['parsedCalls']), c['passed'], c['failureCategory']])
print('Compared 31 identical frozen cases; all MODEL_NO_GO '
      f'(FG {f["passed"]}/31, Needle {n["passed"]}/31, Qwen3VL {q["passed"]}/31).')

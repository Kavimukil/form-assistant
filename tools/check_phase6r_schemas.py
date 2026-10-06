"""Validate the frozen extraction protocol and production schema golden."""
import json
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
root = Path(__file__).resolve().parents[1]
fixtures = root / 'packages/form_assistant_function_gemma/test/fixtures'
protocol = json.loads((fixtures / 'extraction_protocol.v1.json').read_text())
Draft202012Validator.check_schema(protocol)
validator = Draft202012Validator(protocol, format_checker=FormatChecker())
corpus = [json.loads(line) for line in (root / 'benchmarks/function_gemma_phase6r/corpus.v1.jsonl').read_text().splitlines()]
checks = 0
for case in corpus:
    for call in case['expectedCalls']:
        validator.validate(call)
        checks += 1
for name, value in [('set_integer', '32'), ('set_integer', 32.5), ('set_boolean', 1),
                    ('set_boolean', 'yes'), ('set_date', '2026-02-30'),
                    ('set_date', '05/10/2026'), ('set_multi_choice', ['java', 'java'])]:
    assert list(validator.iter_errors({'name': name, 'arguments': {'field_id': 'field', 'value': value}})), (name, value)
    checks += 1
specialized = json.loads((fixtures / 'specialized_schema.v1.json').read_text())
for tool in specialized:
    Draft202012Validator.check_schema(tool['parameters'])
    checks += 1
choice = next(t['parameters'] for t in specialized if t['name'] == 'set_choice')
v = Draft202012Validator(choice)
v.validate({'field_id': 'promotion', 'value': 'fall'})
assert list(v.iter_errors({'field_id': 'promotion', 'value': 'Autumn'}))
checks += 2
print(f'PASS: extraction protocol, specialized golden and {checks} checks')

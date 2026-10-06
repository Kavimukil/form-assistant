"""Validate canonical fixtures and malformed inputs against protocol schemas.

Development dependency: jsonschema 4.x (not a core runtime dependency).
Run from the repository root: python3 tools/check_contract_schemas.py
"""
from pathlib import Path
import json
from datetime import datetime
import re

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[1]
SCHEMAS = ROOT / 'contracts/schemas'
FIXTURES = ROOT / 'packages/form_assistant_core/test/fixtures'
formats = FormatChecker()

@formats.checks('date-time', raises=(ValueError, TypeError))
def utc_timestamp(value):
    if not isinstance(value, str):
        return True
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:\d{3})?Z', value):
        return False
    datetime.strptime(value, '%Y-%m-%dT%H:%M:%S.%fZ')
    return True

registry = Registry()
schemas = {}
for path in sorted(SCHEMAS.glob('*.json')):
    schema = json.loads(path.read_text())
    Draft202012Validator.check_schema(schema)
    schema['$id'] = path.as_uri()
    schemas[path.name.removesuffix('.schema.json')] = schema
    registry = registry.with_resource(path.as_uri(), Resource.from_contents(schema))


def validator(name, definition=None):
    schema = schemas[name]
    if definition:
        schema = {'$ref': schema['$id'] + '#/$defs/' + definition}
    return Draft202012Validator(schema, registry=registry, format_checker=formats)


def fixture(name):
    return json.loads((FIXTURES / (name + '.json')).read_text())


checks = 0
for kind in ['value', 'action']:
    check = validator('form-' + kind)
    for value in fixture('contracts')[kind + 's']:
        check.validate(value)
        checks += 1
validator('form-state').validate(fixture('form_state'))
checks += 1
for event in fixture('bridge_events'):
    validator('bridge-event').validate(event)
    checks += 1
for result in fixture('action_results'):
    validator('bridge-event', 'ActionResult').validate(result)
    checks += 1
validator('bridge-event', 'BatchActionResult').validate(fixture('batch_result'))
checks += 1
for name, invalid in [
    ('form-value', {'type': 'integer', 'value': '1'}),
    ('form-value', {'type': 'date', 'value': '2026-02-30'}),
    ('form-action', {'type': 'navigate', 'target': {'type': 'future'}}),
    ('form-state', {**fixture('form_state'), 'revision': -1}),
    ('form-state', {**fixture('form_state'), 'specVersion': '2.0'}),
    ('bridge-event', {**fixture('bridge_events')[0], 'timestamp': '2026-02-30T12:00:00.000Z'}),
    ('bridge-event', {**fixture('bridge_events')[0], 'snapshot': None}),
]:
    assert not validator(name).is_valid(invalid), (name, invalid)
    checks += 1
assert validator('form-state').is_valid({**fixture('form_state'), 'optionalFuture': True})
checks += 1
print(f'PASS: {len(schemas)} schemas and {checks} fixture/malformed-input checks')

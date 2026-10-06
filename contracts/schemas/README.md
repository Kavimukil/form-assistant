# Serialized schemas

Protocol 1.0 schemas mirror the canonical Dart codecs and golden fixtures:

- `form-value.schema.json`: discriminated canonical value fragments.
- `form-action.schema.json`: discriminated canonical action fragments.
- `form-state.schema.json`: versioned FormStateSnapshot documents.
- `bridge-event.schema.json`: versioned bridge events, including nested result,
  batch, change and snapshot definitions. BridgeError.cause is runtime-only.

Snapshot/event roots carry explicit specVersion. Compatible 1.x versions and
unknown optional properties are accepted; current writers emit 1.0. Optional
null properties are omitted. Timestamps use UTC ISO strings. The schemas' date
and date-time formats require format validation, in addition to type checking.

From the repository root run `python3 tools/check_contract_schemas.py`
(development dependency: jsonschema 4.x). It checks all four schema documents,
canonical fixtures and malformed inputs. Strict Dart codecs additionally enforce
portable JSON safety and exact Dart integer types without coercion.

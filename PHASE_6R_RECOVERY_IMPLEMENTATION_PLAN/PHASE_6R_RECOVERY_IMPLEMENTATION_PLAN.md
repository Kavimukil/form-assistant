# Phase 6R Recovery Implementation Plan

**Project:** Local-first Schema-Agnostic Voice Form Assistant Runtime  
**Audience:** Codex / Cursor implementation agent + human reviewer  
**Status:** Implementation plan  
**Starting point:** Phases 0–5 complete; original Phase 6 failed and is superseded  
**Primary model under evaluation:** FunctionGemma 270M  
**Scope:** Recover intelligence integration without rewriting the deterministic runtime foundation

---

## 0. Executive decision

**Do not restart the project.** Preserve Phases 0–5 and replace the failed Phase 6 with **Phase 6R: Constrained Intelligence Recovery**.

The failed Phase 6 tested the wrong abstraction: FunctionGemma was effectively given too much agent/workflow responsibility. Phase 6R narrows the model to **context-conditioned typed semantic slot extraction**. The deterministic runtime continues to own form state, validation, rules, authorization, concurrency, and commits.

### Recovery principle

```text
Phases 0–5                  KEEP
Original Phase 6            TAG + SUPERSEDE
Phase 6R                    IMPLEMENT
Phase 7+                    BLOCKED until 6R GO gate passes
```

Before changing code:

```bash
git status
git add -A
git commit -m "checkpoint: failed phase 6 baseline" || true
git tag phase-6-failed-baseline
git switch -c phase-6r-functiongemma-recovery
```

Do not delete the failed implementation until the migration is complete and benchmark results are preserved.

---

# 1. Problem statement and evidence

The original Phase 6 integration allowed FunctionGemma to behave too much like a general form agent. A representative failure was a simple compound utterance such as:

```text
Age thirty two, consent yes
```

The desired result is exactly:

```json
[
  {
    "name": "set_integer",
    "arguments": {"field_id": "age", "value": 32}
  },
  {
    "name": "set_boolean",
    "arguments": {"field_id": "consent", "value": true}
  }
]
```

Instead, the model could extract only part of the information, request unnecessary clarification, or choose unrelated workflow/navigation behavior.

This does **not** invalidate the runtime architecture. It invalidates the intelligence integration assumptions.

### Revised hypothesis

FunctionGemma 270M may be useful if its job is constrained to:

```text
Natural language + tiny canonical form context
                    ↓
       typed semantic slot extraction
                    ↓
           canonical mutations
```

It must not own:

- form state;
- validation truth;
- rules;
- navigation/workflow during the extraction benchmark;
- submit;
- authorization;
- side effects;
- source-schema interpretation;
- field discovery across thousands of fields.

---

# 2. Architecture delta

## 2.1 Old Phase 6 mental model

```text
UserInput
   ↓
IntelligenceAdapter
   ↓
FunctionGemma
   ↓
generic/broad tool surface
   ↓
FormAction / workflow behavior
```

## 2.2 Phase 6R architecture

```text
FormIR + FormStateSnapshot + UserInput
                  │
                  ▼
            ContextCompiler
                  │
                  ▼
          SemanticContext
     revision + fingerprint + locale
                  │
                  ▼
    FunctionGemmaToolSchemaBuilder
                  │
                  ▼
    specialized extraction tools
                  │
                  ▼
           FunctionGemma
                  │
                  ▼
      native typed tool calls
                  │
                  ▼
    FunctionGemmaToolCallParser
                  │
                  ▼
       FunctionGemmaAdapter
                  │
                  ▼
           QualityGate
                  │
                  ▼
         ActionProposal[]
                  │
                  ▼
           ActionRuntime
                  │
                  ▼
         FormStateBridge
```

### Responsibility boundary

```text
ContextCompiler
    controls what the model can SEE

ToolSchemaBuilder
    controls what the model can PROPOSE

Strict parser + QualityGate
    controls what is considered VALID

ActionRuntime + FormStateBridge
    controls what can actually HAPPEN
```

---

# 3. Preserve / modify / add / retire

## KEEP unchanged unless compilation forces a small compatibility edit

- `FormValue`
- canonical `FormAction`
- `FormIR`
- `FormAdapter`
- `FormStateSnapshot`
- `FormStateBridge`
- `LocalFormStateBridge`
- `ExternalFormStateBridge`
- revision semantics
- `ActionRuntime`
- runtime state/event/tracing infrastructure
- `IntelligenceAdapter` abstraction
- `MockIntelligenceAdapter`

## KEEP but evolve

- `SemanticContext`
- `ContextCompiler`
- `ActionProposal`
- `FunctionGemmaAdapter`
- `QualityGate`
- intelligence evaluation harness if one exists

## ADD

- `FunctionGemmaContextFormatter`
- `FunctionGemmaToolSchemaBuilder`
- `FunctionGemmaToolSet`
- `FunctionGemmaToolDefinition`
- `FunctionGemmaToolCall`
- `FunctionGemmaToolCallParser`
- `FunctionGemmaToolCallValidator`
- canonical tool-schema encoder
- tool-schema fingerprint/cache key
- Phase 6R benchmark corpus
- benchmark runner + machine-readable report
- migration/compatibility tests

## REMOVE FROM MODEL SURFACE / DEPRECATE

- generic `set_form_field` model tool;
- raw source-schema exposure;
- full-form schema prompt;
- model-driven navigation in extraction benchmark;
- model-driven submit;
- model-driven undo/redo;
- upload/camera/signature/delete tools;
- `request_clarification` as a FunctionGemma tool during the initial GO/NO-GO benchmark.

Do not necessarily delete canonical runtime actions such as navigation. The change is that they are not part of the initial FunctionGemma extraction surface.

---

# 4. Public vs internal contracts

Phase 6R must preserve this separation.

## Public/stable runtime contracts

- `FormAdapter`
- `FormIR`
- `FormValue`
- `FormAction`
- `FormStateBridge`
- `FormStateSnapshot`
- `IntelligenceAdapter`
- `IntelligenceRequest`
- `IntelligenceResult`
- `ActionProposal`
- `SemanticContext` serialized shape if already public

## FunctionGemma-specific internal contracts

- tool names and native formatting;
- tool-schema specialization;
- prompt formatting;
- native tool-call parsing;
- tokenization/runtime integration;
- schema caching;
- FunctionGemma-specific confidence/diagnostics.

Swapping FunctionGemma for Needle or another model must not change canonical `FormAction` or state contracts.

---

# 5. SemanticContext v1.1

Do not pass raw project schemas to the model. `SemanticContext` is a bounded canonical projection of the fields relevant to the current interaction.

```dart
final class SemanticContext {
  static const String currentSpecVersion = '1.1';

  final String specVersion;
  final String formId;
  final int revision;
  final String fingerprint;
  final String locale;
  final String? activeFieldId;
  final List<String> recentFieldIds;
  final List<SemanticFieldContext> fields;
}
```

```dart
final class SemanticFieldContext {
  final String id;
  final SemanticValueType type;
  final String label;
  final String? concept;
  final List<String> aliases;
  final FormValue? currentValue;
  final SemanticConstraints constraints;
  final List<SemanticOption> options;
  final bool optionsTruncated;
  final bool writable;
  final Set<FieldSelectionReason> selectionReasons;
}
```

```dart
enum SemanticValueType {
  string,
  integer,
  number,
  boolean,
  date,
  choice,
  multiChoice,
}
```

### Invariants

1. IDs are canonical and language-neutral.
2. `currentValue == null` means unanswered/cleared.
3. Choice values are canonical option IDs, never labels.
4. `writable=false` fields may be included for understanding but never exposed as mutation targets.
5. `revision` equals the source `FormStateSnapshot.revision` used for compilation.
6. Context is bounded by field/token budgets.
7. Full source schema is never present.
8. `fingerprint` covers model-relevant semantic context, not runtime diagnostics.
9. Selection reasons are diagnostic and should normally not be sent to FunctionGemma.

### Default context budget

```dart
final class ContextBudget {
  final int maxFields;          // default 16
  final int maxTokens;          // default 768
  final int maxRecentFields;    // default 5
  final int maxAliasesPerField; // default 6
  final int maxOptionsPerField; // default 32
  final int maxFieldCharacters; // default 512
}
```

The budget is runtime configuration, not a wire-protocol constant.

---

# 6. Frozen FunctionGemma extraction vocabulary v1

Phase 6R exposes exactly these eight tools during the core benchmark:

```text
set_string
set_integer
set_number
set_boolean
set_date
set_choice
set_multi_choice
clear_field
```

No workflow tools are permitted in the Phase 6R GO/NO-GO benchmark.

## Canonical tool-call envelope

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "FunctionGemma Extraction Tool Call",
  "oneOf": [
    {"$ref": "#/$defs/set_string"},
    {"$ref": "#/$defs/set_integer"},
    {"$ref": "#/$defs/set_number"},
    {"$ref": "#/$defs/set_boolean"},
    {"$ref": "#/$defs/set_date"},
    {"$ref": "#/$defs/set_choice"},
    {"$ref": "#/$defs/set_multi_choice"},
    {"$ref": "#/$defs/clear_field"}
  ],
  "$defs": {
    "field_id": {"type": "string", "minLength": 1},
    "option_id": {"type": "string", "minLength": 1},

    "set_string": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "arguments"],
      "properties": {
        "name": {"const": "set_string"},
        "arguments": {
          "type": "object",
          "additionalProperties": false,
          "required": ["field_id", "value"],
          "properties": {
            "field_id": {"$ref": "#/$defs/field_id"},
            "value": {"type": "string"}
          }
        }
      }
    },

    "set_integer": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "arguments"],
      "properties": {
        "name": {"const": "set_integer"},
        "arguments": {
          "type": "object",
          "additionalProperties": false,
          "required": ["field_id", "value"],
          "properties": {
            "field_id": {"$ref": "#/$defs/field_id"},
            "value": {"type": "integer"}
          }
        }
      }
    },

    "set_number": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "arguments"],
      "properties": {
        "name": {"const": "set_number"},
        "arguments": {
          "type": "object",
          "additionalProperties": false,
          "required": ["field_id", "value"],
          "properties": {
            "field_id": {"$ref": "#/$defs/field_id"},
            "value": {"type": "number"}
          }
        }
      }
    },

    "set_boolean": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "arguments"],
      "properties": {
        "name": {"const": "set_boolean"},
        "arguments": {
          "type": "object",
          "additionalProperties": false,
          "required": ["field_id", "value"],
          "properties": {
            "field_id": {"$ref": "#/$defs/field_id"},
            "value": {"type": "boolean"}
          }
        }
      }
    },

    "set_date": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "arguments"],
      "properties": {
        "name": {"const": "set_date"},
        "arguments": {
          "type": "object",
          "additionalProperties": false,
          "required": ["field_id", "value"],
          "properties": {
            "field_id": {"$ref": "#/$defs/field_id"},
            "value": {
              "type": "string",
              "format": "date",
              "pattern": "^\\d{4}-\\d{2}-\\d{2}$"
            }
          }
        }
      }
    },

    "set_choice": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "arguments"],
      "properties": {
        "name": {"const": "set_choice"},
        "arguments": {
          "type": "object",
          "additionalProperties": false,
          "required": ["field_id", "value"],
          "properties": {
            "field_id": {"$ref": "#/$defs/field_id"},
            "value": {"$ref": "#/$defs/option_id"}
          }
        }
      }
    },

    "set_multi_choice": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "arguments"],
      "properties": {
        "name": {"const": "set_multi_choice"},
        "arguments": {
          "type": "object",
          "additionalProperties": false,
          "required": ["field_id", "value"],
          "properties": {
            "field_id": {"$ref": "#/$defs/field_id"},
            "value": {
              "type": "array",
              "uniqueItems": true,
              "items": {"$ref": "#/$defs/option_id"}
            }
          }
        }
      }
    },

    "clear_field": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "arguments"],
      "properties": {
        "name": {"const": "clear_field"},
        "arguments": {
          "type": "object",
          "additionalProperties": false,
          "required": ["field_id"],
          "properties": {
            "field_id": {"$ref": "#/$defs/field_id"}
          }
        }
      }
    }
  }
}
```

Multiple calls are represented as an ordered list of these primitive calls. Preserve model order until deterministic normalization/validation decides otherwise.

---

# 7. Runtime tool-schema specialization

`FunctionGemmaToolSchemaBuilder` is deterministic and model-specific.

```dart
abstract interface class FunctionGemmaToolSchemaBuilder {
  FunctionGemmaToolSet build(SemanticContext context);
}
```

## Specialization rules

1. Only fields present in `SemanticContext.fields` may appear in any `field_id`.
2. Only `writable == true` fields may appear as mutation targets.
3. Exact type mapping:
   - string → `set_string`
   - integer → `set_integer`
   - number → `set_number`
   - boolean → `set_boolean`
   - date → `set_date`
   - choice → `set_choice`
   - multiChoice → `set_multi_choice`
4. Omit a setter completely if there are no compatible writable fields.
5. `clear_field` includes every writable selected field. Clearing an empty field is allowed to resolve as deterministic `ActionNoOp`; this keeps schema identity stable across ordinary value changes.
6. Choice output values are canonical option IDs only.
7. Multi-choice items are canonical option IDs only.
8. Labels and aliases help interpretation but are never legal output values.
9. If `optionsTruncated == true`, only supplied candidate option IDs may be emitted.
10. Multiple choice fields should use correlated field→option branches (`oneOf`) when supported/reliable; benchmark a simpler schema if nested `oneOf` hurts FunctionGemma.
11. Schema order must be deterministic.
12. Specialization is not a validation/security boundary. Validate again after generation.

### Concrete specialization example

Input context:

```json
{
  "specVersion": "1.1",
  "formId": "store_visit",
  "revision": 31,
  "fingerprint": "sha256:example",
  "locale": "en-IN",
  "activeFieldId": "consent",
  "recentFieldIds": ["age", "promotion"],
  "fields": [
    {"id": "name", "type": "string", "label": "Name", "currentValue": "Mukil", "writable": true},
    {"id": "age", "type": "integer", "label": "Age", "currentValue": null, "writable": true},
    {"id": "weight_kg", "type": "number", "label": "Weight", "currentValue": null, "writable": true},
    {"id": "consent", "type": "boolean", "label": "Consent", "currentValue": null, "writable": true},
    {"id": "visit_date", "type": "date", "label": "Visit date", "currentValue": null, "writable": true},
    {
      "id": "promotion",
      "type": "choice",
      "label": "Promotion",
      "currentValue": "spring",
      "writable": true,
      "optionsTruncated": false,
      "options": [
        {"id": "spring", "label": "Spring"},
        {"id": "summer", "label": "Summer"},
        {"id": "fall", "label": "Fall", "aliases": ["autumn"]},
        {"id": "winter", "label": "Winter"}
      ]
    },
    {
      "id": "technologies",
      "type": "multi_choice",
      "label": "Technologies",
      "currentValue": ["java"],
      "writable": true,
      "optionsTruncated": false,
      "options": [
        {"id": "java", "label": "Java"},
        {"id": "flutter", "label": "Flutter"},
        {"id": "react", "label": "React"},
        {"id": "python", "label": "Python"}
      ]
    }
  ]
}
```

Expected mutation surface:

```text
set_string        field_id=[name]
set_integer       field_id=[age]
set_number        field_id=[weight_kg]
set_boolean       field_id=[consent]
set_date          field_id=[visit_date]
set_choice        field_id=promotion, values=[spring,summer,fall,winter]
set_multi_choice  field_id=technologies, values=[java,flutter,react,python]
clear_field       field_id=[name,age,weight_kg,consent,visit_date,promotion,technologies]
```

---

# 8. Strict tool-call validation

The FunctionGemma adapter must not coerce malformed model output.

## Required strictness

| Tool | Accept | Reject |
|---|---|---|
| set_string | JSON string | number, bool, null |
| set_integer | JSON integer | `"32"`, `32.5`, bool |
| set_number | finite JSON number | numeric string, NaN, Infinity |
| set_boolean | JSON bool | `"yes"`, `"true"`, `1` |
| set_date | real YYYY-MM-DD date | locale date strings, impossible dates |
| set_choice | canonical valid option ID | label, alias, source ID, unknown ID |
| set_multi_choice | unique canonical option IDs | unknown IDs, scalar, duplicates |
| clear_field | valid field_id only | extra `value` argument |

FunctionGemma performs semantic conversion:

```text
"thirty two"              → 32
"yes"                     → true
"seventy two point five" → 72.5
"14th August 1992"       → "1992-08-14"
"autumn"                  → "fall"
```

The adapter verifies the result; it does not repair arbitrary output.

### Dart mapping

```dart
FormAction mapFunctionGemmaCall(FunctionGemmaToolCall call) {
  final args = call.arguments;

  return switch (call.name) {
    'set_string' => SetValueAction(
        fieldId: requiredFieldId(args),
        value: StringValue(requiredString(args, 'value')),
      ),
    'set_integer' => SetValueAction(
        fieldId: requiredFieldId(args),
        value: IntegerValue(requiredInteger(args, 'value')),
      ),
    'set_number' => SetValueAction(
        fieldId: requiredFieldId(args),
        value: NumberValue(requiredFiniteNumber(args, 'value')),
      ),
    'set_boolean' => SetValueAction(
        fieldId: requiredFieldId(args),
        value: BooleanValue(requiredBoolean(args, 'value')),
      ),
    'set_date' => SetValueAction(
        fieldId: requiredFieldId(args),
        value: DateValue(requiredIsoDate(args, 'value')),
      ),
    'set_choice' => SetValueAction(
        fieldId: requiredFieldId(args),
        value: ChoiceValue(requiredString(args, 'value')),
      ),
    'set_multi_choice' => SetValueAction(
        fieldId: requiredFieldId(args),
        value: MultiChoiceValue(requiredStringList(args, 'value')),
      ),
    'clear_field' => ClearValueAction(
        fieldId: requiredFieldId(args),
      ),
    _ => throw UnsupportedFunctionGemmaToolException(call.name),
  };
}
```

After parsing, validate against the exact `SemanticContext` used for inference:

```text
known tool?
  ↓
exact argument types?
  ↓
field in context?
  ↓
field writable?
  ↓
tool matches semantic field type?
  ↓
choice IDs valid for that field?
  ↓
constraints/rules valid?
  ↓
canonical FormAction
```

No invalid model output reaches `FormStateBridge`.

---

# 9. Multi-choice semantics

`set_multi_choice` is **replacement**, not append.

Current state:

```json
{"technologies": ["java"]}
```

Utterance:

```text
Also add Flutter and React
```

Expected call:

```json
{
  "name": "set_multi_choice",
  "arguments": {
    "field_id": "technologies",
    "value": ["java", "flutter", "react"]
  }
}
```

Do not add `add_choice`/`remove_choice` in Phase 6R. Reconsider only if the benchmark demonstrates replacement semantics are a systematic weakness.

---

# 10. Date semantics

`set_date.value` is always normalized `YYYY-MM-DD`.

Example:

```text
My date of birth is 14th August 1992
```

Expected:

```json
{
  "name": "set_date",
  "arguments": {
    "field_id": "date_of_birth",
    "value": "1992-08-14"
  }
}
```

Validate both regex shape and actual calendar validity. Reject `2025-02-29`, `2026-04-31`, `05/10/2026`, etc.

Relative dates such as `yesterday` require explicit interaction temporal context, e.g. `referenceDate` and `timeZone`. Do not infer relative dates without that context.

---

# 11. Proposal and revision chain

Preserve the complete revision chain:

```text
FormStateSnapshot.revision
        ↓
SemanticContext.revision
        ↓
IntelligenceRequest
        ↓
ActionProposal.baseRevision
        ↓
ApplyContext.expectedRevision
```

```dart
final class ActionProposal {
  final String id;
  final int baseRevision;
  final List<FormAction> actions;
  final ActionProvenance provenance;
  final double? confidence;
}
```

If inference starts on revision 17 and the authoritative state moves to 18, do not blindly apply the proposal.

---

# 12. Fingerprints and schema caching

Maintain three separate identities.

```text
revision
  → optimistic concurrency / stale proposal detection

SemanticContext.fingerprint
  → did model-relevant semantic context change?

toolSchemaFingerprint
  → did FunctionGemma's permitted output space change?
```

Do not collapse them into one value.

## Schema cache key

```dart
final class FunctionGemmaSchemaCacheKey {
  final String cacheKeyVersion;       // "1"
  final String toolProtocolVersion;   // "1.0"
  final String adapterVersion;
  final String normalizedLocale;
  final String toolSchemaFingerprint;
}
```

Do not include revision, formId, sessionId, interactionId, proposalId, or the complete SemanticContext fingerprint.

### Invalidation policy

- revision-only change → schema cache HIT;
- ordinary current-value change → HIT;
- active field change → HIT if selected mutation surface is unchanged;
- field/option labels or aliases change → schema HIT, model-context fingerprint changes;
- selected field added/removed → MISS;
- field type changes → MISS;
- writable changes → MISS;
- option ID added/removed → MISS;
- retrieved/truncated option candidate set changes → MISS;
- locale changes → MISS initially;
- tool protocol or adapter/schema-builder version changes → MISS.

Compute `toolSchemaFingerprint` from deterministic canonical serialization of the generated specialized schema/tool set. This prevents future schema-affecting features from being omitted accidentally.

---

# 13. QualityGate Phase 6R behavior

QualityGate is deterministic. Valid JSON is not enough.

Minimum checks:

- parse validity;
- supported tool;
- exact argument types;
- field existence in supplied SemanticContext;
- writable status;
- tool↔field type compatibility;
- field constraints;
- option validity;
- multi-choice uniqueness;
- duplicate/conflicting writes;
- stale revision;
- semantic ambiguity where detectable;
- runtime/rule validation before commit.

### Duplicate write policy

For Phase 6R, reject conflicting writes to the same field in one proposal unless they are byte/semantically identical.

Example:

```text
set_integer(age, 31)
set_integer(age, 32)
```

→ reject/diagnose as conflicting model output rather than silently applying last-write-wins.

Identical duplicates may be deterministically deduplicated with a diagnostic.

### Outcomes

Internally support:

```text
ACCEPT
REJECT
CLARIFY
FALLBACK
```

For the initial FunctionGemma benchmark, score the raw extraction before cloud fallback masks failures.

---

# 14. Migration from failed Phase 6

Perform migration in small commits. Do not mix cleanup, new contracts, and model-runtime changes in one large patch.

## Migration M0 — baseline preservation

- tag failed baseline;
- export current Phase 6 benchmark/failing examples;
- capture current test result and representative raw model outputs;
- create recovery branch.

**Gate:** baseline can be reproduced.

## Migration M1 — inventory old intelligence surface

Search the repository for:

```text
set_form_field
navigate
submit
clarification
FunctionGemma
IntelligenceAdapter
SemanticContext
ContextCompiler
QualityGate
ActionProposal
```

Produce `docs/phase6r/OLD_PHASE6_INVENTORY.md` with:

- file/class;
- keep/modify/deprecate/delete;
- dependency impact;
- tests affected.

Do not edit implementation until this inventory exists.

## Migration M2 — SemanticContext v1.1

Add/verify:

- `writable`;
- typed `currentValue`;
- canonical options;
- `optionsTruncated`;
- `revision`;
- `fingerprint`;
- normalized locale;
- bounded aliases/options.

Update codecs/tests. If compatibility with v1.0 is required, provide explicit migration/decoder behavior; do not silently reinterpret incompatible payloads.

**Gate:** ContextCompiler tests pass independently of FunctionGemma.

## Migration M3 — freeze tool protocol

Implement the eight-tool definitions as internal FunctionGemma contracts. Remove generic tool generation from the new path.

**Gate:** JSON-schema/unit tests prove strict primitive shapes.

## Migration M4 — schema specialization

Implement `FunctionGemmaToolSchemaBuilder` and deterministic ordering/canonical encoding.

**Gate:** golden tests for specialized schemas pass.

## Migration M5 — strict parser/validator

Implement raw native call → `FunctionGemmaToolCall` parsing with no coercion.

**Gate:** malformed-output matrix passes.

## Migration M6 — canonical action mapping

Map validated calls to existing canonical `FormAction` only. No direct state mutation.

**Gate:** tool call → canonical action golden tests pass.

## Migration M7 — FunctionGemma context formatter

Formatter consumes `SemanticContext`, not source schema. Keep model formatting inside the adapter package.

Requirements:

- compact;
- deterministic;
- current values included;
- active field clearly represented;
- labels/aliases available;
- choice option IDs + labels/aliases available;
- no diagnostics/selection reasons unless experiment proves useful;
- no full-form dump.

**Gate:** prompt/context snapshots are deterministic and token-budget tests pass.

## Migration M8 — adapter integration

Rebuild `FunctionGemmaAdapter.interpret()` around:

```text
request
 ↓
context formatter
 ↓
specialized tools
 ↓
model inference
 ↓
raw calls
 ↓
strict parser
 ↓
context validation
 ↓
canonical actions
 ↓
ActionProposal(baseRevision=context.revision)
```

**Gate:** Mock/native-fixture tests pass before real model tests.

## Migration M9 — QualityGate + stale handling

Integrate revision/fingerprint behavior. A cache hit must never bypass stale proposal checks.

**Gate:** concurrency tests pass.

## Migration M10 — schema cache

Implement only after correctness. Cache generated/prepared tool schema or tokenized prefix where useful. Do not optimize before benchmark correctness is stable.

**Gate:** cached and uncached inference inputs are semantically identical.

## Migration M11 — benchmark real FunctionGemma

Run frozen corpus. Store raw model output, parsed calls, validation result, canonical actions, expected actions, latency, and failure category.

**Gate:** GO/NO-GO criteria below.

---

# 15. Task sequence for Codex/Cursor

Execute strictly in this order. Stop at every gate and run tests. Do not proceed because code compiles.

## 6R.0 Recovery setup

Deliverables:

- failed-baseline tag;
- recovery branch;
- old Phase 6 inventory;
- `ADR-006-CONSTRAINED-FUNCTIONGEMMA.md`;
- `PHASE_6R_STATUS.md`.

## 6R.1 SemanticContext hardening

Deliverables:

- v1.1 contract;
- codecs;
- writable state;
- option truncation semantics;
- context fingerprint tests;
- bounded context tests.

## 6R.2 Extraction tool protocol

Deliverables:

- eight tool definitions;
- protocol version constant `1.0`;
- strict tool-call DTO;
- JSON schema/golden representation.

## 6R.3 Specialized schema builder

Deliverables:

- field grouping by semantic type;
- writable filtering;
- option ID specialization;
- truncated-option behavior;
- deterministic ordering;
- canonical schema serialization;
- tool-schema fingerprint.

## 6R.4 Strict parser and validator

Deliverables:

- no-coercion parser;
- finite-number validation;
- strict integer validation;
- real ISO date validation;
- choice/multi-choice membership validation;
- unknown field/tool rejection;
- duplicate/conflict handling.

## 6R.5 Canonical action mapper

Deliverables:

- all eight tool mappings;
- ordered multi-call support;
- proposal construction;
- `baseRevision` propagation;
- provenance.

## 6R.6 FunctionGemma formatter/runtime integration

Deliverables:

- compact formatter;
- FunctionGemma native tool definitions;
- native tool-call parser bridge;
- multiple tool calls per turn;
- raw output diagnostics;
- no workflow tools.

## 6R.7 QualityGate integration

Deliverables:

- deterministic validation;
- ACCEPT/REJECT/CLARIFY/FALLBACK internal outcome;
- no cloud fallback during raw benchmark scoring;
- runtime event/trace coverage.

## 6R.8 Revision/fingerprint handling

Deliverables:

- stale proposal rejection/re-evaluation;
- relevant-context fingerprint comparison path;
- tests for unrelated vs relevant state changes;
- no cache/concurrency coupling.

## 6R.9 Schema/prefix caching

Deliverables:

- cache-key contract;
- locale normalization;
- invalidation tests;
- bounded LRU if cache can grow with dynamic choice candidates;
- metrics: hit/miss/build time.

## 6R.10 Evaluation harness

Deliverables:

- frozen corpus;
- deterministic fixtures;
- real-model runner;
- JSON/CSV report;
- failure taxonomy;
- baseline comparison.

## 6R.11 GO/NO-GO review

Deliverables:

- benchmark report;
- failure analysis;
- recommendation: GO FunctionGemma / CONDITIONAL GO / NO-GO;
- no Phase 7 code before decision is recorded.

---

# 16. Unit and integration test plan

## A. SemanticContext tests

Test:

- canonical IDs only;
- current values colocated with fields;
- revision propagation;
- writable true/false;
- active field priority;
- recent field ordering;
- alias caps;
- field/token budgets;
- choice option caps;
- `optionsTruncated`;
- huge form selects bounded context;
- source-schema values do not leak;
- deterministic compilation for identical input.

## B. Schema specialization tests

Given selected fields, assert exact specialized JSON for:

- one field per scalar type;
- multiple integer fields;
- no compatible field → tool omitted;
- read-only field excluded;
- choice with aliases;
- two choice fields with disjoint options;
- multi-choice;
- truncated options;
- option candidate set changes;
- clear_field includes all writable selected fields;
- deterministic ordering.

## C. Strict parser negative matrix

Must reject:

```text
set_integer value="32"
set_integer value=32.5
set_number value="72.5"
set_number NaN/Infinity
set_boolean value="yes"
set_boolean value=1
set_date value="05/10/2026"
set_date value="2026-02-30"
set_choice unknown option
set_choice alias instead of canonical ID
set_multi_choice scalar
set_multi_choice duplicate IDs
set_multi_choice unknown ID
clear_field with value
unknown tool
unknown field
wrong setter for field type
non-writable field
extra properties
missing required properties
```

## D. Action mapping tests

Exact mappings:

```text
set_string       → SetValueAction(StringValue)
set_integer      → SetValueAction(IntegerValue)
set_number       → SetValueAction(NumberValue)
set_boolean      → SetValueAction(BooleanValue)
set_date         → SetValueAction(DateValue)
set_choice       → SetValueAction(ChoiceValue)
set_multi_choice → SetValueAction(MultiChoiceValue)
clear_field      → ClearValueAction
```

## E. Multi-call tests

- preserve order;
- multiple independent fields accepted;
- identical duplicate writes deduplicated/diagnosed;
- conflicting same-field writes rejected;
- one invalid call in best-effort proposal: QualityGate policy explicit; do not silently mutate invalid field;
- partial acceptance behavior tested at ActionRuntime layer.

## F. Revision/concurrency tests

- inference rev17, state remains17 → apply;
- inference rev17, relevant state becomes18 → reject/rerun;
- inference rev17, unrelated state becomes18 and relevant fingerprint unchanged → optional optimized revalidation path;
- bridge expectedRevision always authoritative current target revision;
- cached schema never changes proposal baseRevision.

## G. Cache tests

Expected HIT:

- revision only;
- current scalar value change;
- active field change with same selected mutation surface;
- label/alias change if schema JSON unchanged;
- option label/alias change if IDs unchanged.

Expected MISS:

- selected field added/removed;
- field type change;
- writable change;
- option ID add/remove;
- candidate option set change;
- optionsTruncated change if represented in generated tool definition/fingerprint policy;
- locale change;
- tool protocol version change;
- adapter/schema-builder version change.

---

# 17. Frozen Phase 6R benchmark corpus

Store cases as data, not Dart test code only. Suggested path:

```text
benchmarks/function_gemma_phase6r/
  corpus.v1.jsonl
  README.md
  expected/
  reports/
```

Each case should include:

```json
{
  "id": "compound_age_consent_001",
  "category": "compound",
  "input": "Age thirty two, consent yes",
  "contextFixture": "age_consent.json",
  "expectedCalls": [
    {"name": "set_integer", "arguments": {"field_id": "age", "value": 32}},
    {"name": "set_boolean", "arguments": {"field_id": "consent", "value": true}}
  ]
}
```

## Minimum benchmark categories and examples

### 1. Integer

```text
"Age thirty two"
→ age=32

"There were four registers open"
→ register_count=4
```

### 2. Number

```text
"Weight is seventy two point five kilos"
→ weight_kg=72.5

"Discount is twelve and a half percent"
→ discount_percent=12.5
```

### 3. Boolean

```text
"Yes I consent"
→ consent=true

"No, there is no back room"
→ has_back_room=false
```

### 4. String

```text
"My name is Mukil"
→ name="Mukil"

"City is Bangalore"
→ city="Bangalore"
```

### 5. Date

```text
"Visit date was October fifth 2026"
→ visit_date="2026-10-05"

"DOB is fourteenth August 1992"
→ date_of_birth="1992-08-14"
```

### 6. Choice + aliases

Context option `fall` has alias `autumn`:

```text
"The promotion was autumn"
→ promotion="fall"
```

### 7. Multi-choice

```text
"I use Java and Flutter"
→ technologies=[java,flutter]
```

Existing value `[java]`:

```text
"Also add Flutter and React"
→ technologies=[java,flutter,react]
```

### 8. Clear

Existing `promotion=spring`:

```text
"Clear the promotion"
→ clear_field(promotion)
```

### 9. Corrections

Existing `age=31`:

```text
"Actually I'm thirty two"
→ set_integer(age,32)
```

Do not expect clear+set.

### 10. Compound extraction

```text
"Age thirty two, consent yes"
→ age=32, consent=true

"We have a back room, four registers were open and the promotion was autumn"
→ has_back_room=true
→ register_count=4
→ promotion=fall
```

### 11. Negation

```text
"I do not consent"
→ consent=false

"It wasn't the spring promotion, it was autumn"
→ promotion=fall
```

### 12. Reference/current state

Active/recent field age, current=31:

```text
"Change that to thirty two"
→ age=32
```

Current technologies=[java,flutter]:

```text
"Remove Flutter and keep Java"
→ technologies=[java]
```

### 13. Ambiguous / should not invent

```text
"Maybe four or five"
```

Expected: no confident mutation / QualityGate clarification outcome. Do not score an invented exact number as success.

```text
"The promotion was the other one"
```

Without enough context: no invented option.

### 14. Invalid constraints

Context age min18 max100:

```text
"Age is one hundred and fifty"
```

Model may extract 150, but deterministic validation must reject it. Separate **extraction accuracy** from **commit validity**.

### 15. ASR-like text noise

Examples should be based on plausible transcript errors, e.g.:

```text
"age thirty to consent yes"
"four registers where open"
"promotion was auto man"
```

Do not overfit prompt/schema to these examples. Record whether failures are semantic/model limitations.

### 16. Out-of-context field

Context contains age+consent only:

```text
"My country is India"
```

FunctionGemma must not invent a `country` field ID.

### 17. Option truncation

Country candidates `[india, indonesia]`, truncated=true:

```text
"Japan"
```

Must not emit `japan` because it is not in the permitted candidate set. Runtime may retrieve more candidates/fallback later.

---

# 18. Benchmark metrics

Do not use JSON validity as the primary success metric.

Record at least:

```text
Exact Action Set Accuracy
Field Identification Accuracy
Typed Value Accuracy
Compound Utterance Exact Match
Choice Canonical-ID Accuracy
Multi-choice Exact Set Accuracy
Hallucinated Field Rate
Hallucinated Option Rate
Invalid Tool/Argument Rate
Unnecessary No-Answer/Clarification Rate
Constraint Extraction vs Commit Rejection
TTFT
Total inference latency
Input token count
Output token count
```

### Exact action comparison

Normalize only where semantics permit:

- action ordering may be ignored for independent field mutations in benchmark scoring if runtime semantics are order-independent;
- multi-choice value ordering may be normalized as a set;
- do **not** normalize wrong types, labels to IDs, strings to numbers, or malformed dates. That would hide model failures.

### Failure taxonomy

Every failed case must be assigned one primary category:

```text
CONTEXT_SELECTION
CONTEXT_FORMATTING
FIELD_SELECTION
VALUE_EXTRACTION
TYPE_ERROR
OPTION_MAPPING
MULTI_CHOICE_STATE
NEGATION
REFERENCE_RESOLUTION
MODEL_HALLUCINATION
TOOL_FORMAT
AMBIGUITY_POLICY
CONSTRAINT_REJECTION_EXPECTED
RUNTIME_VALIDATION
UNKNOWN
```

This is necessary before deciding whether to tune FunctionGemma, change context selection, or replace the model.

---

# 19. GO / CONDITIONAL GO / NO-GO gate

The gate is about whether FunctionGemma is viable as the **local extraction engine**, not whether the entire product is viable.

Run the frozen corpus multiple times if decoding is nondeterministic. Prefer deterministic decoding for the baseline if supported.

## Hard correctness requirements

The following are **zero-tolerance safety/correctness requirements** across the gate corpus:

```text
0 unauthorized/out-of-context field IDs accepted
0 unknown option IDs accepted
0 wrong-type calls committed
0 malformed dates committed
0 stale proposals blindly committed
0 raw source-schema IDs leaking into canonical actions
```

These can be guaranteed by deterministic validation even if the model misbehaves.

## Suggested model-quality thresholds for GO

Use these as initial engineering thresholds; record them in config so they can be revised explicitly rather than silently.

```text
Simple single-field exact action accuracy       >= 97%
Boolean exact accuracy                           >= 98%
Integer/number typed-value accuracy              >= 97%
Choice canonical-ID accuracy                     >= 97%
Multi-choice exact-set accuracy                  >= 93%
Compound 2–3 field exact action-set accuracy     >= 92%
Correction/reference cases                       >= 90%
Hallucinated field rate                          <= 1%
Hallucinated option rate                         <= 1%
Malformed tool-call rate                         <= 2%
```

Also require the critical regression case:

```text
"Age thirty two, consent yes"
```

with context containing only compatible `age` and `consent` targets to succeed reliably. Treat repeated failure here as a major negative signal.

Latency thresholds should be set from the target Zebra device/runtime measurements rather than invented in this phase. Record p50/p95 and compare against the product latency budget.

## GO

Choose **GO** when:

- hard correctness requirements pass;
- quality thresholds are met or clearly exceeded;
- failures are sparse/non-systematic;
- latency/memory are viable on target hardware;
- no architecture changes are needed to support normal form domains.

Proceed to Phase 7.

## CONDITIONAL GO

Choose **CONDITIONAL GO** when:

- deterministic safety requirements pass;
- overall extraction is strong;
- one bounded category is below target, e.g. multi-choice correction;
- a deterministic fast path, QualityGate clarification, or cloud fallback can cover it without distorting the architecture;
- failures do not indicate broad domain brittleness.

Document exactly which cases route to fallback/clarification.

## NO-GO

Choose **NO-GO FunctionGemma** if, after the constrained context + specialized tools implementation:

- simple/compound typed extraction remains unreliable;
- field selection is systematically unstable;
- aliases/choice IDs are frequently hallucinated;
- corrections/current-state references fail broadly;
- malformed tool output is frequent enough to destroy UX;
- target-device performance is unacceptable.

A FunctionGemma NO-GO is **not** a project restart.

Replace only:

```text
IntelligenceAdapter implementation
        ↓
NeedleAdapter / alternative SLM / cloud adapter
```

Keep SemanticContext, canonical actions, QualityGate, ActionRuntime, FormStateBridge, benchmark corpus, and most of the specialization/evaluation concepts.

---

# 20. Phase 7 entry criteria

Do not begin Hybrid/Cloud Phase 7 until all are true:

- Phase 6R status marked complete;
- GO/CONDITIONAL GO decision recorded;
- benchmark report committed;
- failed cases categorized;
- no critical TODOs in strict validation;
- revision/stale tests pass;
- FunctionGemma can be disabled/swapped through `IntelligenceAdapter`;
- no model-specific types leak into runtime core;
- raw source schema never reaches intelligence adapters.

Cloud fallback must receive the same compact semantic context philosophy; do not use cloud fallback as an excuse to send the entire source schema.

---

# 21. Required documentation files

Codex/Cursor should create/update:

```text
docs/phase6r/
  README.md
  ADR-006-CONSTRAINED-FUNCTIONGEMMA.md
  OLD_PHASE6_INVENTORY.md
  SEMANTIC_CONTEXT_V1_1.md
  FUNCTIONGEMMA_TOOL_PROTOCOL_V1.md
  TOOL_SCHEMA_SPECIALIZATION.md
  QUALITY_GATE.md
  CACHE_AND_FINGERPRINTS.md
  BENCHMARK_SPEC.md
  GO_NO_GO.md
  PHASE_6R_STATUS.md
```

Do not allow documentation to diverge from implementation. Golden JSON fixtures should be generated/validated by the same codecs/builders used in tests where practical.

---

# 22. Suggested repository layout

Adapt to the current repo rather than moving files unnecessarily.

```text
packages/
  form_assistant_core/
    lib/
      contracts/
      runtime/
      context/

  form_assistant_function_gemma/
    lib/
      adapter/
      context_formatter/
      tools/
        tool_protocol.dart
        tool_schema_builder.dart
        tool_schema_encoder.dart
        tool_call.dart
        tool_call_parser.dart
        tool_call_validator.dart
      cache/
      diagnostics/

    test/
      tools/
      formatter/
      adapter/
      fixtures/

benchmarks/
  function_gemma_phase6r/
    corpus.v1.jsonl
    contexts/
    reports/

docs/phase6r/
```

If the existing package boundaries differ, preserve them unless there is a concrete dependency problem. This phase is not a repository-layout rewrite.

---

# 23. Codex/Cursor execution rules

Paste/use the following as the execution directive.

```text
You are implementing Phase 6R of an existing form-assistant runtime.
Phases 0–5 are already implemented and must not be rewritten.
The previous Phase 6 failed and is preserved as a baseline.

Goal:
Rebuild only the intelligence integration so FunctionGemma 270M is evaluated as a constrained semantic slot extractor.

Hard architecture rules:
1. FormStateBridge remains authoritative for state commits.
2. FunctionGemma never mutates state directly.
3. FunctionGemma receives SemanticContext, never the raw source schema.
4. Only these model tools are permitted in the Phase 6R extraction path:
   set_string, set_integer, set_number, set_boolean, set_date,
   set_choice, set_multi_choice, clear_field.
5. Generate field_id and option constraints dynamically from the exact SemanticContext.
6. Parse model output strictly. Do not coerce strings to numbers/bools/dates.
7. Map validated calls to existing canonical FormAction types.
8. Preserve revision -> SemanticContext -> ActionProposal.baseRevision -> ApplyContext.expectedRevision.
9. Schema caching must never bypass stale-result validation.
10. Keep FunctionGemma-specific formatting/schema/runtime code outside runtime core.
11. Do not implement Phase 7 cloud fallback or Phase 8 STT in this work.
12. Do not add workflow tools to improve benchmark results.
13. Do not fine-tune FunctionGemma during the initial Phase 6R benchmark.
14. Do not alter benchmark expected outputs to match model failures.

Execution method:
- Inspect existing code before editing.
- Create OLD_PHASE6_INVENTORY.md.
- Implement tasks 6R.0 through 6R.11 sequentially.
- At every task, run targeted tests and the full relevant test suite.
- Stop and fix failures before moving to the next task.
- Make small commits aligned to the task boundaries.
- Update PHASE_6R_STATUS.md after every completed task.
- Preserve raw benchmark outputs and failure classifications.
- Do not proceed to Phase 7. End with a GO / CONDITIONAL GO / NO-GO report.

When an existing implementation conflicts with this plan:
- preserve canonical runtime/state contracts unless clearly broken;
- replace model-specific Phase 6 behavior;
- document the conflict and chosen migration in PHASE_6R_STATUS.md;
- do not silently redesign unrelated components.
```

---

# 24. Definition of done

Phase 6R is complete only when:

```text
[ ] failed Phase 6 baseline is tagged/reproducible
[ ] architecture delta documented
[ ] SemanticContext v1.1 implemented/tested
[ ] eight-tool extraction protocol frozen
[ ] runtime specialization implemented/tested
[ ] strict no-coercion parser implemented/tested
[ ] tool→canonical FormAction mapping implemented/tested
[ ] FunctionGemma receives only compact SemanticContext
[ ] multiple tool calls work
[ ] choice aliases resolve to canonical IDs
[ ] multi-choice replacement semantics work
[ ] stale proposal handling works
[ ] schema fingerprint/cache invalidation works
[ ] benchmark corpus is frozen
[ ] real FunctionGemma benchmark executed
[ ] raw outputs/reports preserved
[ ] failures classified
[ ] GO / CONDITIONAL GO / NO-GO decision recorded
[ ] Phase 7 remains untouched until gate decision
```

---

# 25. Final architectural checkpoint

At the end of Phase 6R, the system should look like this:

```text
                    SOURCE FORM SCHEMA
                           │
                      FormAdapter
                           │
                           ▼
                         FormIR
                           │
              ┌────────────┴────────────┐
              │                         │
        existing renderer         Form Runtime Core
                                        │
                              FormStateSnapshot
                                        │
User text/voice transcript ───────► ContextCompiler
                                        │
                                        ▼
                                SemanticContext
                              rev / fp / locale
                                        │
                                        ▼
                          FunctionGemmaToolSchemaBuilder
                                        │
                              constrained 8 tools
                                        │
                                        ▼
                                FunctionGemma
                                        │
                                  typed calls
                                        │
                                        ▼
                          strict parser + validator
                                        │
                                        ▼
                               canonical FormAction
                                        │
                                        ▼
                                  QualityGate
                                        │
                                        ▼
                                 ActionProposal
                                  baseRevision
                                        │
                                        ▼
                                  ActionRuntime
                                        │
                                        ▼
                                FormStateBridge
                              /                 \
                    External bridge        Local bridge
```

The key success criterion is not that FunctionGemma becomes a general agent. It is that a tiny on-device model can reliably perform a narrow semantic transformation while every consequential operation remains deterministic and model-independent.

---

## Phase 6R decision record

At completion fill this section in rather than creating an undocumented verbal decision:

```text
Date:
Commit:
Device/runtime:
Model artifact/version:
Corpus version:
Cases executed:

Simple exact accuracy:
Compound exact accuracy:
Choice accuracy:
Multi-choice accuracy:
Hallucinated field rate:
Hallucinated option rate:
Malformed call rate:
p50 latency:
p95 latency:
Peak memory:

Decision: GO / CONDITIONAL GO / NO-GO

Primary failure categories:
1.
2.
3.

Required follow-up:

Phase 7 permitted: YES / NO
```

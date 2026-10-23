# Phase 12 — Multilingual semantics and React bindings

Started 2026-10-23. This completes the written plan. Canonical actions and
field ids are unchanged.

## Localized semantics

`FieldSemantics` and `FormOption` accept `localizedLabels` and
`localizedAliases`, keyed by a normalized locale (`en_IN` becomes `en-in`).
Both maps are omitted from JSON when empty, so existing FormIR goldens stay
valid. `labelFor` uses the locale, then its language, then the base label.
The base label is not an identity: when a locale has its own label, choice
matching uses that label and the option id. The written value is still the id.

`NativeForm.project` takes an optional locale and paints `labelFor`. The
Flutter renderer forwards the same locale and still does not call a model.

## Speech, intelligence, and code switching

`FormAssistantRuntime.locale` defaults to `en`. `submit` can override it.
The compiled `SemanticContext` carries that locale, and localized labels are
included in the model context when present. A final STT segment submits with
the session locale. Partials still do not commit.

English whole-utterance routing is unchanged. After it declines an utterance,
`evaluateCodeSwitch` may commit only when a non-English lexicon contributed.
Built-in tables cover English and a small Spanish set (yes/no, numbers through
fifteen, tens, `siguiente` / `anterior`). `thirty dos` is mixed and writes
integer 32. `thirty and two` stays with the model. The action JSON has no
locale field.

## React

`contracts/schemas/` is the language-independent contract.
`bindings/form_assistant_react` decodes protocol 1.0 actions and drops unknown
fields such as `locale`. It does not reimplement the runtime and does not add
React-specific action shapes.

Gate: `packages/form_assistant_core/test/phase12_gate_test.dart` (6 tests).
Core suite is 139 tests. Decoder check:
`node --experimental-strip-types bindings/form_assistant_react/src/protocol.test.ts`.

Phase 12 is the last phase in the written plan.

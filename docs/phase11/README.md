# Phase 11 — Native form platform

Started 2026-10-23. This is not required for an existing-form integration.
The local bridge still owns canonical state. No new value types were added.

## Rules and workflow

`NativeForm` adds visibility rules and an ordered workflow on top of a `FormIR`.

A `FieldVisibilityRule` shows its field only when another field currently
equals a canonical value. A hidden field is omitted from the current step.
Writing it, or navigating to it, fails in `ActionRuntime` with
`rule.field_hidden` and does not change the revision. A stored value is left
in place when the field later becomes hidden.

`FormWorkflow` lists every field in exactly one step. The current step is the
first step that still has a visible required field with no value. The
projection is `NativeFormView`: labels, values, visibility, and step index.
It is data, not a widget.

## One action path

`FormAssistantRuntime.commitNative` builds a user-origin proposal and runs
`executeProposal`. It does not call the intelligence adapter. A spoken answer
that the input router understands uses that same action runtime. An utterance
the router cannot resolve still goes to the model. Manual UI and AI therefore
meet at `ActionRuntime` and the bridge.

## Flutter renderer

`NativeFormRenderer` paints the current step from the bridge snapshot: a
switch for a boolean, a dropdown or checkboxes for choices, and a text field
for string, integer, number, and date. Edits are `FormAction`s passed to the
host callback, which should be `commitNative`. The widget does not call a
model and does not replace an existing source form.

Existing-form chrome from Phase 9 is unchanged.

Gate: `packages/form_assistant_core/test/phase11_gate_test.dart` (3 tests)
and `packages/form_assistant_flutter/test/native_form_renderer_test.dart`.
Core suite is 133 tests.

Phase 12 multilingual semantics and React bindings have started. See [Phase 12](../phase12/README.md).

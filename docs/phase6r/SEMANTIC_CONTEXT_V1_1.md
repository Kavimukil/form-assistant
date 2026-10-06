# SemanticContext v1.1

Explicit `specVersion=1.1` codec; unknown/legacy serialized versions rejected.
Existing constructor and fields/values accessors remain source-compatible with
Phases 0–5. FormFieldContext is also named SemanticFieldContext; it exposes type,
label/concept/aliases, typed currentValue, constraints, canonical options, writable
and optionsTruncated. Runtime canonical FormField access is retained.

Compilation caps fields (16), estimated tokens (768), recent IDs (5), aliases (6),
options (32) and field semantic characters (512). Oversized mandatory fields fail
closed instead of destroying meaning by truncation. Current answer text is never
silently truncated. Option/alias candidates are capped explicitly; supplied options
alone define permitted outputs. Read-only lifecycle produces non-writable fields.
Individual writable flags may also be supplied by semantic-context callers; the
existing FormIR has no per-field authorization contract to infer one from.

Fingerprint is exact sorted canonical JSON with a `canonical-json:` prefix, not
a probabilistic hash or authorization token. It excludes revision/form identity and
diagnostics; includes selected fields, values, locale, active/recent references.
This avoids adding a hashing dependency to the dependency-free core. The fingerprint
is adapter metadata and is never repeated into the model prompt. Legacy conservative
compiler costing includes escaped fields/values/history and v1.1 writable/truncation
metadata; token counts are estimates, not tokenizer measurements.

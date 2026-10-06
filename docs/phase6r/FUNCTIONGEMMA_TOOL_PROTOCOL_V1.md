# Extraction protocol v1.0

Exactly set_string, set_integer, set_number, set_boolean, set_date, set_choice,
set_multi_choice and clear_field. Strict immutable `{name, arguments}` DTOs;
field_id is nonempty, exactly typed values, finite numbers, actual ISO dates,
unique multi-choice IDs; clear_field has no value. No workflow/clarification tool.
JSON schema golden: adapter test/fixtures/extraction_protocol.v1.json, generated
by tool/protocol_golden.dart from production primitive schema encoder. Context
membership and cross-field option correlation are validated after decoding.

# Form action decoder for a React host

This package decodes the canonical protocol 1.0 JSON in `contracts/schemas/`.
A React screen sends those actions to the host that owns form state. It does
not reimplement the Dart runtime, and it does not add React-specific action
fields.

`decodeAction` drops unknown optional fields, including `locale`. Field ids and
value types stay the ones in the schema.

```sh
node --experimental-strip-types src/protocol.test.ts
```

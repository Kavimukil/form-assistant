import assert from "node:assert/strict";
import { decodeAction, protocolSpecVersion } from "./protocol.ts";

const action = decodeAction({
  type: "set_value",
  fieldId: "age",
  locale: "es",
  value: { type: "integer", value: 32, locale: "es" },
});

assert.equal(protocolSpecVersion, "1.0");
assert.deepEqual(action, {
  type: "set_value",
  fieldId: "age",
  value: { type: "integer", value: 32 },
});
assert.equal("locale" in action, false);
assert.throws(() => decodeAction({ type: "delete_form" }));

/** Canonical protocol 1.0. Unknown optional fields, including locale, are dropped. */

export const protocolSpecVersion = "1.0";

export type FormValue =
  | { type: "string"; value: string }
  | { type: "integer"; value: number }
  | { type: "number"; value: number }
  | { type: "boolean"; value: boolean }
  | { type: "date"; value: string }
  | { type: "choice"; value: string }
  | { type: "multi_choice"; value: string[] };

export type NavigationTarget =
  | { type: "field"; fieldId: string }
  | { type: "next" }
  | { type: "previous" };

export type FormAction =
  | { type: "set_value"; fieldId: string; value: FormValue }
  | { type: "clear_value"; fieldId: string }
  | { type: "navigate"; target: NavigationTarget }
  | {
      type: "request_clarification";
      reason: string;
      fieldIds?: string[];
      detail?: string;
    };

function record(input: unknown): Record<string, unknown> {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    throw new TypeError("Expected a JSON object");
  }
  return input as Record<string, unknown>;
}

function text(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`Expected non-empty ${name}`);
  }
  return value;
}

export function decodeValue(input: unknown): FormValue {
  const raw = record(input);
  switch (raw.type) {
    case "string":
      return { type: "string", value: text(raw.value, "string") };
    case "integer":
      if (typeof raw.value !== "number" || !Number.isSafeInteger(raw.value)) {
        throw new TypeError("Expected a safe integer");
      }
      return { type: "integer", value: raw.value };
    case "number":
      if (typeof raw.value !== "number" || !Number.isFinite(raw.value)) {
        throw new TypeError("Expected a finite number");
      }
      return { type: "number", value: raw.value };
    case "boolean":
      if (typeof raw.value !== "boolean") throw new TypeError("Expected a boolean");
      return { type: "boolean", value: raw.value };
    case "date":
      if (typeof raw.value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(raw.value)) {
        throw new TypeError("Expected a calendar date");
      }
      return { type: "date", value: raw.value };
    case "choice":
      return { type: "choice", value: text(raw.value, "choice") };
    case "multi_choice":
      if (!Array.isArray(raw.value) || raw.value.some((item) => typeof item !== "string" || item === "")) {
        throw new TypeError("Expected choice ids");
      }
      return { type: "multi_choice", value: [...raw.value] };
    default:
      throw new TypeError("Unknown value type");
  }
}

export function decodeAction(input: unknown): FormAction {
  const raw = record(input);
  switch (raw.type) {
    case "set_value":
      return {
        type: "set_value",
        fieldId: text(raw.fieldId, "fieldId"),
        value: decodeValue(raw.value),
      };
    case "clear_value":
      return { type: "clear_value", fieldId: text(raw.fieldId, "fieldId") };
    case "navigate": {
      const target = record(raw.target);
      if (target.type === "field") {
        return { type: "navigate", target: { type: "field", fieldId: text(target.fieldId, "fieldId") } };
      }
      if (target.type === "next" || target.type === "previous") {
        return { type: "navigate", target: { type: target.type } };
      }
      throw new TypeError("Unknown navigation target");
    }
    case "request_clarification": {
      const reason = text(raw.reason, "reason");
      if (!["ambiguous", "missing_information", "invalid_value", "low_confidence"].includes(reason)) {
        throw new TypeError("Unknown clarification reason");
      }
      const action: FormAction = { type: "request_clarification", reason };
      if (raw.fieldIds !== undefined) {
        if (!Array.isArray(raw.fieldIds)) throw new TypeError("Expected field ids");
        action.fieldIds = raw.fieldIds.map((item) => text(item, "fieldId"));
      }
      if (raw.detail !== undefined) action.detail = text(raw.detail, "detail");
      return action;
    }
    default:
      throw new TypeError("Unknown action type");
  }
}

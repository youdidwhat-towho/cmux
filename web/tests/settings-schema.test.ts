import { describe, expect, test } from "bun:test";
import schema from "../data/cmux-settings.schema.json";

type SchemaNode = {
  $ref?: string;
  oneOf?: SchemaNode[];
  type?: string | string[];
  enum?: unknown[];
  pattern?: string;
  properties?: Record<string, SchemaNode>;
  propertyNames?: SchemaNode;
  additionalProperties?: boolean | SchemaNode;
  minItems?: number;
  maxItems?: number;
  items?: SchemaNode;
  prefixItems?: SchemaNode[];
};

const rootSchema = schema as SchemaNode & { $defs?: Record<string, SchemaNode> };

function resolveRef(ref: string): SchemaNode {
  const prefix = "#/$defs/";
  if (!ref.startsWith(prefix)) {
    throw new Error(`Unsupported schema ref: ${ref}`);
  }

  const resolved = rootSchema.$defs?.[ref.slice(prefix.length)];
  if (!resolved) {
    throw new Error(`Unknown schema ref: ${ref}`);
  }
  return resolved;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function matchesType(value: unknown, type: string): boolean {
  switch (type) {
    case "array":
      return Array.isArray(value);
    case "boolean":
      return typeof value === "boolean";
    case "integer":
      return Number.isInteger(value);
    case "null":
      return value === null;
    case "object":
      return isRecord(value);
    case "string":
      return typeof value === "string";
    default:
      throw new Error(`Unsupported schema type: ${type}`);
  }
}

function validateSchemaValue(value: unknown, node: SchemaNode): boolean {
  if (node.$ref) {
    return validateSchemaValue(value, resolveRef(node.$ref));
  }

  if (node.oneOf) {
    return node.oneOf.filter((option) => validateSchemaValue(value, option)).length === 1;
  }

  if (node.enum && !node.enum.some((candidate) => Object.is(candidate, value))) {
    return false;
  }

  if (node.type) {
    const types = Array.isArray(node.type) ? node.type : [node.type];
    if (!types.some((type) => matchesType(value, type))) {
      return false;
    }
  }

  if (node.pattern) {
    if (typeof value !== "string") return false;
    if (!new RegExp(node.pattern, "u").test(value)) return false;
  }

  if (Array.isArray(value)) {
    if (node.minItems !== undefined && value.length < node.minItems) return false;
    if (node.maxItems !== undefined && value.length > node.maxItems) return false;

    if (node.prefixItems) {
      for (let index = 0; index < value.length; index += 1) {
        const itemSchema = node.prefixItems[index] ?? node.items;
        if (!itemSchema || !validateSchemaValue(value[index], itemSchema)) {
          return false;
        }
      }
      return true;
    }

    if (node.items) {
      return value.every((item) => validateSchemaValue(item, node.items!));
    }
  }

  if (isRecord(value)) {
    if (node.propertyNames) {
      for (const key of Object.keys(value)) {
        if (!validateSchemaValue(key, node.propertyNames)) {
          return false;
        }
      }
    }

    const properties = node.properties ?? {};
    for (const [key, propertyValue] of Object.entries(value)) {
      const propertySchema = properties[key];
      if (propertySchema) {
        if (!validateSchemaValue(propertyValue, propertySchema)) {
          return false;
        }
        continue;
      }

      if (node.additionalProperties === false) {
        return false;
      }
      if (typeof node.additionalProperties === "object") {
        if (!validateSchemaValue(propertyValue, node.additionalProperties)) {
          return false;
        }
      }
    }
  }

  return true;
}

function validatesSettings(candidate: unknown): boolean {
  return validateSchemaValue(candidate, rootSchema);
}

function settingsWithBinding(binding: unknown): unknown {
  return {
    shortcuts: {
      bindings: {
        toggleSplitZoom: binding,
      },
    },
  };
}

describe("cmux settings schema shortcuts", () => {
  test("accepts Space key names in shortcut bindings", () => {
    expect(validatesSettings(settingsWithBinding("cmd+shift+space"))).toBe(true);
    expect(validatesSettings(settingsWithBinding("cmd+shift+Space"))).toBe(true);
    expect(validatesSettings(settingsWithBinding("cmd+shift+<space>"))).toBe(true);
    expect(validatesSettings(settingsWithBinding(["ctrl+b", "space"]))).toBe(true);
  });

  test("rejects unknown shortcut key names", () => {
    expect(validatesSettings(settingsWithBinding("cmd+shift+definitelyNotAKey"))).toBe(false);
  });
});

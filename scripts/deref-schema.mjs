// Inline every #/$defs/* $ref (and strip additionalProperties:false — the
// generated runtime validators are deliberately tolerant; ajv in repo CI is
// the strict gate) so codegen tools that don't resolve refs
// (json-schema-to-zod) still see the full constraint. CI feeds codegen the
// derefed copy; schema/waterx-config.schema.json stays the canonical, ref'd SSOT.
import { readFileSync, writeFileSync } from "node:fs";
const schema = JSON.parse(readFileSync(process.argv[2], "utf8"));
const defs = schema.$defs ?? {};
function deref(node) {
  if (Array.isArray(node)) return node.map(deref);
  if (node && typeof node === "object") {
    if (typeof node.$ref === "string" && node.$ref.startsWith("#/$defs/")) {
      const name = node.$ref.slice("#/$defs/".length);
      if (!defs[name]) throw new Error(`unknown $def ${name}`);
      const { $ref, ...rest } = node;
      return { ...deref(defs[name]), ...deref(rest) };
    }
    const entries = Object.entries(node)
      .filter(([k, v]) => !(k === "additionalProperties" && v === false))
      .map(([k, v]) => [k, k === "$defs" ? v : deref(v)]);
    return Object.fromEntries(entries);
  }
  return node;
}
const out = deref(schema);
delete out.$defs;
writeFileSync(process.argv[3], JSON.stringify(out, null, 2));
console.log(`derefed -> ${process.argv[3]}`);

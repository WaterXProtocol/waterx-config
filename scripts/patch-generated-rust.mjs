// Post-generation patch for quicktype's Rust output: rename the root type.
// Deliberately NO deny_unknown_fields: consumers parse live CDN data that can
// gain fields before their pinned crate does — serde's default (ignore
// unknown) is what keeps an additive config change from breaking deployed
// consumers. Strict validation is the config repo's own ajv gate.
import { readFileSync, writeFileSync } from "node:fs";
const p = new URL("../packages/rust/src/generated.rs", import.meta.url);
let s = readFileSync(p, "utf8");
if (s.includes("pub struct Generated")) s = s.replaceAll("Generated", "WaterxConfig");
writeFileSync(p, s);
console.log("generated.rs patched (root rename + deny_unknown_fields)");

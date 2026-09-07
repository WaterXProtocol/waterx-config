// Post-generation patch for quicktype's Rust output: rename the root type and
// make every struct strict (deny_unknown_fields) — unknown fields failing to
// parse is the entire point of this crate.
import { readFileSync, writeFileSync } from "node:fs";
const p = new URL("../packages/rust/src/generated.rs", import.meta.url);
let s = readFileSync(p, "utf8");
if (s.includes("pub struct Generated")) s = s.replaceAll("Generated", "WaterxConfig");
s = s.replaceAll(
  "#[derive(Debug, Clone, Serialize, Deserialize)]\npub struct",
  "#[derive(Debug, Clone, Serialize, Deserialize)]\n#[serde(deny_unknown_fields)]\npub struct",
);
writeFileSync(p, s);
console.log("generated.rs patched (root rename + deny_unknown_fields)");

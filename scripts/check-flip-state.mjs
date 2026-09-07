// Repo-state gate: the flip is DONE — both served files must declare the
// consolidated shape, and no legacy artifact may resurface.
import { existsSync, readFileSync } from "node:fs";

const root = new URL("..", import.meta.url);
let failures = 0;
for (const net of ["mainnet", "testnet"]) {
  const v = JSON.parse(readFileSync(new URL(`${net}.json`, root), "utf8")).schema_version;
  if (v !== 2) {
    console.error(`FAIL: ${net}.json declares schema_version ${v} — this repo serves the consolidated shape (2) only`);
    failures++;
  }
}
const LEGACY_ARTIFACTS = [
  "schema/waterx-config-target.schema.json", // the target schema IS waterx-config.schema.json now
  "packages/ts/src/schema-legacy.ts",
  "packages/ts/src/lift.mjs",
  "packages/rust/src/lift.rs",
  "packages/rust/src/generated_legacy.rs",
  "scripts/derive-target.mjs",
  "scripts/gen_target_schema.py",
  "docs/FIELDS-TARGET.md",
];
for (const p of LEGACY_ARTIFACTS) {
  if (existsSync(new URL(p, root))) {
    console.error(`FAIL: legacy artifact resurfaced: ${p}`);
    failures++;
  }
}
console.log(failures ? `flip-state: ${failures} failure(s)` : "flip-state: consolidated shape, no legacy artifacts");
process.exit(failures ? 1 : 0);

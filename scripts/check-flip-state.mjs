// Repo-state gate: no legacy artifact of the pre-flip era may resurface
// (e.g. via a revert of the flip commit). The schema_version pin itself is
// NOT re-checked here — ajv (schema enum) and both parsers already enforce it
// in the same CI job. This is a migration-window tripwire, not a permanent
// invariant: delete the script once no live branch predates the flip.
import { existsSync } from "node:fs";

const root = new URL("..", import.meta.url);
let failures = 0;
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

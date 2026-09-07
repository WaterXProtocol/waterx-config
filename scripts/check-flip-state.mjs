// Flip-coherence gate: the repo must be in exactly one mode. Pre-flip the
// legacy artifacts are load-bearing; post-flip they are contraband — this is
// what turns docs/FLIP-PLAN.md's cleanup checklist from prose into CI.
import { existsSync, readFileSync } from "node:fs";

const root = new URL("..", import.meta.url);
const flipped = ["mainnet", "testnet"].map((n) =>
  (JSON.parse(readFileSync(new URL(`${n}.json`, root), "utf8")).schema_version ?? 1) >= 2);
if (flipped[0] !== flipped[1]) {
  console.error("FAIL: mainnet and testnet declare different shapes — flip both in one commit");
  process.exit(1);
}
const LEGACY_ARTIFACTS = [
  "schema/waterx-config.schema.json",
  "packages/ts/src/schema-legacy.ts",
  "packages/ts/src/lift.mjs",
  "packages/rust/src/lift.rs",
  "docs/FIELDS.md",
  "scripts/gen_schema.py",
];
const missing = LEGACY_ARTIFACTS.filter((p) => !existsSync(new URL(p, root)));
if (!flipped[0] && missing.length) {
  console.error(`FAIL: pre-flip, legacy artifacts are load-bearing but missing: ${missing.join(", ")}`);
  process.exit(1);
}
if (flipped[0] && missing.length !== LEGACY_ARTIFACTS.length) {
  const leftover = LEGACY_ARTIFACTS.filter((p) => existsSync(new URL(p, root)));
  console.error(`FAIL: post-flip, delete the legacy artifacts (and rename the target schema to waterx-config.schema.json): ${leftover.join(", ")}`);
  process.exit(1);
}
console.log(`flip-state coherent: ${flipped[0] ? "TARGET (post-flip)" : "LEGACY (pre-flip)"}`);

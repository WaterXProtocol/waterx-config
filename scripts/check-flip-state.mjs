// Repo-state gate: nothing of the pre-flip era may resurface — neither the
// two-format tooling FILES (a revert of the flip commit) nor the legacy READ
// PATHS in the served DATA (a partial revert or a cherry-pick that restores
// old-shaped mainnet.json/testnet.json under the unchanged filenames; review
// finding: the filename list alone misses that case). The schema_version pin
// itself is NOT re-checked here — ajv (schema enum) and both parsers already
// enforce it in the same CI job. This is a migration-window tripwire, not a
// permanent invariant: delete the script once no live branch predates the flip.
import { existsSync, readFileSync } from "node:fs";

const root = new URL("..", import.meta.url);
let failures = 0;

// The old shape's signature read paths (from docs/FLIP-PLAN.md's path map).
const LEGACY_DATA_PATHS = [
  // (the packages themselves stay — as pure identity blocks; the legacy
  // signature is their domain FIELDS)
  "packages/waterx_rule/feeds",
  "packages/pyth_rule/feeds",
  "packages/pyth_rule/config",
  "packages/pyth_lazer_rule/feeds",
  "packages/constant_rule/feeds",
  "packages/supra_rule/feeds",
  "packages/waterx_oracle/aggregators",
  "packages/waterx_perp/markets",
  "packages/wlp/wlp_pool",
  "deploy_tx_log",
];
const dig = (doc, path) => path.split("/").reduce((o, k) => o?.[k], doc);
for (const net of ["mainnet", "testnet"]) {
  const doc = JSON.parse(readFileSync(new URL(`${net}.json`, root), "utf8"));
  for (const p of LEGACY_DATA_PATHS) {
    if (dig(doc, p) !== undefined) {
      console.error(`FAIL: ${net}.json carries the legacy read path ${p} — the pre-flip shape resurfaced`);
      failures++;
    }
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

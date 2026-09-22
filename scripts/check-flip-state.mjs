// Repo-state gate: nothing deliberately removed may resurface — neither the
// two-format tooling FILES of the pre-flip era (a revert of the flip commit)
// nor any REMOVED READ PATH in the served DATA (a partial revert or a
// cherry-pick that restores an old-shaped mainnet.json/testnet.json under the
// unchanged filenames; review finding: the filename list alone misses that
// case). The schema_version pin itself is NOT re-checked here — ajv (schema
// enum) and both parsers already enforce it in the same CI job.
//
// PERMANENT, not a migration-window tripwire: the schema is regenerated FROM
// the data, so a resurfaced block would regenerate a schema that accepts it
// and nothing else would notice. LEGACY_DATA_PATHS is the repo's removed-path
// ledger (venue_feeds, coin_registry, oracle_rules/pyth joined it after the
// flip); only LEGACY_ARTIFACTS is genuinely pre-flip and could be retired once
// no live branch predates the flip.
import { existsSync, readFileSync } from "node:fs";

const root = new URL("..", import.meta.url);
let failures = 0;

// Every DELIBERATELY-REMOVED path — the pre-flip shape's signature read
// paths (from docs/FLIP-PLAN.md's path map) plus later removals. A removal
// PR appends its path here, the same way required-anchors demands an anchor
// be removed alongside its field; a revert or cherry-pick from any older
// branch then fails loudly instead of resurfacing the field.
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
  // removed 2026-09-09 (not pre-flip): venue composition → quote-service BBO
  // config (quote-center #191); coin_registry was the Sui system constant 0xc
  "oracle_rules/waterx/venue_feeds",
  "coin_registry",
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

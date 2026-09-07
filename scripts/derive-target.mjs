// Flip tooling over the shared lift (packages/ts/src/lift.mjs — the ONE
// mapping implementation, also used by the parser pre-flip).
//
//   node scripts/derive-target.mjs check          CI: lift both networks, print a digest (throws on unmapped fields)
//   node scripts/derive-target.mjs emit <dir>     write lifted target docs to <dir>/<net>.json (schema gen, inspection)
//   node scripts/derive-target.mjs flip           FLIP DAY: overwrite mainnet.json/testnet.json with the target shape
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { liftToTarget } from "../packages/ts/src/lift.mjs";

const root = new URL("..", import.meta.url);
const mode = process.argv[2];
const outDir = process.argv[3];
if (!["check", "emit", "flip"].includes(mode)) throw new Error("usage: derive-target.mjs check|emit <dir>|flip");

for (const net of ["mainnet", "testnet"]) {
  const legacy = JSON.parse(readFileSync(new URL(`${net}.json`, root), "utf8"));
  if (legacy.schema_version >= 2) {
    console.log(`${net}: already target shape — nothing to do`);
    continue;
  }
  const { doc, forensics } = liftToTarget(legacy);
  if (forensics.deploy_tx_log.length || Object.keys(forensics.package_publish).length) {
    // legacy forensics reappeared in the hot path — route them back out
    mkdirSync(new URL("deploys", root), { recursive: true });
    writeFileSync(new URL(`deploys/${net}.json`, root), JSON.stringify(forensics, null, 2) + "\n");
    console.log(`${net}: legacy forensics routed to deploys/${net}.json`);
  }
  const body = JSON.stringify(doc, null, 2) + "\n";
  if (mode === "emit") {
    mkdirSync(new URL(outDir, root), { recursive: true });
    writeFileSync(new URL(`${outDir}/${net}.json`, root), body);
    console.log(`${net}: emitted ${outDir}/${net}.json`);
  } else if (mode === "flip") {
    writeFileSync(new URL(`${net}.json`, root), body);
    console.log(`${net}: FLIPPED to target shape`);
  } else {
    console.log(`${net}: lift clean — ${Object.keys(doc.symbols).length} symbols, rules: ${Object.keys(doc.oracle_rules).join(", ")}`);
  }
}

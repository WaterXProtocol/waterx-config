// Flip tooling over the shared lift (packages/ts/src/lift.mjs — the ONE
// mapping implementation, also used by the parser pre-flip).
//
//   node scripts/derive-target.mjs emit <dir>   lift both networks into <dir>/<net>.json
//                                               (CI losslessness gate + schema-gen input)
//   node scripts/derive-target.mjs flip         FLIP DAY: overwrite mainnet.json/testnet.json
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { liftToTarget } from "../packages/ts/src/lift.mjs";

const root = new URL("..", import.meta.url);
const [mode, outDir] = process.argv.slice(2);
if (!(mode === "flip" || (mode === "emit" && outDir))) throw new Error("usage: derive-target.mjs emit <dir>|flip");

for (const net of ["mainnet", "testnet"]) {
  const legacy = JSON.parse(readFileSync(new URL(`${net}.json`, root), "utf8"));
  if (legacy.schema_version >= 2) {
    console.log(`${net}: already target shape — nothing to do`);
    continue;
  }
  const doc = liftToTarget(legacy); // strict: an unmapped legacy field fails the PR
  const body = JSON.stringify(doc, null, 2) + "\n";
  if (mode === "flip") {
    writeFileSync(new URL(`${net}.json`, root), body);
    console.log(`${net}: FLIPPED to target shape`);
  } else {
    mkdirSync(new URL(outDir, root), { recursive: true });
    writeFileSync(new URL(`${outDir}/${net}.json`, root), body);
    console.log(`${net}: emitted ${outDir}/${net}.json — ${Object.keys(doc.symbols).length} symbols, rules: ${Object.keys(doc.oracle_rules).join(", ")}`);
  }
}

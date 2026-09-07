// Keyspace + cross-network consistency gate (audit P2/P4).
//
// The symbol-keyed map inventory comes from schema/map-paths.json — the ONE
// registry (also consumed by the schema generators), so a new map is declared
// once and checked everywhere. Works on both shapes: each network file is
// checked against the map paths of the shape it declares, so this gate
// survives the flip unchanged. Exceptions stay keyed by the map's LEGACY path
// in schema/coverage-exceptions.json (the registry translates), so the
// reviewed exception list survives the flip too.
import { existsSync, readFileSync } from "node:fs";

const root = new URL("..", import.meta.url);
const read = (p) => JSON.parse(readFileSync(new URL(p, root), "utf8"));
const registry = read("schema/map-paths.json").maps;
const exceptions = read("schema/coverage-exceptions.json");

let failures = 0;
const fail = (msg) => { console.error(`FAIL ${msg}`); failures++; };
const ok = (msg) => console.log(`  ok ${msg}`);

const dig = (doc, path) => path.split("/").reduce((o, k) => o?.[k], doc);

for (const net of ["mainnet", "testnet"]) {
  const doc = read(`${net}.json`);
  const target = (doc.schema_version ?? 1) >= 2;
  const shape = target ? "target" : "legacy";
  const base = new Set(Object.keys(
    target ? (doc.symbols ?? {}) : (doc.packages?.waterx_rule?.feeds ?? {}),
  ));
  for (const entry of registry) {
    if (entry.base !== "symbols") continue;
    const map = dig(doc, entry[shape]);
    if (!map) continue;
    const allowed = new Set(exceptions[net]?.[entry.legacy] ?? []);
    const extra = Object.keys(map).filter((s) => !base.has(s) && !allowed.has(s));
    if (extra.length) fail(`${net} (${shape}): ${entry[shape]} has symbols outside the universe and not excepted: ${extra.join(", ")}`);
    else ok(`${net} (${shape}): ${entry[shape]} ⊆ universe (+${allowed.size} excepted)`);
  }

  // cross-network field drift only applies to the legacy shape's free-form
  // packages; the target shape's packages are uniform by schema.
}

// field drift between networks (legacy shape only — target packages are uniform)
const m = read("mainnet.json");
const t = read("testnet.json");
if ((m.schema_version ?? 1) < 2 && (t.schema_version ?? 1) < 2) {
  const driftAllow = new Set(exceptions.field_drift ?? []);
  for (const p of Object.keys(m.packages).filter((p) => p in t.packages)) {
    const a = new Set(Object.keys(m.packages[p] ?? {}));
    const b = new Set(Object.keys(t.packages[p] ?? {}));
    for (const f of [...a].filter((x) => !b.has(x)))
      if (!driftAllow.has(`${p}.${f}`)) fail(`field drift not excepted: ${p}.${f} (mainnet only)`);
    for (const f of [...b].filter((x) => !a.has(x)))
      if (!driftAllow.has(`${p}.${f}`)) fail(`field drift not excepted: ${p}.${f} (testnet only)`);
  }
}

console.log(failures ? `consistency: ${failures} failure(s)` : "consistency: all green");
process.exit(failures ? 1 : 0);

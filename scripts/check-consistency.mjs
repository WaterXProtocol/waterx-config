// Keyspace + cross-network consistency gate (audit P2/P4).
//
// The symbol-keyed map inventory comes from schema/map-paths.json — the ONE
// registry (also consumed by the schema generators). Each network file is
// checked against the map paths of the shape it declares, so this gate
// survives the flip unchanged. Exceptions are keyed by the map's stable `id`,
// and a stale exception (symbol no longer in its map) FAILS — the list can
// only shrink.
import { readFileSync } from "node:fs";

const root = new URL("..", import.meta.url);
const read = (p) => JSON.parse(readFileSync(new URL(p, root), "utf8"));
const registry = read("schema/map-paths.json").maps;
const exceptions = read("schema/coverage-exceptions.json");
const docs = Object.fromEntries(["mainnet", "testnet"].map((n) => [n, read(`${n}.json`)]));

let failures = 0;
const fail = (msg) => { console.error(`FAIL ${msg}`); failures++; };
const ok = (msg) => console.log(`  ok ${msg}`);
const dig = (doc, path) => path.split("/").reduce((o, k) => o?.[k], doc);

for (const [net, doc] of Object.entries(docs)) {
  const shape = (doc.schema_version ?? 1) >= 2 ? "target" : "legacy";
  const universe = new Set(Object.keys(
    shape === "target" ? (doc.symbols ?? {}) : (doc.packages?.waterx_rule?.feeds ?? {}),
  ));
  for (const entry of registry) {
    if (entry.base !== "symbols") continue;
    const map = dig(doc, entry[shape]);
    if (!map) continue;
    const keys = new Set(Object.keys(map));
    const allowed = new Set(exceptions[net]?.[entry.id] ?? []);
    const extra = [...keys.difference(universe)].filter((s) => !allowed.has(s));
    if (extra.length) fail(`${net} (${shape}): ${entry[shape]} has symbols outside the universe and not excepted: ${extra.join(", ")}`);
    else ok(`${net} (${shape}): ${entry[shape]} ⊆ universe (+${allowed.size} excepted)`);
    const stale = [...allowed.difference(keys)];
    if (stale.length) fail(`${net}: stale exception(s) for ${entry.id} — no longer present in the map, remove them: ${stale.join(", ")}`);
  }
}

// Cross-network field drift applies to the legacy shape's free-form packages
// only; the target shape's packages are uniform by schema.
if (Object.values(docs).every((d) => (d.schema_version ?? 1) < 2)) {
  const driftAllow = new Set(exceptions.field_drift ?? []);
  const { mainnet: m, testnet: t } = docs;
  for (const p of Object.keys(m.packages).filter((p) => p in t.packages)) {
    const a = new Set(Object.keys(m.packages[p] ?? {}));
    const b = new Set(Object.keys(t.packages[p] ?? {}));
    for (const f of a.difference(b))
      if (!driftAllow.has(`${p}.${f}`)) fail(`field drift not excepted: ${p}.${f} (mainnet only)`);
    for (const f of b.difference(a))
      if (!driftAllow.has(`${p}.${f}`)) fail(`field drift not excepted: ${p}.${f} (testnet only)`);
  }
}

console.log(failures ? `consistency: ${failures} failure(s)` : "consistency: all green");
process.exit(failures ? 1 : 0);

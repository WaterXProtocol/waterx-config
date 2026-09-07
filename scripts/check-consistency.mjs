// Keyspace consistency gate (audit P2): every symbol-keyed map ⊆ the symbols
// universe, with per-map declared exceptions. The map inventory comes from
// schema/map-paths.json — the ONE registry (also consumed by the schema
// generator). Exceptions are keyed by the map's stable `id`; a stale
// exception (symbol no longer present, id unknown to the registry, or a map
// that vanished while excepted) FAILS — the list can only shrink.
import { readFileSync } from "node:fs";

const root = new URL("..", import.meta.url);
const read = (p) => JSON.parse(readFileSync(new URL(p, root), "utf8"));
const registry = read("schema/map-paths.json").maps;
const exceptions = read("schema/coverage-exceptions.json");

let failures = 0;
const fail = (msg) => { console.error(`FAIL ${msg}`); failures++; };
const ok = (msg) => console.log(`  ok ${msg}`);
const dig = (doc, path) => path.split("/").reduce((o, k) => o?.[k], doc);
const knownIds = new Set(registry.map((m) => m.id));

for (const net of ["mainnet", "testnet"]) {
  const doc = read(`${net}.json`);
  const universe = new Set(Object.keys(doc.symbols ?? {}));
  const declared = exceptions[net] ?? {};
  for (const id of Object.keys(declared)) {
    if (!knownIds.has(id)) fail(`${net}: exception for unknown map id '${id}' — not in schema/map-paths.json`);
  }
  for (const entry of registry) {
    if (entry.base !== "symbols") continue;
    const map = dig(doc, entry.path);
    const allowed = new Set(declared[entry.id] ?? []);
    if (!map) {
      if (allowed.size) fail(`${net}: ${entry.path} is absent but still carries ${allowed.size} exception(s) — remove them`);
      continue;
    }
    const keys = new Set(Object.keys(map));
    const extra = [...keys.difference(universe)].filter((s) => !allowed.has(s));
    if (extra.length) fail(`${net}: ${entry.path} has symbols outside the universe and not excepted: ${extra.join(", ")}`);
    else ok(`${net}: ${entry.path} ⊆ symbols (+${allowed.size} excepted)`);
    const stale = [...allowed.difference(keys)];
    if (stale.length) fail(`${net}: stale exception(s) for ${entry.id} — no longer present in the map, remove them: ${stale.join(", ")}`);
  }
}

console.log(failures ? `consistency: ${failures} failure(s)` : "consistency: all green");
process.exit(failures ? 1 : 0);

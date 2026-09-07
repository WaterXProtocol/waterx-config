// Keyspace consistency gate (audit P2): every symbol-keyed map ⊆ the symbols
// universe, with per-map declared exceptions. The map inventory comes from
// schema/map-paths.json — the ONE registry (also consumed by the schema
// generator), including '*' segments (each expands over one map's keys, the
// same semantics the generator uses). Nothing is skipped silently: an absent
// map prints an explicit line, so "checked" and "not present" are always
// distinguishable in the log (review finding: two maps were unchecked with
// zero notice). Exceptions are keyed by the map's stable `id`; a stale
// exception (symbol no longer in the map, symbol now IN the universe, id
// unknown, id for an open keyspace, or a map that vanished while excepted)
// FAILS — the list can only shrink.
import { readFileSync } from "node:fs";

const root = new URL("..", import.meta.url);
const read = (p) => JSON.parse(readFileSync(new URL(p, root), "utf8"));
const registry = read("schema/map-paths.json").maps;
const exceptions = read("schema/coverage-exceptions.json");

let failures = 0;
const fail = (msg) => { console.error(`FAIL ${msg}`); failures++; };
const ok = (msg) => console.log(`  ok ${msg}`);

// Expand a registry path against a document. '*' fans out over the keys of
// the map at that position; the result is every concrete (path, value) the
// pattern denotes. A path that resolves to nothing returns [] — the caller
// reports that explicitly rather than skipping in silence.
const expand = (node, segs, at) => {
  if (node === undefined || node === null) return [];
  if (segs.length === 0) return [{ path: at, node }];
  const [seg, ...rest] = segs;
  if (seg === "*") {
    if (typeof node !== "object" || Array.isArray(node)) return [];
    return Object.entries(node).flatMap(([k, v]) => expand(v, rest, `${at}/${k}`));
  }
  return expand(node[seg], rest, at ? `${at}/${seg}` : seg);
};

const symbolIds = new Set(registry.filter((m) => m.base === "symbols").map((m) => m.id));
const knownIds = new Set(registry.map((m) => m.id));

for (const net of ["mainnet", "testnet"]) {
  const doc = read(`${net}.json`);
  const universe = new Set(Object.keys(doc.symbols ?? {}));
  const declared = exceptions[net] ?? {};
  for (const id of Object.keys(declared)) {
    if (!knownIds.has(id)) fail(`${net}: exception for unknown map id '${id}' — not in schema/map-paths.json`);
    else if (!symbolIds.has(id)) fail(`${net}: exception for '${id}', an open-keyspace map — meaningless, remove it`);
  }
  for (const entry of registry) {
    if (entry.base !== "symbols") continue;
    const found = expand(doc, entry.path.split("/"), "");
    const allowed = new Set(declared[entry.id] ?? []);
    if (found.length === 0) {
      if (allowed.size) fail(`${net}: ${entry.path} is absent but still carries ${allowed.size} exception(s) — remove them`);
      else console.log(`  -- ${net}: ${entry.path} absent on this network (nothing to check)`);
      continue;
    }
    const seen = new Set();
    for (const { path, node } of found) {
      if (typeof node !== "object" || node === null || Array.isArray(node)) {
        fail(`${net}: ${path} is declared a symbol-keyed map but is not an object`);
        continue;
      }
      const keys = new Set(Object.keys(node));
      for (const k of keys) seen.add(k);
      const extra = [...keys.difference(universe)].filter((s) => !allowed.has(s));
      if (extra.length) fail(`${net}: ${path} has symbols outside the universe and not excepted: ${extra.join(", ")}`);
      else ok(`${net}: ${path} ⊆ symbols (+${allowed.size} excepted)`);
    }
    const gone = [...allowed.difference(seen)];
    if (gone.length) fail(`${net}: stale exception(s) for ${entry.id} — no longer present in the map, remove them: ${gone.join(", ")}`);
    const joined = [...allowed].filter((s) => universe.has(s));
    if (joined.length) fail(`${net}: stale exception(s) for ${entry.id} — now IN the symbols universe, no longer drift, remove them: ${joined.join(", ")}`);
  }
}

console.log(failures ? `consistency: ${failures} failure(s)` : "consistency: all green");
process.exit(failures ? 1 : 0);

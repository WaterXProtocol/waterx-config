// Keyspace consistency gate (audit P2): every symbol-keyed map ⊆ the symbols
// universe, with per-map declared exceptions. The map inventory comes from
// schema/map-paths.json — the ONE registry (also consumed by the schema
// generator), including '*' segments (each expands over one map's keys, the
// same semantics the generator uses).
//
// FAIL-CLOSED (review findings): the registry itself is validated (unique
// ids, legal base/networks/path); a map declared for a network that is
// missing or untraversable there FAILS (a path typo or a data regression
// must never read as "nothing to check"); a map PRESENT on an undeclared
// network fails too. Exceptions are keyed by the map's stable `id`; a stale
// exception (symbol no longer in the map, symbol now IN the universe, id
// unknown, or id for an open keyspace) FAILS — the list can only shrink.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = new URL("..", import.meta.url);
const read = (p) => JSON.parse(readFileSync(new URL(p, root), "utf8"));

// Expand a registry path against a document. '*' fans out over the keys of
// the map at that position; the result is every concrete (path, value) the
// pattern denotes. Anything unresolvable contributes nothing — the CALLER
// decides whether emptiness is declared absence or a failure.
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

const SEG = /^(\*|[A-Za-z0-9_.-]+)$/;
const NETWORKS = ["mainnet", "testnet"];

// The base classification is a CONTRACT, pinned here independently of the
// mutable registry (review finding: flipping a symbol map's base to 'open'
// in map-paths.json alone would silently disable its ⊆-symbols check).
// Reclassifying a map, adding a symbol-keyed one, or removing one must edit
// this reviewed list in the same PR — and deleting a registry row for a
// pinned map fails outright.
const SYMBOL_KEYED_MAPS = new Set([
  "pyth_price_feeds", "lazer_feed_ids", "supra_pair_ids",
  "constant_prices", "aggregators", "perp_markets",
]);

/** Run every check. Pure: takes the registry, exceptions, and {net: doc};
 *  returns { failures: string[], log: string[] }. The CLI below feeds it the
 *  real files; scripts/test_check_consistency.mjs feeds it mutations. */
export function runChecks(registry, exceptions, docs) {
  const failures = [];
  const log = [];
  const fail = (msg) => failures.push(msg);
  const ok = (msg) => log.push(`  ok ${msg}`);

  // The registry is itself an input that can rot — validate it first.
  const ids = new Set();
  for (const e of registry) {
    if (!e.id || ids.has(e.id)) fail(`registry: missing or duplicate id '${e.id ?? "?"}'`);
    ids.add(e.id);
    if (!["symbols", "open"].includes(e.base)) fail(`registry ${e.id}: base must be 'symbols' or 'open', got '${e.base}'`);
    else {
      const expected = SYMBOL_KEYED_MAPS.has(e.id) ? "symbols" : "open";
      if (e.base !== expected)
        fail(`registry ${e.id}: base '${e.base}' contradicts the pinned contract ('${expected}') — reclassifying a map must update SYMBOL_KEYED_MAPS in check-consistency.mjs in the same PR`);
    }
    if (!Array.isArray(e.networks) || e.networks.length === 0 || !e.networks.every((n) => NETWORKS.includes(n)))
      fail(`registry ${e.id}: networks must be a non-empty subset of ${NETWORKS.join("/")}`);
    if (!e.path || !e.path.split("/").every((s) => SEG.test(s)))
      fail(`registry ${e.id}: malformed path '${e.path}'`);
  }
  for (const id of SYMBOL_KEYED_MAPS) {
    if (!ids.has(id)) fail(`registry: pinned symbol-keyed map '${id}' is missing from map-paths.json — deleting its row would silently drop its keyspace check`);
  }
  const symbolIds = new Set(registry.filter((m) => m.base === "symbols").map((m) => m.id));

  for (const net of NETWORKS) {
    const doc = docs[net];
    const universe = new Set(Object.keys(doc.symbols ?? {}));
    const declared = exceptions[net] ?? {};
    for (const id of Object.keys(declared)) {
      if (!ids.has(id)) fail(`${net}: exception for unknown map id '${id}' — not in schema/map-paths.json`);
      else if (!symbolIds.has(id)) fail(`${net}: exception for '${id}', an open-keyspace map — meaningless, remove it`);
    }
    for (const entry of registry) {
      const found = expand(doc, entry.path.split("/"), "");
      const applies = (entry.networks ?? NETWORKS).includes(net);
      if (!applies) {
        if (found.length) fail(`${net}: ${entry.path} exists but map-paths.json does not declare it for ${net} — declare it or remove the data`);
        else ok(`${net}: ${entry.path} absent, as declared`);
        continue;
      }
      if (found.length === 0) {
        fail(`${net}: ${entry.path} is declared for ${net} but missing or untraversable — a path typo in map-paths.json, or the data lost the map`);
        continue;
      }
      if (entry.base !== "symbols") {
        ok(`${net}: ${entry.path} present (open keyspace)`);
        continue;
      }
      const allowed = new Set(declared[entry.id] ?? []);
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
  return { failures, log };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const registry = read("schema/map-paths.json").maps;
  const exceptions = read("schema/coverage-exceptions.json");
  const docs = Object.fromEntries(NETWORKS.map((n) => [n, read(`${n}.json`)]));
  const { failures, log } = runChecks(registry, exceptions, docs);
  for (const l of log) console.log(l);
  for (const f of failures) console.error(`FAIL ${f}`);
  console.log(failures.length ? `consistency: ${failures.length} failure(s)` : "consistency: all green");
  process.exit(failures.length ? 1 : 0);
}

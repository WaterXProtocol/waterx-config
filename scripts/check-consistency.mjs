// Cross-map + cross-network consistency gate (audit P2/P4).
// Every symbol-keyed map is diffed against waterx_rule.feeds; every diff must
// be declared in schema/coverage-exceptions.json or the check fails. Same for
// fields present on only one network.
import { readFileSync } from "node:fs";
const root = new URL("..", import.meta.url);
const read = (p) => JSON.parse(readFileSync(new URL(p, root), "utf8"));
const m = read("mainnet.json"), t = read("testnet.json");
const exceptions = read("schema/coverage-exceptions.json");
let failures = 0;
const fail = (msg) => { console.error(`FAIL ${msg}`); failures++; };
const ok = (msg) => console.log(`  ok ${msg}`);

for (const [net, doc] of [["mainnet", m], ["testnet", t]]) {
  const P = doc.packages;
  const base = new Set(Object.keys(P.waterx_rule?.feeds ?? {}));
  const maps = {
    "pyth_rule.feeds": P.pyth_rule?.feeds,
    "pyth_lazer_rule.feeds": P.pyth_lazer_rule?.feeds,
    "supra_rule.feeds": P.supra_rule?.feeds,
    "constant_rule.feeds": P.constant_rule?.feeds,
    "waterx_oracle.aggregators": P.waterx_oracle?.aggregators,
    "waterx_perp.markets": P.waterx_perp?.markets,
  };
  for (const [name, map] of Object.entries(maps)) {
    if (!map) continue;
    const allowed = new Set(exceptions[net]?.[name] ?? []);
    const extra = Object.keys(map).filter((s) => !base.has(s) && !allowed.has(s));
    if (extra.length) fail(`${net}: ${name} has symbols outside waterx_rule.feeds and not excepted: ${extra.join(", ")}`);
    else ok(`${net}: ${name} keyspace ⊆ waterx_rule.feeds (+${allowed.size} excepted)`);
  }
}

// cross-network field drift: every field on one side only must be excepted
const driftAllow = new Set(exceptions.field_drift ?? []);
for (const p of Object.keys(m.packages).filter((p) => p in t.packages)) {
  const a = new Set(Object.keys(m.packages[p] ?? {}));
  const b = new Set(Object.keys(t.packages[p] ?? {}));
  for (const f of [...a].filter((x) => !b.has(x)))
    if (!driftAllow.has(`${p}.${f}`)) fail(`field drift not excepted: ${p}.${f} (mainnet only)`);
  for (const f of [...b].filter((x) => !a.has(x)))
    if (!driftAllow.has(`${p}.${f}`)) fail(`field drift not excepted: ${p}.${f} (testnet only)`);
}
if (!failures) console.log("consistency: all green");
process.exit(failures ? 1 : 0);

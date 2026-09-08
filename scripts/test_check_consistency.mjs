// Mutation tests for check-consistency's fail-closed guarantees (review
// finding: a path typo, a missing wildcard parent, or a base flip must be a
// FAILURE, never a silent skip). Dependency-free; run from the repo root:
//     node scripts/test_check_consistency.mjs
import { readFileSync } from "node:fs";
import { runChecks } from "./check-consistency.mjs";

const root = new URL("..", import.meta.url);
const read = (p) => JSON.parse(readFileSync(new URL(p, root), "utf8"));
const registry = () => structuredClone(read("schema/map-paths.json").maps);
const exceptions = () => structuredClone(read("schema/coverage-exceptions.json"));
const docs = () => Object.fromEntries(["mainnet", "testnet"].map((n) => [n, structuredClone(read(`${n}.json`))]));

let failures = 0;
const expectFail = (label, needle, reg, exc, dd) => {
  const r = runChecks(reg, exc, dd);
  if (!r.failures.some((f) => f.includes(needle))) {
    console.error(`TEST FAIL ${label}: expected a failure containing '${needle}', got: ${JSON.stringify(r.failures)}`);
    failures++;
  } else console.log(`  ok ${label}`);
};

// 0. The live inputs pass (sanity).
{
  const r = runChecks(registry(), exceptions(), docs());
  if (r.failures.length) { console.error(`TEST FAIL live inputs: ${JSON.stringify(r.failures)}`); failures++; }
  else console.log("  ok live inputs pass");
}

// 1. A path typo in a symbol-keyed map must FAIL, not skip.
{
  const reg = registry();
  reg.find((e) => e.id === "pyth_price_feeds").path = "oracle_rules/pyth/price_feeds";
  expectFail("path typo fails", "missing or untraversable", reg, exceptions(), docs());
}

// 2. A missing wildcard parent must FAIL for a declared network.
{
  const dd = docs();
  delete dd.mainnet.objects.staking.rewarders;
  expectFail("missing wildcard parent fails", "missing or untraversable", registry(), exceptions(), dd);
}

// 3. Flipping ANY symbol map's base to 'open' must FAIL against the pinned
//    contract — including one with NO live coverage exception (review
//    finding: the exception path only caught this incidentally).
{
  const reg = registry();
  reg.find((e) => e.id === "venue_feeds").base = "open";
  expectFail("base flip (no exceptions) fails", "pinned contract", reg, exceptions(), docs());
}
{
  const reg = registry();
  reg.find((e) => e.id === "constant_prices").base = "open";
  expectFail("base flip (live exceptions) fails", "pinned contract", reg, exceptions(), docs());
}

// 3b. Deleting a pinned symbol map's registry row must FAIL — a keyspace
//     check cannot vanish by removing its declaration.
{
  const reg = registry().filter((e) => e.id !== "perp_markets");
  expectFail("deleted symbol-map row fails", "missing from map-paths.json", reg, exceptions(), docs());
}

// 3c. A NEW symbol-keyed map not in the pinned contract must FAIL — adding
//     one is a deliberate, two-file change.
{
  const reg = registry();
  reg.push({ id: "surprise_feeds", path: "oracle_rules/waterx/venue_feeds", base: "symbols", networks: ["mainnet", "testnet"] });
  expectFail("unpinned new symbol map fails", "pinned contract", reg, exceptions(), docs());
}

// 4. Data losing a declared map must FAIL (regression, not absence).
{
  const dd = docs();
  delete dd.testnet.oracle_rules.supra;
  expectFail("declared map lost from data fails", "missing or untraversable", registry(), exceptions(), dd);
}

// 5. A map appearing on an undeclared network must FAIL.
{
  const dd = docs();
  dd.testnet.oracle_rules.pyth_lazer = { lazer_feed_ids: { BTCUSD: 1 } };
  expectFail("undeclared presence fails", "does not declare it for testnet", registry(), exceptions(), dd);
}

// 6. Registry rot fails: bad base, bad networks, duplicate id, malformed path.
{
  const reg = registry();
  reg[0] = { ...reg[0], base: "symbolz" };
  expectFail("bad base fails", "base must be", reg, exceptions(), docs());
}
{
  const reg = registry();
  reg[0] = { ...reg[0], networks: ["mainnet", "devnet"] };
  expectFail("bad networks fails", "non-empty subset", reg, exceptions(), docs());
}

if (failures) { console.error(`test_check_consistency: ${failures} test(s) failed`); process.exit(1); }
console.log("test_check_consistency: all guarantees hold");

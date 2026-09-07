/** The schema↔data↔parser↔lift quadrangle: the LIVE legacy files must parse
 * into the target shape, and a natively-target document must parse identically. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseWaterxConfig, WaterxConfigError } from "../src/index.ts";

const FIXTURES = new Map<string, unknown>();
const load = (rel: string): any => {
  if (!FIXTURES.has(rel)) {
    FIXTURES.set(rel, JSON.parse(readFileSync(new URL(`../../../${rel}`, import.meta.url), "utf8")));
  }
  return structuredClone(FIXTURES.get(rel));
};

for (const net of ["mainnet", "testnet"] as const) {
  test(`${net}.json (legacy shape) lifts + parses into the target shape`, () => {
    const cfg = parseWaterxConfig(load(`${net}.json`), net);
    assert.equal(cfg.schema_version, 2);
    assert.ok(Object.keys(cfg.symbols).length >= 31);
    const btc = cfg.oracle_rules.waterx?.venue_feeds["BTCUSD"];
    assert.ok(btc);
    assert.ok(btc.sources.every((s) => typeof s.name === "string" && Number.isInteger(s.weight)));
    // identity fields survive at the SAME path — the flip-immunity guarantee
    assert.match(cfg.packages.waterx_rule.published_at ?? "", /^0x[0-9a-fA-F]{64}$/);
  });

  test(`${net}: a natively-target document round-trips (flip-day behavior)`, () => {
    const lifted = parseWaterxConfig(load(`${net}.json`));
    const again = parseWaterxConfig(structuredClone(lifted), net); // now schema_version=2 → native path
    assert.deepEqual(again, lifted);
  });
}

test("a corrupted object id is rejected (patterns bite despite tolerance)", () => {
  const doc = load("mainnet.json");
  doc.packages.waterx_oracle.oracle = "0xnot-an-id";
  assert.throws(() => parseWaterxConfig(doc), WaterxConfigError);
});

test("an unknown field is TOLERATED (forward-compat with newer configs)", () => {
  const doc = load("mainnet.json");
  doc.packages.waterx_rule.surprise = 1;
  const cfg = parseWaterxConfig(doc);
  assert.ok(cfg.oracle_rules.waterx);
});

test("network mismatch is rejected", () => {
  assert.throws(() => parseWaterxConfig(load("mainnet.json"), "testnet"), WaterxConfigError);
});

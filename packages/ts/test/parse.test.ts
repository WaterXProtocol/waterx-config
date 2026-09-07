/** The two live instances MUST parse — this is the schema↔data↔parser triangle. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseWaterxConfig, WaterxConfigError } from "../src/index.ts";

for (const net of ["mainnet", "testnet"] as const) {
  test(`${net}.json parses strictly`, () => {
    const doc = JSON.parse(readFileSync(new URL(`../../../${net}.json`, import.meta.url), "utf8"));
    const cfg = parseWaterxConfig(doc, net);
    assert.equal(cfg.network, net);
    assert.ok(Object.keys(cfg.packages).length >= 15);
  });
}

test("waterx_rule feed shape is fully typed", () => {
  const doc = JSON.parse(readFileSync(new URL("../../../mainnet.json", import.meta.url), "utf8"));
  const cfg = parseWaterxConfig(doc);
  const btc = cfg.packages.waterx_rule?.feeds["BTCUSD"];
  assert.ok(btc);
  assert.equal(typeof btc.ticker, "string");
  assert.ok(btc.sources.every((s) => typeof s.name === "string" && Number.isInteger(s.weight)));
});

test("a corrupted object id is rejected", () => {
  const doc = JSON.parse(readFileSync(new URL("../../../mainnet.json", import.meta.url), "utf8"));
  doc.packages.waterx_oracle.oracle = "0xnot-an-id";
  assert.throws(() => parseWaterxConfig(doc), WaterxConfigError);
});

test("an unknown field is TOLERATED by default (forward-compat with newer configs)", () => {
  const doc = JSON.parse(readFileSync(new URL("../../../mainnet.json", import.meta.url), "utf8"));
  doc.packages.waterx_rule.surprise = 1;
  const cfg = parseWaterxConfig(doc);
  assert.ok(cfg.packages.waterx_rule);
});

test("strict mode rejects unknown fields (CI/pinned-document use)", () => {
  const doc = JSON.parse(readFileSync(new URL("../../../mainnet.json", import.meta.url), "utf8"));
  doc.packages.waterx_rule.surprise = 1;
  assert.throws(() => parseWaterxConfig(doc, undefined, { strict: true }), WaterxConfigError);
});

test("a corrupted object id is rejected even in tolerant mode", () => {
  const doc = JSON.parse(readFileSync(new URL("../../../mainnet.json", import.meta.url), "utf8"));
  doc.packages.waterx_oracle.oracle = "0xnot-an-id";
  assert.throws(() => parseWaterxConfig(doc), WaterxConfigError);
});

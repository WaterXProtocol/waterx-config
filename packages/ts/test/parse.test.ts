/** The schema↔data↔parser triangle on the served (consolidated) shape, plus
 * loader behavior with an injected fetch. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";
import { loadWaterxConfig, parseWaterxConfig, WaterxConfigError } from "../src/index.ts";

const FIXTURES = new Map<string, unknown>();
const load = (rel: string): any => {
  if (!FIXTURES.has(rel)) {
    FIXTURES.set(rel, JSON.parse(readFileSync(new URL(`../../../${rel}`, import.meta.url), "utf8")));
  }
  return structuredClone(FIXTURES.get(rel));
};
const validateCanonical = new Ajv2020().compile(load("schema/waterx-config.schema.json"));

for (const net of ["mainnet", "testnet"] as const) {
  test(`${net}.json parses`, () => {
    const cfg = parseWaterxConfig(load(`${net}.json`), net);
    assert.equal(cfg.schema_version, 2);
    assert.ok(Object.keys(cfg.symbols).length > 0);
    assert.ok(cfg.symbols["BTCUSD"], "the flagship symbol must exist in the universe");
    assert.ok(cfg.objects.oracle.aggregators["BTCUSD"], "the flagship symbol must have an on-chain aggregator");
    assert.ok(cfg.packages.waterx_rule, "waterx_rule identity block");
    assert.match(cfg.packages.waterx_rule.published_at, /^0x[0-9a-fA-F]{64}$/);
  });
}

test("Voucher type origins survive parsing on both deployed networks", () => {
  const origins = ["0x842257f800decb84668282b372c4eecbee2a39da23a61e9e02a9af74f441f0fe"];
  const mainnetOrigins = ["0x9c455caf234cbb8ddba6ed87762e5e3fcc6f0ff84711a08331ab8ebccb5e0344"];
  const testnet = parseWaterxConfig(load("testnet.json"), "testnet");
  assert.equal(validateCanonical(load("testnet.json")), true);
  assert.deepEqual(testnet.objects.prediction.voucher_type_origins, origins);
  assert.deepEqual(parseWaterxConfig(JSON.parse(JSON.stringify(testnet))).objects.prediction.voucher_type_origins, origins);
  assert.deepEqual(parseWaterxConfig(load("mainnet.json"), "mainnet").objects.prediction.voucher_type_origins, mainnetOrigins);
  assert.equal(validateCanonical(load("mainnet.json")), true);
});

test("Voucher origins are required now that both networks are deployed", () => {
  const doc = load("testnet.json");
  delete doc.objects.prediction.voucher_type_origins;
  assert.equal(validateCanonical(doc), false);
  assert.throws(() => parseWaterxConfig(doc), WaterxConfigError);
});

test("duplicate Voucher origins agree between canonical schema and generated parser", () => {
  const doc = load("testnet.json");
  const origin = doc.objects.prediction.voucher_type_origins[0];
  doc.objects.prediction.voucher_type_origins = [origin, origin];
  assert.equal(validateCanonical(doc), true);
  assert.deepEqual(parseWaterxConfig(doc).objects.prediction.voucher_type_origins, [origin, origin]);
});

for (const [label, value] of [
  ["empty array", []],
  ["null", null],
  ["single string", "0x" + "a".repeat(64)],
  ["object", { package: "0x" + "a".repeat(64) }],
  ["short address", ["0xdead"]],
  ["non-hex address", ["0x" + "g".repeat(64)]],
  ["non-string item", [1]],
] as const) {
  test(`Voucher origins reject ${label}`, () => {
    const doc = load("testnet.json");
    doc.objects.prediction.voucher_type_origins = value;
    assert.equal(validateCanonical(doc), false, "canonical schema must reject the same malformed origins");
    assert.throws(() => parseWaterxConfig(doc), WaterxConfigError);
  });
}

test("a corrupted object id is rejected (patterns bite despite tolerance)", () => {
  const doc = load("mainnet.json");
  doc.objects.oracle.aggregators.BTCUSD = "0xnope";
  assert.throws(() => parseWaterxConfig(doc), WaterxConfigError);
});

test("unknown fields are TOLERATED, and NEW packages/symbols survive (uniform maps)", () => {
  const doc = load("mainnet.json");
  doc.oracle_rules.waterx.surprise = 1;
  doc.packages.brand_new_pkg = { published_at: "0x" + "a".repeat(64), original_id: "0x" + "b".repeat(64), version: 1 };
  const cfg = parseWaterxConfig(doc);
  assert.ok(cfg.packages.brand_new_pkg, "a newly deployed package must be visible to pinned consumers");
});

test("wrong schema_version is rejected", () => {
  const doc = load("mainnet.json");
  doc.schema_version = 3;
  assert.throws(() => parseWaterxConfig(doc), WaterxConfigError);
});

test("network mismatch is rejected", () => {
  assert.throws(() => parseWaterxConfig(load("mainnet.json"), "testnet"), WaterxConfigError);
});

test("loader: HTTP 429 is retried with backoff (the status this CDN rule exists for)", async () => {
  let calls = 0;
  const body = JSON.stringify(load("mainnet.json"));
  const fetchImpl = (async () => {
    calls++;
    return calls < 3 ? new Response("slow down", { status: 429 }) : new Response(body, { status: 200 });
  }) as typeof fetch;
  const cfg = await loadWaterxConfig("mainnet", { fetchImpl, attempts: 3, backoffBaseMs: 0 });
  assert.equal(calls, 3);
  assert.equal(cfg.network, "mainnet");
});

test("loader: 404 is NOT retried, even from a path containing 'abort'", async () => {
  let calls = 0;
  const fetchImpl = (async () => {
    calls++;
    return new Response("nope", { status: 404 });
  }) as typeof fetch;
  await assert.rejects(loadWaterxConfig("mainnet", { fetchImpl, baseUrl: "https://cdn.example.com/abort" }));
  assert.equal(calls, 1);
});

test("loader: raw.githubusercontent is refused case-insensitively", async () => {
  await assert.rejects(
    loadWaterxConfig("mainnet", { baseUrl: "https://RAW.GITHUBUSERCONTENT.COM/x" }),
    /not a config source/,
  );
});

test("loader: attempts is floored at 1", async () => {
  let calls = 0;
  const body = JSON.stringify(load("mainnet.json"));
  const fetchImpl = (async () => {
    calls++;
    return new Response(body, { status: 200 });
  }) as typeof fetch;
  await loadWaterxConfig("mainnet", { fetchImpl, attempts: 0 });
  assert.equal(calls, 1);
});

test("loader: a 200 with a non-JSON body is permanent — no retries (SyntaxError class)", async () => {
  let calls = 0;
  const fetchImpl = (async () => {
    calls++;
    return new Response("<html>edge error page</html>", { status: 200 });
  }) as typeof fetch;
  await assert.rejects(loadWaterxConfig("mainnet", { fetchImpl, backoffBaseMs: 0 }), SyntaxError);
  assert.equal(calls, 1, "a malformed body must not be re-fetched");
});

test("loader: non-finite attempts falls back to the default instead of zero fetches", async () => {
  let calls = 0;
  const body = JSON.stringify(load("mainnet.json"));
  const fetchImpl = (async () => {
    calls++;
    return new Response(body, { status: 200 });
  }) as typeof fetch;
  await loadWaterxConfig("mainnet", { fetchImpl, attempts: Number("not a number") });
  assert.equal(calls, 1, "NaN attempts must still fetch");
});

test("loader: exhausted retries surface the last HTTP status", async () => {
  const fetchImpl = (async () => new Response("busy", { status: 429 })) as typeof fetch;
  try {
    await loadWaterxConfig("mainnet", { fetchImpl, attempts: 2, backoffBaseMs: 0 });
    assert.fail("should have thrown");
  } catch (e) {
    assert.ok(e instanceof WaterxConfigError);
    assert.equal(e.status, 429, "circuit-breakers need the status without string-matching cause");
  }
});

test("parse strips unknown FIELDS on known objects (documented; do not round-trip a parse result)", () => {
  const doc = load("mainnet.json");
  doc.oracle_rules.waterx.surprise = 1;
  const cfg: any = parseWaterxConfig(doc);
  assert.ok(!("surprise" in cfg.oracle_rules.waterx), "typed view drops unknown fields — patch the ORIGINAL doc for read-modify-write");
});

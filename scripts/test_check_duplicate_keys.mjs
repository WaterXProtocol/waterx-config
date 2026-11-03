// Regression cases for raw JSON duplicate detection; Node's JSON.parse is last-wins.
import assert from "node:assert/strict";
import {
  mkdtempSync,
  readFileSync,
  rmdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { assertNoDuplicateKeys } from "./check-duplicate-keys.mjs";

for (const [label, source] of [
  ["identical values", '{"ETHBTC":1,"ETHBTC":1}'],
  ["shadowed values", '{"ETHBTC":1,"ETHBTC":2}'],
  ["nested objects", '{"objects":{"perp":{"ETHBTC":{},"ETHBTC":{}}}}'],
  ["objects inside arrays", '{"items":[{"ETHBTC":1,"ETHBTC":2}]}'],
  ["Unicode escape aliases", '{"ETHBTC":1,"\\u0045THBTC":2}'],
  ["escaped quote aliases", '{"a\\"b":1,"a\\u0022b":2}'],
  ["prototype names", '{"__proto__":1,"__proto__":2}'],
]) {
  test("rejects duplicate " + label, () => {
    assert.throws(
      () => assertNoDuplicateKeys(source, "fixture.json"),
      /fixture.json:1: duplicate JSON key/,
    );
  });
}

for (const [label, source] of [
  ["sibling objects", '{"first":{"ETHBTC":1},"second":{"ETHBTC":2}}'],
  ["array siblings", '[{"ETHBTC":1},{"ETHBTC":2}]'],
  ["strings with JSON punctuation", '{"text":"{\\"ETHBTC\\":1}","ETHBTC":2}'],
  ["empty containers", '{"a":[],"b":{},"c":[null,true,false,12.4]}'],
  ["top-level scalar", '"ETHBTC"'],
]) {
  test("allows " + label, () => assertNoDuplicateKeys(source));
}

test("reports the second member's source line", () => {
  assert.throws(
    () =>
      assertNoDuplicateKeys('{\n"ETHBTC":1,\n"ETHBTC":2\n}', "testnet.json"),
    /testnet.json:3: duplicate JSON key "ETHBTC"/,
  );
});

test("does not accept malformed JSON", () => {
  assert.throws(() => assertNoDuplicateKeys('{"ETHBTC":}'), SyntaxError);
});

test("all four symbol-keyed config sections reject duplicate ratio keys", () => {
  const fixture = readFileSync(
    new URL("../testnet.json", import.meta.url),
    "utf8",
  );
  for (const section of ["symbols", "aggregators", "markets", "feeds"]) {
    const key = '"' + section + '": {';
    const mutated = fixture.replace(key, key + '"ETHBTC":null,"ETHBTC":null,');
    assert.notEqual(mutated, fixture);
    assert.throws(
      () => assertNoDuplicateKeys(mutated),
      /duplicate JSON key "ETHBTC"/,
    );
  }
});

test("the CLI validates both served network files", () => {
  const script = fileURLToPath(
    new URL("./check-duplicate-keys.mjs", import.meta.url),
  );
  const output = execFileSync(process.execPath, [script], { encoding: "utf8" });
  assert.match(output, /mainnet.json: no duplicate JSON keys/);
  assert.match(output, /testnet.json: no duplicate JSON keys/);
});

test("the CI command exits nonzero for duplicate input", () => {
  const directory = mkdtempSync(join(tmpdir(), "waterx-config-duplicates-"));
  const fixture = join(directory, "duplicate.json");
  try {
    writeFileSync(fixture, '{"ETHBTC":1,"ETHBTC":1}');
    const script = fileURLToPath(
      new URL("./check-duplicate-keys.mjs", import.meta.url),
    );
    const result = spawnSync(process.execPath, [script, fixture], {
      encoding: "utf8",
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /duplicate JSON key "ETHBTC"/);
  } finally {
    unlinkSync(fixture);
    rmdirSync(directory);
  }
});

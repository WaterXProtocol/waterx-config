// Mechanically derive the v2 document (docs/V2-PROPOSAL.md) from a v1 network
// file. This script IS the field map: every v1 field is either moved here or
// deliberately routed to deploys/<network>.json — an unrecognized field throws,
// so v1 additions cannot silently miss the v2 story.
//
// Usage: node scripts/derive-v2.mjs <network>
//   writes v2/<network>.json and deploys/<network>.json
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const net = process.argv[2];
if (!["mainnet", "testnet"].includes(net)) throw new Error("usage: derive-v2.mjs <mainnet|testnet>");
const root = new URL("..", import.meta.url);
const v1 = JSON.parse(readFileSync(new URL(`${net}.json`, root), "utf8"));
const P = v1.packages;

/** take(pkgName, field) — consume a field so leftovers can be detected. */
const taken = new Map();
function take(pkg, field) {
  const body = P[pkg];
  if (!body || !(field in body)) return undefined;
  if (!taken.has(pkg)) taken.set(pkg, new Set());
  taken.get(pkg).add(field);
  return body[field];
}
const IDENTITY = ["published_at", "original_id", "version", "upgrade_capability", "mvr"];
const FORENSICS = ["publish_digest", "publish_checkpoint", "register_digest", "register_checkpoint"];

// ── §2 packages: uniform identity ─────────────────────────────────────────
const packages = {};
for (const name of Object.keys(P)) {
  const entry = {};
  for (const f of IDENTITY) {
    const v = take(name, f);
    if (v !== undefined && v !== null) entry[f] = v;
  }
  for (const f of FORENSICS) take(name, f); // routed to deploys below
  packages[name] = entry;
}

// ── §1 symbols: introduced by waterx_rule.feeds ───────────────────────────
const venueFeeds = take("waterx_rule", "feeds") ?? {};
const symbols = Object.fromEntries(
  Object.entries(venueFeeds).map(([s, f]) => [s, { kind: f.kind ?? "perp" }]),
);
const v2VenueFeeds = Object.fromEntries(
  Object.entries(venueFeeds).map(([s, { kind, ...rest }]) => [s, rest]), // kind lives in symbols now
);

// ── §4 oracle rules ───────────────────────────────────────────────────────
const oracle_rules = {};
oracle_rules.waterx = {
  package: "waterx_rule",
  rule_config_object: take("waterx_rule", "config"),
  enclave: {
    object: take("waterx_rule", "enclave"),
    cap: take("waterx_rule", "enclave_cap"),
    config: take("waterx_rule", "enclave_config"),
    pubkey: take("waterx_rule", "enclave_pubkey") ?? take("enclave", "enclave_pubkey"),
  },
  venue_feeds: v2VenueFeeds,
};
take("enclave", "enclave_pubkey"); // duplicate home, dropped (P7)
take("enclave", "enclave_config");
take("enclave", "enclave_cap");
take("enclave", "enclave");
const wrEnabled = take("waterx_rule", "enabled");
if (wrEnabled !== undefined) oracle_rules.waterx.enabled = wrEnabled; // semantics TBD; carried, schema'd

if (P.pyth_rule) {
  oracle_rules.pyth = {
    package: "pyth_rule",
    pyth_config_object: take("pyth_rule", "config"),
    pyth_price_feeds: take("pyth_rule", "feeds") ?? {},
  };
}
if (P.pyth_lazer_rule) {
  oracle_rules.pyth_lazer = {
    package: "pyth_lazer_rule",
    ...(take("pyth_lazer_rule", "state") !== undefined && { lazer_state_object: P.pyth_lazer_rule.state }),
    ...(take("pyth_lazer_rule", "config") !== undefined && { lazer_config_object: P.pyth_lazer_rule.config }),
    lazer_feed_ids: take("pyth_lazer_rule", "feeds") ?? {},
  };
}
if (P.constant_rule) {
  oracle_rules.constant = {
    package: "constant_rule",
    ...(take("constant_rule", "config") !== undefined && { rule_config_object: P.constant_rule.config }),
    constant_prices: take("constant_rule", "feeds") ?? {},
  };
}
if (P.supra_rule) {
  oracle_rules.supra = {
    package: "supra_rule",
    ...(take("supra_rule", "config") !== undefined && { rule_config_object: P.supra_rule.config }),
    pair_ids: Object.fromEntries(
      Object.entries(take("supra_rule", "feeds") ?? {}).map(([s, f]) => [s, f.pair_id]),
    ),
  };
}

// ── §3 objects by domain ──────────────────────────────────────────────────
const objects = {};
const put = (domain, key, val) => {
  if (val === undefined) return;
  (objects[domain] ??= {})[key] = val;
};
put("oracle", "oracle", take("waterx_oracle", "oracle"));
put("oracle", "listing_cap", take("waterx_oracle", "listing_cap"));
put("oracle", "aggregators", take("waterx_oracle", "aggregators"));
put("perp", "global_config", take("waterx_perp", "global_config"));
put("perp", "admin_cap", take("waterx_perp", "admin_cap"));
put("perp", "market_registry_wlp", take("waterx_perp", "market_registry_wlp"));
put("perp", "markets", take("waterx_perp", "markets"));
put("wlp", "pool", take("wlp", "wlp_pool"));
put("wlp", "aum", take("wlp", "wlp_aum"));
put("wlp", "currency_type", take("wlp", "currency"));
put("wlp", "metadata_cap", take("wlp", "metadata_cap"));
put("wlp", "pool_tokens", take("wlp", "pool_tokens"));
put("staking", "admin_cap", take("waterx_staking", "admin_cap"));
put("staking", "pools", take("waterx_staking", "pools"));
put("staking", "rewarders", take("waterx_staking", "rewarders"));
put("account", "registry", take("waterx_account", "account_registry"));
put("account", "admin_cap", take("waterx_account", "admin_cap"));
put("referral", "table", take("waterx_referral", "referral_table"));
put("credit", "registry", take("waterx_credit", "credit_registry"));
put("credit", "credit_type", take("waterx_credit", "credit_type"));
{
  const assets = take("native_custody", "assets");
  put("custody", "vault", take("native_custody", "vault"));
  if (assets) put("custody", "assets", assets.map(({ _comment, ...a }) => a)); // P5: comments out of data
}
put("bridge", "state", take("wormhole_bridge", "bridge"));
put("bridge", "emitter_cap", take("wormhole_bridge", "emitter_cap"));
put("bridge", "wormhole_state", take("wormhole_bridge", "wormhole_state"));
{
  const limits = {};
  for (const [v1k, v2k] of [
    ["max_mint_per_tx", "max_mint_per_tx"], ["max_burn_per_tx", "max_burn_per_tx"],
    ["daily_mint_limit", "daily_mint"], ["daily_burn_limit", "daily_burn"],
    ["personal_burn_cap", "personal_burn"],
  ]) {
    const v = take("wormhole_bridge", v1k);
    if (v !== undefined) limits[v2k] = v;
  }
  if (Object.keys(limits).length) put("bridge", "limits", limits);
}
put("withdrawal_queue", "queue", take("withdrawal_queue", "queue"));
put("withdrawal_queue", "executors", take("withdrawal_queue", "executors"));
put("prediction", "global_config", take("waterx_prediction", "global_config"));
put("prediction", "admin_cap", take("waterx_prediction", "admin_cap"));
put("prediction", "market_registries", take("waterx_prediction", "market_registries"));
put("prediction", "settlement_coin_types", take("waterx_prediction", "settlement_coin_types"));
put("prediction", "claimable_link_config", take("waterx_prediction_gift", "claimable_link_config"));
put("prediction", "gift_admin_cap", take("waterx_prediction_gift", "admin_cap"));
put("usd", "metadata_cap", take("usd", "metadata_cap"));
// testnet-only utility packages
put("faucet", "faucet", take("testnet_faucet", "faucet"));
put("faucet", "whitelist", take("testnet_faucet", "whitelist"));
put("mock_usdsui", "currency_type", take("mock_usdsui", "currency"));
put("mock_usdsui", "metadata_cap", take("mock_usdsui", "metadata_cap"));
put("mock_usdsui", "treasury_cap", take("mock_usdsui", "treasury_cap"));

// ── leftover detection: every non-identity v1 field must have a v2 home ───
const leftovers = [];
for (const [name, body] of Object.entries(P)) {
  for (const f of Object.keys(body ?? {})) {
    if (!taken.get(name)?.has(f)) leftovers.push(`${name}.${f}`);
  }
}
if (leftovers.length) {
  throw new Error(`v1 fields with no v2 disposition (extend derive-v2.mjs): ${leftovers.join(", ")}`);
}

// ── outputs ───────────────────────────────────────────────────────────────
const v2 = {
  schema_version: 2,
  network: v1.network,
  chain_id: v1.chain_id,
  symbols,
  packages,
  objects,
  oracle_rules,
  ...(v1.coin_registry !== undefined && { coin_registry: v1.coin_registry }),
  ...(v1.evm !== undefined && { evm: v1.evm }),
};
const forensics = {
  network: v1.network,
  deploy_tx_log: v1.deploy_tx_log ?? [],
  package_publish: Object.fromEntries(
    Object.entries(P)
      .map(([name, body]) => [name, Object.fromEntries(FORENSICS.filter((f) => f in (body ?? {})).map((f) => [f, body[f]]))])
      .filter(([, v]) => Object.keys(v).length),
  ),
};
mkdirSync(new URL("v2", root), { recursive: true });
mkdirSync(new URL("deploys", root), { recursive: true });
writeFileSync(new URL(`v2/${net}.json`, root), JSON.stringify(v2, null, 2) + "\n");
writeFileSync(new URL(`deploys/${net}.json`, root), JSON.stringify(forensics, null, 2) + "\n");
console.log(`v2/${net}.json + deploys/${net}.json derived; 0 leftover fields`);

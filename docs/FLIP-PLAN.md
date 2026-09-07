# waterx-config flip plan — the consolidated target shape

Status: **decided** (2026-09-07 audit; zasper: single format, hard flip, no
v1/v2 parallel serving). The parser packages expose ONLY the target shape and
lift a legacy document internally (`packages/ts/src/lift.mjs`, mirrored by
`packages/rust/src/lift.rs` with a byte-equality test between them), so
consumers migrate once. Work accumulates on the `staging-v2`/`main-v2`
branches; **flip day** = `node scripts/derive-target.mjs flip` committed via
the `main-v2 → main` promotion PR, once the last direct-path consumer has
adopted a parser package (the audit report §8 table is the gate).

## Design rules

Five conventions, applied everywhere — the "consistent design" the current file
lacks:

1. **One tree per concern.** Package *identity* (ids/versions) is separate from
   *shared objects* (grouped by domain) is separate from the *oracle rule
   registry*. Today all three interleave inside `packages.*`, which is why 25
   packages carry 48 differently-shaped extra fields.
2. **One symbol universe.** A top-level `symbols` map is the only place a
   symbol is *introduced*; every other symbol-keyed map may only *reference*
   it (CI-enforced ⊆, with per-map declared exceptions).
3. **Names say what they hold.** No more four incompatible `feeds` and four
   unrelated `config`s: `venue_feeds`, `pyth_price_feeds`, `lazer_feed_ids`,
   `constant_prices`, `pyth_config_object`.
4. **Numbers have one rule.** Sui ids: `0x` + 64 hex. Amounts/prices that can
   exceed 2^53: decimal strings, annotated `u128-dec9` in the schema. Small
   enumerable ints (weights, versions, feed ids): JSON ints. Nothing else.
5. **Data is data.** No `_comment`; prose lives in schema `description`s and
   renders into FIELDS.md. Deploy forensics (`deploy_tx_log`,
   `publish_digest`/`checkpoint`) move to `deploys/<network>.json`, out of the
   hot-path document entirely.

## The shape

```jsonc
{
  "schema_version": 2,
  "network": "mainnet",
  "chain_id": "35834a8a",

  // ── 1 · the symbol universe ─────────────────────────────────────────────
  // The ONLY place a symbol is introduced. kind drives publisher cadence and
  // FE categorisation; every other symbol-keyed map below must reference a
  // key from here (CI-enforced).
  "symbols": {
    "BTCUSD":  { "kind": "perp" },
    "XAUUSD":  { "kind": "commodity" },
    "AAPLXUSD": { "kind": "xstock" }
    // …
  },

  // ── 2 · package identity, uniform ───────────────────────────────────────
  // EXACTLY these fields for every package — nothing package-specific here.
  "packages": {
    "waterx_perp": {
      "published_at": "0x…64hex",
      "original_id":  "0x…64hex",
      "version": 2,
      "upgrade_capability": "0x…64hex",   // optional
      "mvr": { "name": "@waterx-protocol/perp", "package_info_id": "0x…", "app_cap_id": "0x…" } // optional
    }
    // …every package, same shape
  },

  // ── 3 · shared objects, grouped by domain ───────────────────────────────
  // Object ids only, specific names, symbol maps reference §1.
  "objects": {
    "oracle":  { "oracle": "0x…", "listing_cap": "0x…",
                 "aggregators": { "BTCUSD": "0x…" } },
    "perp":    { "global_config": "0x…", "admin_cap": "0x…",
                 "markets": { "BTCUSD": { "market": "0x…", "config": "0x…" } } },
    "wlp":     { "pool": "0x…", "aum": "0x…", "currency_type": "0x…::wlp::WLP",
                 "pool_tokens": { "USDC": "0x…::usdc::USDC" } },
    "staking": { "pools": { "WLP": "0x…" }, "rewarders": { "WLP": { "USDC": { "rewarder_id": "0x…", "coin_type": "0x…", "decimals": 6 } } } },
    "account": { "registry": "0x…" },
    "referral": { "table": "0x…" },
    "credit":  { "registry": "0x…", "credit_type": "0x…::credit::CREDIT" },
    "custody": { "vault": "0x…", "assets": [ { "name": "tUSDC", "type": "0x…", "decimal": 6,
                 "mint_fee_scaled": "0", "burn_fee_scaled": "1000000", "min_burn_amount": "1000000" } ] },
    "bridge":  { "state": "0x…", "emitter_cap": "0x…",
                 "limits": { "max_mint_per_tx": "…", "max_burn_per_tx": "…",
                             "daily_mint": "…", "daily_burn": "…",
                             "personal_burn": { "cap_amount": "…", "window_ms": "…" } } },
    "withdrawal_queue": { "queue": "0x…" },
    "prediction": { "global_config": "0x…", "market_registries": { "USD": "0x…" },
                    "settlement_coin_types": { "USD": "0x…::usd::USD" },
                    "claimable_link_config": "0x…" }
  },

  // ── 4 · oracle rule registry, one roof, named shapes ────────────────────
  "oracle_rules": {
    "waterx": {
      "package": "waterx_rule",              // reference into §2
      "enclave": {                            // the ONE home for enclave identity
        "config": "0x…", "cap": "0x…", "object": "0x…",
        "pubkey": "03baaa…hex"                // was duplicated in two packages
      },
      // was waterx_rule.feeds — same content, honest name. weights stay an
      // OFF-CHAIN-ONLY trust surface (audit I-16) and keep their warning in
      // the schema description.
      "venue_feeds": {
        "BTCUSD": { "ticker": "BTCUSDT", "method": "confidence", "min_sources": 2,
                    "sources": [ { "name": "binance_usdm_perp_ws", "weight": 1 } ] }
      }
    },
    "pyth": {
      "package": "pyth_rule",
      "pyth_config_object": "0x…",           // was the fourth thing named `config`
      "pyth_price_feeds": {
        "SUIUSD": { "feed_id": "0x…", "price_info_object": "0x…" }
      }
    },
    "pyth_lazer": {
      "package": "pyth_lazer_rule",
      "lazer_state_object": "0x…",
      "lazer_feed_ids": { "SUIUSD": 11 }     // was a bare int keyed under `feeds`
    },
    "constant": {
      "package": "constant_rule",
      "constant_prices": { "USDCUSD": { "price": "1000000000" } }  // u128-dec9
    }
    // testnet additionally: "supra": { "package": "supra_rule", "pair_ids": { … } }
  },

  // ── 5 · non-Sui config ──────────────────────────────────────────────────
  "evm": { "bridge": { "chains": { "ethereum": { /* unchanged shape */ } } } }
}
```

Deploy forensics (`deploy_tx_log`, per-package `publish_digest` /
`publish_checkpoint`, `register_digest`/`register_checkpoint`) move to
**`deploys/<network>.json`** — same repo, same review, out of the document that
14 repos parse on every boot.

## v1 → v2 field map

Every v1 field, disposition and destination. "drop" = removed with its data
preserved in git history / `deploys/`.

| v1 | v2 | note |
|---|---|---|
| `packages.*.published_at / original_id / version / upgrade_capability / mvr` | `packages.*` unchanged | now the *only* fields there |
| `packages.*.publish_digest / publish_checkpoint` | `deploys/<network>.json` | audit P4/P7; zero runtime consumers |
| `packages.waterx_rule.register_digest / register_checkpoint` | `deploys/<network>.json` | same |
| `packages.waterx_rule.feeds` | `oracle_rules.waterx.venue_feeds` | shape unchanged; name honest |
| `packages.waterx_rule.enclave / enclave_cap / enclave_config / enclave_pubkey` | `oracle_rules.waterx.enclave.*` | P7 dedup — one home |
| `packages.enclave.enclave_pubkey` (duplicate) | *(dropped)* | reads move to `oracle_rules.waterx.enclave.pubkey` |
| `packages.waterx_rule.config` | `oracle_rules.waterx.rule_config_object` | de-generic'd |
| `packages.waterx_rule.enabled` (testnet) | *(drop or schema'd)* | owner to confirm semantics first |
| `packages.pyth_rule.feeds` | `oracle_rules.pyth.pyth_price_feeds` | |
| `packages.pyth_rule.config` | `oracle_rules.pyth.pyth_config_object` | |
| `packages.pyth_lazer_rule.feeds` | `oracle_rules.pyth_lazer.lazer_feed_ids` | bare int → still int, named |
| `packages.constant_rule.feeds` | `oracle_rules.constant.constant_prices` | |
| `packages.supra_rule.feeds` (testnet) | `oracle_rules.supra.pair_ids` | |
| `packages.waterx_oracle.aggregators` | `objects.oracle.aggregators` | keys ⊆ `symbols`; drop retired `USDCUSD` or except it |
| `packages.waterx_oracle.{oracle,listing_cap}` | `objects.oracle.*` | |
| `packages.waterx_perp.{markets,global_config,admin_cap,market_registry_wlp}` | `objects.perp.*` | |
| `packages.wlp.{wlp_pool,wlp_aum,currency,pool_tokens,metadata_cap}` | `objects.wlp.*` | de-prefixed (`wlp_pool`→`pool`) |
| `packages.waterx_staking.{pools,rewarders}` | `objects.staking.*` | |
| `packages.waterx_account.account_registry` | `objects.account.registry` | |
| `packages.waterx_referral.referral_table` | `objects.referral.table` | |
| `packages.waterx_credit.{credit_registry,credit_type}` | `objects.credit.*` | |
| `packages.native_custody.{vault,assets}` | `objects.custody.*` | `_comment` → schema description (P5) |
| `packages.wormhole_bridge.{bridge,emitter_cap,wormhole_state,…limits…}` | `objects.bridge.*` with a `limits` block | six loose fields → one block |
| `packages.withdrawal_queue.{queue,executors}` | `objects.withdrawal_queue.*` | `executors` becomes schema'd, both networks |
| `packages.waterx_prediction.*` objects | `objects.prediction.*` | |
| `packages.waterx_prediction_gift.claimable_link_config` | `objects.prediction.claimable_link_config` | |
| `coin_registry` | unchanged (schema'd in v2) | currently `z.any()` — needs its own pass |
| `evm` | unchanged | |
| `deploy_tx_log` | `deploys/<network>.json` | |
| — | `symbols` (new) | R2: the single symbol universe |
| — | `schema_version` (new) | consumers branch on it during migration |

## Why consumers get simpler

- **QC** (`config.rs`): reads `oracle_rules.waterx` — one subtree instead of
  fishing `feeds` out of `packages`, and the enclave identity it pins comes
  from the same subtree.
- **keeper**: `oracle_rules.*` is exactly its collect-order universe; the
  lazer ticker↔feed-id map it defensively validates today becomes
  schema-guaranteed one-to-one.
- **SDK/FE/BE**: `packages` becomes a uniform `Record<string, PackageIdentity>`
  — `packageIds()` loses its type-guard; object ids come from `objects.<domain>`
  with real names.
- **CI**: the ⊆-`symbols` rule replaces today's exception-list diffing for the
  common case; exceptions shrink to genuinely-intentional gaps (e.g. lazer not
  carrying fx).

## Rollout

1. Land the v2 schema next to v1 (`schema/v2/…`), plus a **derive script**
   that mechanically produces the v2 document from v1 (every mapping above is
   mechanical). CI proves v1→v2 derivation is lossless (modulo the dropped
   forensics, which land in `deploys/`).
2. Generated parsers gain a v2 mode; consumers migrate imports at their own
   pace while the CDN serves both (`/v2/mainnet.json` beside `/mainnet.json`).
3. When the last consumer flips (tracked in the audit's consumption matrix),
   v1 files freeze with a deprecation banner; one release later they are gone.

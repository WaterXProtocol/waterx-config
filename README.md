# waterx-config

On-chain deployment info (package ids, object ids, etc.) for each WaterX network, shared by the backend, SDK, frontend, and deployment scripts.

## How to read it (CDN)

Read through our own CDN. **Do not** hit `raw.githubusercontent.com` directly — GitHub's scraping rate limit will return 429:

- `https://config.waterx.app/mainnet.json`
- `https://config.waterx.app/testnet.json`

Hosted on Cloudflare Pages, wired to this repo's `main` branch. Pushing to main deploys automatically and purges the edge cache. Response headers (CORS, `Content-Type`, `Cache-Control`) live in [`_headers`](./_headers) at the repo root.

## Files

- `testnet.json` — Sui testnet deployment info (chain-id `4c78adac`), sourced from the `Published.toml` under each package in [`waterx-contract`](../waterx-contract).
- `mainnet.json` — Sui mainnet deployment info.

## Schema

```jsonc
{
  "network": "testnet | mainnet",
  "chain_id": "<sui chain id>",
  "packages": {
    "<package_name>": {
      "published_at": "0x...",      // package id of the current latest version
      "original_id":  "0x...",      // package id from the first publish (unchanged across upgrades; used for type tags)
      "version": 1,                  // package object version: 1 at first publish, +1 per upgrade
      "upgrade_capability": "0x..." // some packages: UpgradeCap object id
      // ...other package-specific shared object / cap ids
    }
  }
}
```

`published_at` is used to send transactions (calling that version's functions); `original_id` is used to build type tags (e.g. `<original_id>::module::Type`). Upgrading a package only changes `published_at` / `version`.

## Package-specific fields

| Package | Extra fields |
| --- | --- |
| `waterx_referral` | `referral_table` (shared `ReferralTable` object) |
| `pyth_rule` | `config` (shared `Config` object: `identifier_map` + `tolerance_sec_map`), `feeds` (per-ticker `{ feed_id, price_info_object }`) |
| `pyth_sponsor_rule` | `pyth_sponsor` (shared sponsor pool) |
| `constant_rule` | `config` (shared `Config` object), `feeds` (per-ticker `{ price }` — fixed-price assets like `USDCUSD`) |
| `waterx_account` | `admin_cap`, `account_registry` |
| `waterx_oracle` | `listing_cap`, `oracle`, `aggregators` (per-ticker `PriceAggregator` id) |
| `waterx_perp` | `admin_cap`, `global_config`, `market_registry_wlp`, `markets` (per-ticker `{ market, config }`) |
| `waterx_prediction` | `admin_cap`, `global_config`, `market_registries` (per-settlement-coin `MarketRegistry` id), `settlement_coin_types` |
| `waterx_prediction_gift` | `admin_cap`, `claimable_link_config` |
| `waterx_staking` | `admin_cap`, `pools`, `rewarders` |
| `waterx_credit` | `credit_registry`, `credit_type` (the USD stack — legacy singular aliases of `credit_registries.USD`), `credit_registries` (per-credit `{ registry, credit_type, decimals }`; see below) |
| `wlp` | `currency`, `metadata_cap`, `wlp_pool`, `wlp_aum` (shared `lp_pool::WlpAum<WLP>` object), `pool_tokens` (per-ticker CoinType bound via `lp_pool::add_token<WLP, C>`) |
| `usd_credit`, `sui_credit`, `deep_credit`, `wal_credit` | `metadata_cap` — the credit coin packages, each `<asset>_credit::<asset>::<ASSET>` (`…::usd::USD`, `…::sui::SUI`, `…::deep::DEEP`, `…::wal::WAL`). `mainnet.json` still carries the USD package under its pre-rename key `usd` (and no per-credit maps yet) until the mainnet follow-up lands. While a coin is published but its registry not yet created the block also carries `proof` (the one-shot `create_credit_registry` input) |
| `native_custody` | `vault`, `assets` (the USD vault — legacy singular aliases of `vaults.USD`), `vaults` (per-credit `{ vault, assets[] }`; see below) |
| `withdrawal_queue` | `queue`, `executors` (the USD queue — legacy singular aliases of `queues.USD`), `queues` (per-credit `{ queue, executors[] }`; see below) |
| `wormhole_bridge` | `bridge`, `wormhole_state`, `emitter_cap`, `personal_burn_cap`, `daily_mint_limit`, `daily_burn_limit`, `max_mint_per_tx`, `max_burn_per_tx` |
| `mock_usdsui` | `currency`, `treasury_cap`, `metadata_cap` |
| `supra_rule` | `config`, `feeds` |
| `waterx_rule` | `feeds` (per-symbol `{ ticker, sources[], method, kind }` — the off-chain quote-service feed registry; see below) |
| `testnet_faucet` | `faucet`, `whitelist` |

Packages may also carry `publish_checkpoint` / `publish_digest`, recording the checkpoint and transaction digest of the publish. Nearly every `testnet.json` package has them; on `mainnet.json` only a few do.

Testnet-only packages, absent from `mainnet.json`: `mock_sui`, `mock_usdc`, `mock_usdsui` (mainnet uses real CoinTypes), plus `testnet_faucet` and `supra_rule`. There are no mainnet-only packages.

`waterx_rule` is a special case: its on-chain package (`published_at` / `original_id` / …) is not yet deployed to mainnet (pending WL-1965), but its `feeds` registry — which the off-chain quote-service reads and which is independent of the package addresses — is carried on **both** networks so the service can boot with `NETWORK=mainnet`.

### Per-credit maps (`credit_registries` / `vaults` / `queues`)

The credit umbrella is generic over the `CREDIT` coin, and there is one stack per credit: a `CreditRegistry<CREDIT>` (on `waterx_credit`), a `CustodyVault<CREDIT>` (on `native_custody`) and a `Queue<CREDIT>` (on `withdrawal_queue`). Each of those packages carries a map keyed by the credit's short name — `"USD"` (backed by USDC / USDSUI), `"SUI"`, `"DEEP"`, `"WAL"` (each backed 1:1 by the asset it is named after, NativeCustody only, no Wormhole leg) — and the three maps always carry the same key set:

```jsonc
"waterx_credit": {
  // ...
  "credit_registry": "0x…",                       // legacy: same as credit_registries.USD.registry
  "credit_type":     "0x…::usd::USD",             // legacy: same as credit_registries.USD.credit_type
  "credit_registries": {
    "USD": { "registry": "0x…", "credit_type": "0x…::usd::USD",     "decimals": 6 },
    "SUI": { "registry": "0x…", "credit_type": "0x…::sui::SUI",     "decimals": 6 }
  }
},
"native_custody": {
  // ...
  "vault": "0x…", "assets": [ /* … */ ],          // legacy: same as vaults.USD
  "vaults": {
    "USD": { "vault": "0x…", "assets": [ { "name": "USDC", "type": "0x…::usdc::USDC", "decimal": 6, "mint_fee_scaled": "0", "burn_fee_scaled": "500000", "min_burn_amount": "0" } ] },
    "SUI": { "vault": "0x…", "assets": [ { "name": "SUI",  "type": "0x2::sui::SUI",   "decimal": 9, "mint_fee_scaled": "0", "burn_fee_scaled": "500000", "min_burn_amount": "0" } ] }
  }
},
"withdrawal_queue": {
  // ...
  "queue": "0x…", "executors": [ "0x…" ],         // legacy: same as queues.USD
  "queues": {
    "USD": { "queue": "0x…", "executors": [ "0x…" ] },
    "SUI": { "queue": "0x…", "executors": [ "0x…" ] }
  }
}
```

Every credit is a 6-decimal coin (`native_custody` scales each backing asset to 6 decimals), so `decimals` is the credit's, while `assets[].decimal` is the backing asset's — a 9-decimal SUI / WAL deposit must be a multiple of `1_000` base units. `mint_fee_scaled` / `burn_fee_scaled` are 1e9-scaled `Float` rates (`500000` = 0.05%). The singular `credit_registry` / `credit_type` / `vault` / `assets` / `queue` / `executors` fields are kept for consumers that still read only the USD stack; new code should read the maps. Bring-up of an additional credit is driven by [`waterx-contract/scripts/deploy/create-credit-registries.ts`](../waterx-contract/scripts/deploy/create-credit-registries.ts), which writes these entries (and the coin's package block) as each step lands.

### Per-ticker maps (`aggregators` / `markets` / `feeds`)

Listing a new trading pair adds one entry to each of these three maps, keyed by the oracle ticker (e.g. `"BTCUSD"`):

```jsonc
"waterx_oracle": {
  // ...
  "aggregators": {
    "BTCUSD": "0x<PriceAggregator id>"   // waterx_oracle::aggregator::PriceAggregator
  }
},
"waterx_perp": {
  // ...
  "market_registry_wlp": "0x<MarketRegistry<WLP> id>",   // one shared registry per LP type
  "markets": {
    "BTCUSD": {
      "market": "0x<Market<WLP> id>",     // waterx_perp::trading::Market<LP_TOKEN>, a DOF child of the registry
      "config": "0x<MarketConfig id>"     // embedded in Market.config; recorded here for convenience
    }
  }
},
"pyth_rule": {
  // ...
  "config": "0x<pyth_rule::Config id>",   // shared; holds each ticker's feed_id + tolerance_sec
  "feeds": {
    "BTCUSD": {
      "feed_id":           "0x<32-byte Pyth feed id>",         // the price feed id used by Hermes
      "price_info_object": "0x<Pyth PriceInfoObject id>"       // the matching shared PriceInfoObject on testnet/mainnet Pyth
    }
  }
}
```

`feed_id` is defined by Pyth and is usually **different** between testnet and mainnet (look them up via `hermes-beta.pyth.network` or `hermes.pyth.network`). `price_info_object` is Pyth's actual shared PriceInfoObject on that chain — not the `Field<PriceIdentifier, ID>` wrapper object inside the `price_info` table (that one cannot be passed directly as a transaction input).

For the listing flow of a new trading pair (create aggregator → wire up Pyth → create Market), see [`waterx-contract/.claude/skills/list-perp-asset/SKILL.md`](../waterx-contract/.claude/skills/list-perp-asset/SKILL.md).

### `waterx_rule.feeds` — off-chain quote-service registry

Unlike the Pyth/Supra `feeds` maps (which point at on-chain price objects), `waterx_rule.feeds` is the **feed registry the off-chain quote-service reads** to know which symbols to keep signed & fresh. It mirrors the on-chain `waterx_rule::FeedConfig` and is consumed by `quote-service/src/config.rs` (`load_remote` → `RemoteFeed`) — so the field names here are load-bearing. Keyed by oracle **symbol** (e.g. `"BTCUSD"`, not the exchange ticker). Most symbols happen to be the ticker minus its `USDT` suffix, but that is a coincidence rather than a rule — the crude feeds map `WTIUSD` → `CLUSDT` and `BRENTUSD` → `BZUSDT`, because the venues use the futures root symbols while the oracle key stays readable:

```jsonc
"waterx_rule": {
  "feeds": {
    "BTCUSD": {
      "ticker":  "BTCUSDT",                              // exchange ticker the enclave fetches
      "sources": ["binance_usdm_perp_ws", "..."],        // enclave source-id vocabulary (see below)
      "method":  "direct | median | confidence",          // aggregation method
      "kind":    "perp | spot | prediction | xstock | commodity"  // drives per-kind publish cadence
    }
  }
}
```

Source-id vocabulary (enclave string id → on-chain `u64`, a wire contract shared with `waterx_rule.move`; canonical list in `quote-service/src/resolve.rs`):

| id | source | note |
| --- | --- | --- |
| 1 | `binance_spot_ws` / `binance_spot_rest` | |
| 2 | `binance_usdm_perp_ws` | |
| 3 | `bybit_linear_perp_ws` | |
| 4 | `gateio_usdt_perp_ws` | |
| 5 | `bybit_spot_ws` | xStock token price |
| 6 | `xstock_equity_rest` | underlying equity via Alpaca |
| 7 | `okx_spot_ws` | xStock token price |
| 8 | `hyperliquid_perp_ws` | xStock token price |
| 9 | `gateio_spot_ws` | xStock token price |
| 10 | `kraken_spot_ws` | xStock token price |

Every `sources` entry must be in this vocabulary, and `sources`/`method` must match the on-chain `set_perp_feed` config field-for-field — a mismatch makes `waterx_rule` abort during validation (`are_perp_sources` / `is_perp_method`). `kind` is **not** an on-chain field: it is never passed to `set_perp_feed` and is read only by the off-chain quote-service to pick a publish cadence, so adding a new `kind` value cannot abort validation.

> **mainnet carries perp feeds only.** The xStock feeds (`kind: "xstock"`, source ids 5–10) are testnet-only until those source ids are registered on-chain on mainnet (WL-1968); enabling them in `mainnet.json` before that would abort validation.
>
> The commodity feeds (`kind: "commodity"` — `XAGUSD`/`XAUUSD`/`WTIUSD`/`BRENTUSD`) are a different case: they use only source ids 2–4, which are already registered on mainnet, so they would pass validation there. They are testnet-only as a **product** decision pending a mainnet soak, not a technical block.

## Update flow

1. Deploy or upgrade under `waterx-contract/<pkg>`; the Sui CLI updates `Published.toml`.
2. Sync the new addresses into the corresponding `testnet.json` / `mainnet.json`.
3. Commit the change.

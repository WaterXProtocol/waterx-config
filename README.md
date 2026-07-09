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
| `waterx_credit` | `credit_registry`, `credit_type` |
| `wlp` | `currency`, `metadata_cap`, `wlp_pool`, `wlp_aum` (shared `lp_pool::WlpAum<WLP>` object), `pool_tokens` (per-ticker CoinType bound via `lp_pool::add_token<WLP, C>`) |
| `usd` | `metadata_cap` |
| `native_custody` | `vault`, `assets` (per-asset backing config) |
| `withdrawal_queue` | `queue`, `executors` |
| `wormhole_bridge` | `bridge`, `wormhole_state`, `emitter_cap`, `personal_burn_cap`, `daily_mint_limit`, `daily_burn_limit`, `max_mint_per_tx`, `max_burn_per_tx` |
| `mock_usdsui` | `currency`, `treasury_cap`, `metadata_cap` |
| `supra_rule` | `config`, `feeds` |
| `testnet_faucet` | `faucet`, `whitelist` |

Packages may also carry `publish_checkpoint` / `publish_digest`, recording the checkpoint and transaction digest of the publish. Nearly every `testnet.json` package has them; on `mainnet.json` only a few do.

Testnet-only packages, absent from `mainnet.json`: `mock_sui`, `mock_usdc`, `mock_usdsui` (mainnet uses real CoinTypes), plus `testnet_faucet`, `supra_rule`, and `waterx_rule`. There are no mainnet-only packages.

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

## Update flow

1. Deploy or upgrade under `waterx-contract/<pkg>`; the Sui CLI updates `Published.toml`.
2. Sync the new addresses into the corresponding `testnet.json` / `mainnet.json`.
3. Commit the change.

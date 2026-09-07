# waterx-config field reference (flip target)

> Generated from [`schema/waterx-config-target.schema.json`](../schema/waterx-config-target.schema.json) by `scripts/gen-fields-doc.mjs target` — do not edit by hand.

## Top level

| field | type | notes |
|---|---|---|
| `schema_version` | 2 |  |
| `network` | "mainnet" \| "testnet" |  |
| `chain_id` | string |  |
| `symbols` | map<string, object> | The single symbol universe: the ONLY place a symbol is introduced. Every symbol-keyed map elsewhere must reference a key from here (CI-enforced). |
| `objects` | object |  |
| `oracle_rules` | object |  |
| `coin_registry` | string | Short-form Sui address/object id. |
| `evm` | object |  |

## Packages

### `(any package)`

| field | type | required | notes |
|---|---|---|---|
| `published_at` | suiId |  | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `original_id` | suiId |  | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `version` | integer |  | On-chain package version: 1 at first publish, +1 per upgrade. |
| `upgrade_capability` | suiId |  | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. |


## objects

### `objects.oracle`

| field | type | required | notes |
|---|---|---|---|
| `oracle` | suiId | ✓ |  |
| `listing_cap` | suiId | ✓ |  |
| `aggregators` | map<string, suiId> | ✓ | Per-symbol on-chain Aggregator object id — the cross-rule weighted-median aggregation point. |

### `objects.perp`

| field | type | required | notes |
|---|---|---|---|
| `global_config` | suiId | ✓ |  |
| `admin_cap` | suiId | ✓ | Admin capability object id. |
| `market_registry_wlp` | suiId | ✓ |  |
| `markets` | map<string, object> | ✓ | Per-symbol perp market: market + config object ids. |

### `objects.wlp`

| field | type | required | notes |
|---|---|---|---|
| `pool` | suiId | ✓ |  |
| `aum` | suiId | ✓ |  |
| `currency_type` | suiId | ✓ |  |
| `metadata_cap` | suiId | ✓ |  |
| `pool_tokens` | map<string, suiType> | ✓ |  |

### `objects.staking`

| field | type | required | notes |
|---|---|---|---|
| `admin_cap` | suiId | ✓ | Admin capability object id. |
| `pools` | map<string, suiId> | ✓ |  |
| `rewarders` | map<string, object> | ✓ |  |

### `objects.account`

| field | type | required | notes |
|---|---|---|---|
| `registry` | suiId | ✓ |  |
| `admin_cap` | suiId | ✓ | Admin capability object id. |

### `objects.referral`

| field | type | required | notes |
|---|---|---|---|
| `table` | suiId | ✓ |  |

### `objects.credit`

| field | type | required | notes |
|---|---|---|---|
| `registry` | suiId | ✓ |  |
| `credit_type` | suiType | ✓ |  |

### `objects.custody`

| field | type | required | notes |
|---|---|---|---|
| `vault` | suiId | ✓ |  |
| `assets` | array<object> | ✓ |  |

### `objects.bridge`

| field | type | required | notes |
|---|---|---|---|
| `state` | suiId | ✓ |  |
| `emitter_cap` | suiId | ✓ |  |
| `wormhole_state` | suiId | ✓ |  |
| `limits` | object | ✓ |  |

### `objects.withdrawal_queue`

| field | type | required | notes |
|---|---|---|---|
| `queue` | suiId | ✓ |  |
| `executors` | array<suiId> |  |  |

### `objects.prediction`

| field | type | required | notes |
|---|---|---|---|
| `global_config` | suiId | ✓ |  |
| `admin_cap` | suiId | ✓ | Admin capability object id. |
| `market_registries` | map<string, suiId> | ✓ |  |
| `settlement_coin_types` | map<string, suiType> | ✓ |  |
| `claimable_link_config` | suiId | ✓ |  |
| `gift_admin_cap` | suiId | ✓ |  |

### `objects.usd`

| field | type | required | notes |
|---|---|---|---|
| `metadata_cap` | suiId | ✓ |  |

### `objects.faucet`

| field | type | required | notes |
|---|---|---|---|
| `faucet` | suiId | ✓ |  |
| `whitelist` | array<suiId> | ✓ |  |

### `objects.mock_usdsui`

| field | type | required | notes |
|---|---|---|---|
| `currency_type` | suiId | ✓ |  |
| `metadata_cap` | suiId | ✓ |  |
| `treasury_cap` | suiId | ✓ |  |


## oracle_rules

### `oracle_rules.waterx`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `rule_config_object` | suiId | ✓ |  |
| `enclave` | object | ✓ | The ONE home for enclave identity (object, cap, config, pubkey). |
| `venue_feeds` | map<string, object> | ✓ | QC feed registry (was packages.waterx_rule.feeds). `weights` remain OFF-CHAIN ONLY — audit-scope I-16 trust surface. |

### `oracle_rules.pyth`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `pyth_config_object` | suiId | ✓ |  |
| `pyth_price_feeds` | map<string, object> | ✓ | Per-symbol Pyth price feed: feed_id (Pyth) + price_info_object (Sui object the keeper refreshes). |

### `oracle_rules.pyth_lazer`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `lazer_state_object` | suiId | ✓ |  |
| `lazer_config_object` | suiId | ✓ |  |
| `lazer_feed_ids` | map<string, integer> | ✓ | Per-symbol Pyth Lazer numeric feed id, as used by the keeper's Lazer WS subscription. |

### `oracle_rules.constant`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `rule_config_object` | suiId | ✓ |  |
| `constant_prices` | map<string, object> | ✓ | Per-symbol constant price, 1e9-scaled decimal string (e.g. "1000000000" = 1.0). |

### `oracle_rules.supra`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `rule_config_object` | suiId | ✓ |  |
| `pair_ids` | map<string, integer> | ✓ |  |

## Shared definitions

| def | pattern | meaning |
|---|---|---|
| `suiId` | `^0x[0-9a-fA-F]{64}$` | 32-byte Sui object/package id. |
| `suiType` | `^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$` | Fully-qualified Move type tag. |
| `decString` | `^[0-9]+$` | Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices). |

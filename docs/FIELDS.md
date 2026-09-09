# waterx-config field reference

> Generated from [`schema/waterx-config.schema.json`](../schema/waterx-config.schema.json) by `scripts/gen-fields-doc.mjs` — do not edit by hand.

## Top level

| field | type | notes |
|---|---|---|
| `schema_version` | 2 | Format discriminator. This repo serves only version 2 (the consolidated shape); parsers reject anything else. |
| `network` | "mainnet" \| "testnet" |  |
| `chain_id` | string |  |
| `symbols` | map<string, object> | The single symbol universe: the ONLY place a symbol is introduced. Every symbol-keyed map elsewhere must reference a key from here (CI-enforced). |
| `objects` | object |  |
| `oracle_rules` | object |  |
| `evm` | object |  |

## Packages

Every package carries the same identity block (the map is uniform — new packages need no schema change):

| field | type | required | notes |
|---|---|---|---|
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |
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

#### `objects.perp.markets` — each entry

| field | type | required | notes |
|---|---|---|---|
| `market` | suiId | ✓ |  |
| `config` | suiId | ✓ |  |

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
| `rewarders` | map<string, map<string, object>> | ✓ |  |

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
| `assets` | array<object> | ✓ | Native-custody asset rows. mint_fee_scaled / burn_fee_scaled are u128 1e9-scaled (0 = no fee; 1_000_000 = 0.1%; 1_000_000_000 = 100%). min_burn_amount is the dust floor in the asset's smallest unit. |

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

### `oracle_rules.pyth`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `pyth_config_object` | suiId | ✓ |  |
| `pyth_price_feeds` | map<string, object> | ✓ | Per-symbol Pyth price feed: feed_id (Pyth) + price_info_object (Sui object the keeper refreshes). |

#### `oracle_rules.pyth.pyth_price_feeds` — each entry

| field | type | required | notes |
|---|---|---|---|
| `feed_id` | suiId | ✓ | Pyth price-feed identifier (32-byte hex). NOT a Sui object id. |
| `price_info_object` | suiId | ✓ | The shared PriceInfoObject itself — NOT the Field<PriceIdentifier, ID> wrapper object; passing the wrapper is the classic mistake. |

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

#### `oracle_rules.constant.constant_prices` — each entry

| field | type | required | notes |
|---|---|---|---|
| `price` | decString | ✓ |  |

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

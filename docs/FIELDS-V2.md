# waterx-config v2 field reference

> Generated from [`schema/v2/waterx-config-v2.schema.json`](../schema/v2/waterx-config-v2.schema.json) by `scripts/gen-fields-doc.mjs v2` — do not edit by hand.

## Top level

| field | type | notes |
|---|---|---|
| `schema_version` | any |  |
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
| `published_at` | suiId |  |  |
| `original_id` | suiId |  |  |
| `version` | integer |  |  |
| `upgrade_capability` | suiId |  |  |
| `mvr` | object |  |  |


## objects

### `objects.oracle`

| field | type | required | notes |
|---|---|---|---|
| `oracle` | suiId | ✓ |  |
| `listing_cap` | suiId | ✓ |  |
| `aggregators` | map<string, suiId> | ✓ |  |

### `objects.perp`

| field | type | required | notes |
|---|---|---|---|
| `global_config` | suiId | ✓ |  |
| `admin_cap` | suiId | ✓ |  |
| `market_registry_wlp` | suiId | ✓ |  |
| `markets` | map<string, object> | ✓ |  |

### `objects.wlp`

| field | type | required | notes |
|---|---|---|---|
| `pool` | suiId | ✓ |  |
| `aum` | suiId | ✓ |  |
| `currency_type` | suiId | ✓ |  |
| `metadata_cap` | suiId | ✓ |  |
| `pool_tokens` | object | ✓ |  |

### `objects.staking`

| field | type | required | notes |
|---|---|---|---|
| `admin_cap` | suiId | ✓ |  |
| `pools` | object | ✓ |  |
| `rewarders` | object | ✓ |  |

### `objects.account`

| field | type | required | notes |
|---|---|---|---|
| `registry` | suiId | ✓ |  |
| `admin_cap` | suiId | ✓ |  |

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
| `admin_cap` | suiId | ✓ |  |
| `market_registries` | object | ✓ |  |
| `settlement_coin_types` | object | ✓ |  |
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
| `enclave` | object | ✓ |  |
| `venue_feeds` | map<string, object> | ✓ |  |

### `oracle_rules.pyth`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `pyth_config_object` | suiId | ✓ |  |
| `pyth_price_feeds` | map<string, object> | ✓ |  |

### `oracle_rules.pyth_lazer`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `lazer_state_object` | suiId | ✓ |  |
| `lazer_config_object` | suiId | ✓ |  |
| `lazer_feed_ids` | map<string, integer> | ✓ |  |

### `oracle_rules.constant`

| field | type | required | notes |
|---|---|---|---|
| `package` | string | ✓ |  |
| `rule_config_object` | suiId | ✓ |  |
| `constant_prices` | object | ✓ |  |

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
| `decString` | `^[0-9]+$` | Unsigned integer as a decimal string (u64/u128-safe). |

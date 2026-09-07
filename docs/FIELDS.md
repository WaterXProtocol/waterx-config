# waterx-config field reference

> Generated from [`schema/waterx-config.schema.json`](../schema/waterx-config.schema.json) by `scripts/gen-fields-doc.mjs` — do not edit by hand.

## Top level

| field | type | notes |
|---|---|---|
| `network` | "mainnet" \| "testnet" |  |
| `chain_id` | string |  |
| `coin_registry` | string | Short-form Sui address/object id. |
| `evm` | object |  |

## Packages

### `bucket_framework`

| field | type | required | notes |
|---|---|---|---|
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId |  | UpgradeCap object id. Deploy-time artifact; no runtime consumer. · present only on testnet today |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `constant_rule`

| field | type | required | notes |
|---|---|---|---|
| `config` | suiId | ✓ |  |
| `feeds` | object | ✓ | Per-symbol constant price, 1e9-scaled decimal string (e.g. "1000000000" = 1.0). |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `enclave`

| field | type | required | notes |
|---|---|---|---|
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `mock_sui`

> package exists only on testnet today

| field | type | required | notes |
|---|---|---|---|
| `original_id` | suiId |  | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). · present only on testnet today |
| `published_at` | suiId |  | Package id of the current latest version — the tx-call target. Changes on every upgrade. · present only on testnet today |
| `upgrade_capability` | suiId |  | UpgradeCap object id. Deploy-time artifact; no runtime consumer. · present only on testnet today |
| `version` | integer |  | On-chain package version: 1 at first publish, +1 per upgrade. · present only on testnet today |

### `mock_usdc`

> package exists only on testnet today

| field | type | required | notes |
|---|---|---|---|
| `original_id` | suiId |  | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). · present only on testnet today |
| `published_at` | suiId |  | Package id of the current latest version — the tx-call target. Changes on every upgrade. · present only on testnet today |
| `version` | integer |  | On-chain package version: 1 at first publish, +1 per upgrade. · present only on testnet today |

### `mock_usdsui`

> package exists only on testnet today

| field | type | required | notes |
|---|---|---|---|
| `currency` | suiId |  | present only on testnet today |
| `metadata_cap` | suiId |  | present only on testnet today |
| `original_id` | suiId |  | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). · present only on testnet today |
| `published_at` | suiId |  | Package id of the current latest version — the tx-call target. Changes on every upgrade. · present only on testnet today |
| `treasury_cap` | suiId |  | present only on testnet today |
| `upgrade_capability` | suiId |  | UpgradeCap object id. Deploy-time artifact; no runtime consumer. · present only on testnet today |
| `version` | integer |  | On-chain package version: 1 at first publish, +1 per upgrade. · present only on testnet today |

### `native_custody`

| field | type | required | notes |
|---|---|---|---|
| `assets` | array<object> | ✓ |  |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `vault` | suiId | ✓ |  |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `pyth_lazer_rule`

> package exists only on mainnet today

| field | type | required | notes |
|---|---|---|---|
| `config` | suiId |  | present only on mainnet today |
| `feeds` | map<string, integer> |  | Per-symbol Pyth Lazer numeric feed id, as used by the keeper's Lazer WS subscription. · present only on mainnet today |
| `original_id` | suiId |  | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). · present only on mainnet today |
| `published_at` | suiId |  | Package id of the current latest version — the tx-call target. Changes on every upgrade. · present only on mainnet today |
| `state` | suiId |  | present only on mainnet today |
| `upgrade_capability` | suiId |  | UpgradeCap object id. Deploy-time artifact; no runtime consumer. · present only on mainnet today |
| `version` | integer |  | On-chain package version: 1 at first publish, +1 per upgrade. · present only on mainnet today |

### `pyth_rule`

| field | type | required | notes |
|---|---|---|---|
| `config` | suiId | ✓ |  |
| `feeds` | map<string, object> | ✓ | Per-symbol Pyth price feed: feed_id (Pyth) + price_info_object (Sui object the keeper refreshes). |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `supra_rule`

> package exists only on testnet today

| field | type | required | notes |
|---|---|---|---|
| `config` | suiId |  | present only on testnet today |
| `feeds` | map<string, object> |  | present only on testnet today |
| `original_id` | suiId |  | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). · present only on testnet today |
| `published_at` | suiId |  | Package id of the current latest version — the tx-call target. Changes on every upgrade. · present only on testnet today |
| `upgrade_capability` | suiId |  | UpgradeCap object id. Deploy-time artifact; no runtime consumer. · present only on testnet today |
| `version` | integer |  | On-chain package version: 1 at first publish, +1 per upgrade. · present only on testnet today |

### `testnet_faucet`

> package exists only on testnet today

| field | type | required | notes |
|---|---|---|---|
| `faucet` | suiId |  | present only on testnet today |
| `original_id` | suiId |  | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). · present only on testnet today |
| `published_at` | suiId |  | Package id of the current latest version — the tx-call target. Changes on every upgrade. · present only on testnet today |
| `upgrade_capability` | suiId |  | UpgradeCap object id. Deploy-time artifact; no runtime consumer. · present only on testnet today |
| `version` | integer |  | On-chain package version: 1 at first publish, +1 per upgrade. · present only on testnet today |
| `whitelist` | array<suiId> |  | present only on testnet today |

### `usd`

| field | type | required | notes |
|---|---|---|---|
| `metadata_cap` | suiId | ✓ |  |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_account`

| field | type | required | notes |
|---|---|---|---|
| `account_registry` | suiId | ✓ |  |
| `admin_cap` | suiId | ✓ | Admin capability object id. |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_credit`

| field | type | required | notes |
|---|---|---|---|
| `credit_registry` | suiId | ✓ |  |
| `credit_type` | suiType | ✓ |  |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_oracle`

| field | type | required | notes |
|---|---|---|---|
| `aggregators` | map<string, suiId> | ✓ | Per-symbol on-chain Aggregator object id — the cross-rule weighted-median aggregation point. |
| `listing_cap` | suiId | ✓ |  |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `oracle` | suiId | ✓ |  |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_perp`

| field | type | required | notes |
|---|---|---|---|
| `admin_cap` | suiId | ✓ | Admin capability object id. |
| `global_config` | suiId | ✓ |  |
| `market_registry_wlp` | suiId | ✓ |  |
| `markets` | map<string, object> | ✓ | Per-symbol perp market: market + config object ids. |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_perp_view`

| field | type | required | notes |
|---|---|---|---|
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_prediction`

| field | type | required | notes |
|---|---|---|---|
| `admin_cap` | suiId | ✓ | Admin capability object id. |
| `global_config` | suiId | ✓ |  |
| `market_registries` | object | ✓ |  |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `settlement_coin_types` | object | ✓ |  |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_prediction_gift`

| field | type | required | notes |
|---|---|---|---|
| `admin_cap` | suiId | ✓ | Admin capability object id. |
| `claimable_link_config` | suiId | ✓ |  |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_referral`

| field | type | required | notes |
|---|---|---|---|
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `referral_table` | suiId | ✓ |  |
| `upgrade_capability` | suiId |  | UpgradeCap object id. Deploy-time artifact; no runtime consumer. · present only on testnet today |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_rule`

| field | type | required | notes |
|---|---|---|---|
| `config` | suiId | ✓ |  |
| `enclave` | suiId | ✓ |  |
| `enclave_cap` | suiId | ✓ |  |
| `enclave_config` | suiId | ✓ |  |
| `enclave_pubkey` | string | ✓ | Registered enclave ed25519 pubkey (hex, no 0x). The SOLE config home (the enclave package block carries identity only); k8s-infra pins an independent env copy by design (boot-without-enclave). |
| `feeds` | map<string, object> | ✓ | QC feed registry, keyed by oracle symbol. The `weights` inside are OFF-CHAIN ONLY: waterx_rule on-chain validates sources/ticker/method/min_sources but has no notion of weights, so a weight change moves the signed price via a parameter no on-chain check can see (waterx-quote-center audit-scope I-16). Review weight changes as a trust-surface change. |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `waterx_staking`

| field | type | required | notes |
|---|---|---|---|
| `admin_cap` | suiId | ✓ | Admin capability object id. |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `pools` | object | ✓ |  |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `rewarders` | object | ✓ |  |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `withdrawal_queue`

| field | type | required | notes |
|---|---|---|---|
| `executors` | array<suiId> |  | present only on testnet today |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `queue` | suiId | ✓ |  |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |

### `wlp`

| field | type | required | notes |
|---|---|---|---|
| `currency` | suiId | ✓ |  |
| `metadata_cap` | suiId | ✓ |  |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `pool_tokens` | object | ✓ |  |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |
| `wlp_aum` | suiId | ✓ |  |
| `wlp_pool` | suiId | ✓ |  |

### `wormhole_bridge`

| field | type | required | notes |
|---|---|---|---|
| `bridge` | suiId | ✓ |  |
| `daily_burn_limit` | decString | ✓ |  |
| `daily_mint_limit` | decString | ✓ |  |
| `emitter_cap` | suiId | ✓ |  |
| `max_burn_per_tx` | decString | ✓ |  |
| `max_mint_per_tx` | decString | ✓ |  |
| `mvr` | object |  | Move Registry (MVR) registration for this package. Mainnet only today. · present only on mainnet today |
| `original_id` | suiId | ✓ | Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type). |
| `personal_burn_cap` | object | ✓ |  |
| `published_at` | suiId | ✓ | Package id of the current latest version — the tx-call target. Changes on every upgrade. |
| `upgrade_capability` | suiId | ✓ | UpgradeCap object id. Deploy-time artifact; no runtime consumer. |
| `version` | integer | ✓ | On-chain package version: 1 at first publish, +1 per upgrade. |
| `wormhole_state` | suiId | ✓ |  |

## Shared definitions

| def | pattern | meaning |
|---|---|---|
| `suiId` | `^0x[0-9a-fA-F]{64}$` | 32-byte Sui object/package id. |
| `suiType` | `^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$` | Fully-qualified Move type tag. |
| `decString` | `^[0-9]+$` | Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices). |

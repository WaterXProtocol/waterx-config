# waterx-config

WaterX 各網路的鏈上部署資訊（package id、object id 等），給後端、SDK、前端及部署腳本共用。

## 檔案

- `testnet.json` — Sui testnet 部署資訊（chain-id `4c78adac`），來源為 [`waterx-contract`](../waterx-contract) 各套件下的 `Published.toml`。
- `mainnet.json` — Sui mainnet 部署資訊，目前所有欄位為 `null`，待 mainnet 部署後填入。

## Schema

```jsonc
{
  "network": "testnet | mainnet",
  "chain_id": "<sui chain id>",
  "packages": {
    "<package_name>": {
      "published_at": "0x...",      // 目前最新版本的 package id
      "original_id":  "0x...",      // 第一次發布的 package id（升級後仍不變，用於 type tag）
      "version": 1,                  // upgrade 次數
      "upgrade_capability": "0x..." // 部分套件：UpgradeCap object id
      // ...其他套件特有的 shared object / cap id
    }
  }
}
```

`published_at` 用於發送交易（呼叫該版本的函式）；`original_id` 用於組 type tag（例如 `<original_id>::module::Type`）。升級套件時只有 `published_at` / `version` 會變動。

## 套件補充欄位

| 套件 | 額外欄位 |
| --- | --- |
| `waterx_referral` | `referral_table`（共用的 `ReferralTable` 物件） |
| `mock_usdsui` | `currency`, `treasury_cap`, `metadata_cap` |
| `pyth_rule` | `config`（shared `Config` 物件：`identifier_map` + `tolerance_sec_map`），`feeds`（per-ticker `{ feed_id, price_info_object }`） |
| `pyth_sponsor_rule` | `pyth_sponsor`（共用的 sponsor pool） |
| `waterx_account` | `admin_cap`, `account_registry` |
| `waterx_oracle` | `listing_cap`, `oracle`, `aggregators`（per-ticker `PriceAggregator` id） |
| `waterx_perp` | `admin_cap`, `global_config`, `market_registry_wlp`, `markets`（per-ticker `{ market, config }`） |
| `waterx_prediction` | `admin_cap`, `global_config`, `market_registries`（per-settlement coin `MarketRegistry` id）, `settlement_coin_types` |
| `wlp` | `currency`, `metadata_cap`, `wlp_pool`, `pool_tokens`（per-ticker CoinType bound via `lp_pool::add_token<WLP, C>`） |

`mock_sui` / `mock_usdc` / `mock_usdsui` 為 testnet-only，mainnet 使用真實 CoinType，故 `mainnet.json` 不含這些套件。

### Per-ticker maps (`aggregators` / `markets` / `feeds`)

每上一個新交易對都會在這三個 map 各新增一筆，key 是 oracle ticker（例如 `"BTCUSD"`）：

```jsonc
"waterx_oracle": {
  // ...
  "aggregators": {
    "BTCUSD": "0x<PriceAggregator id>"   // waterx_oracle::aggregator::PriceAggregator
  }
},
"waterx_perp": {
  // ...
  "market_registry_wlp": "0x<MarketRegistry<WLP> id>",   // 每個 LP 型別一個 shared registry
  "markets": {
    "BTCUSD": {
      "market": "0x<Market<WLP> id>",     // waterx_perp::trading::Market<LP_TOKEN>，registry 的 DOF child
      "config": "0x<MarketConfig id>"     // 內嵌在 Market.config，記錄方便查詢
    }
  }
},
"pyth_rule": {
  // ...
  "config": "0x<pyth_rule::Config id>",   // 共用，存放每 ticker 的 feed_id + tolerance_sec
  "feeds": {
    "BTCUSD": {
      "feed_id":           "0x<32-byte Pyth feed id>",         // Hermes 對應的 price feed id
      "price_info_object": "0x<Pyth PriceInfoObject id>"       // testnet/mainnet Pyth 上對應的 shared PriceInfoObject
    }
  }
}
```

`feed_id` 由 Pyth 定義，testnet 與 mainnet 通常**不同**（要用 `hermes-beta.pyth.network` 或 `hermes.pyth.network` 找）。`price_info_object` 是 Pyth 在該鏈上實際的共享 PriceInfoObject，不是 `price_info` table 內的 `Field<PriceIdentifier, ID>` 包裝物件（後者不能直接當交易輸入）。

新交易對的上線流程（建立 aggregator → 接 Pyth → 建 Market）參見 [`waterx-contract/.claude/skills/list-perp-asset/SKILL.md`](../waterx-contract/.claude/skills/list-perp-asset/SKILL.md)。

## 更新流程

1. 在 `waterx-contract/<pkg>` 下執行部署或升級，Sui CLI 會更新 `Published.toml`。
2. 將新地址同步到對應的 `testnet.json` / `mainnet.json`。
3. 提交變更。

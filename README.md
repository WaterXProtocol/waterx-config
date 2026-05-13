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
| `mock_usdsui` | `currency`, `treasury_cap`, `metadata_cap` |
| `pyth_sponsor_rule` | `pyth_sponsor`（共用的 sponsor pool） |
| `wlp` | `currency`, `metadata_cap`, `wlp_pool` |

`mock_sui` / `mock_usdc` / `mock_usdsui` 為 testnet-only，mainnet 使用真實 CoinType，故 `mainnet.json` 不含這些套件。

## 更新流程

1. 在 `waterx-contract/<pkg>` 下執行部署或升級，Sui CLI 會更新 `Published.toml`。
2. 將新地址同步到對應的 `testnet.json` / `mainnet.json`。
3. 提交變更。

# @waterx/config

The official typed loader for WaterX network config files (the consolidated
shape, `schema_version: 2`), generated from the canonical JSON Schema in
[waterx-config](https://github.com/WaterXProtocol/waterx-config).

```ts
import { loadWaterxConfig } from "@waterx/config";
const cfg = await loadWaterxConfig("mainnet"); // fetches config.waterx.app, retries 429/5xx
cfg.oracle_rules.waterx.venue_feeds["BTCUSD"].sources; // fully typed
```

- **Never** read `raw.githubusercontent.com` — it is 429-rate-limited; the
  loader refuses it. The CDN (`config.waterx.app`) is the only sanctioned source.
- Unknown fields are accepted but **not preserved** in the typed result: open
  maps (e.g. `packages`) keep every entry, unknown fields on known objects are
  stripped. Do not re-serialize a parse result into a config file — patch the
  original document and use `parseWaterxConfig` to validate it.
- Full field reference: [docs/FIELDS.md](https://github.com/WaterXProtocol/waterx-config/blob/main/docs/FIELDS.md).

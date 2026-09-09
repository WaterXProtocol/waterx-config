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

The canonical, machine-checked schema lives at [`schema/waterx-config.schema.json`](./schema/waterx-config.schema.json);
the rendered field reference is [`docs/FIELDS.md`](./docs/FIELDS.md). Both network
files are validated against it on every PR, and every keyspace/field difference
between networks or symbol maps must be declared in
[`schema/coverage-exceptions.json`](./schema/coverage-exceptions.json) — new,
undeclared drift fails CI.

**The served format is the consolidated shape (`schema_version: 2`)** — there
is no legacy format (see [`docs/FLIP-PLAN.md`](./docs/FLIP-PLAN.md) for what
changed and the old→new path map).

**Do not hand-roll config types in a consuming repo.** Use the generated parsers:

- TypeScript: [`packages/ts`](./packages/ts) — `@waterx/config` (Zod
  validator + CDN loader; refuses raw.githubusercontent, retries 429/5xx).
  *Not yet published* — first publish happens on the first `v*` tag once npm
  trusted publishing is configured (see `publish.yml`).
- Rust: [`packages/rust`](./packages/rust) — `waterx-config` crate, consumed
  via git tag (tolerant serde types — the strict gate is this repo's ajv CI —
  optional `fetch` feature with a `load_waterx_config_from(base, network)`
  override for the staging CDN).

Parsing returns the typed view: unknown fields on known objects are stripped
(open maps keep every entry). **Never write a parse result back to a config
file** — read-modify-write tools must patch the original document and use the
parser only to validate.

Both are **generated from the schema** (`codegen.yml` fails any PR where they
drift); edit the schema, never the generated files.

## Listing a feed — read this first

- Venue composition (which exchanges feed a symbol, with what weights and
  method) does **not** live in this repo any more: quote-center #191 moved it
  to quote-service's Spot-BBO consensus config (`BBO_CONFIG_PATH` /
  `BBO_SIGNING_CONFIG_PATH`), which retired `venue_feeds` — and with it the
  audit-I-16 off-chain weights trust surface — from the served files. The
  symbol universe here is `symbols` (and the per-symbol on-chain objects in
  `objects.oracle.aggregators`). The old symbol-vs-ticker gotcha (oracle
  `WTIUSD` trades as venue `CLUSDT`, never `WTIUSDT` — a wrong ticker fetches
  nothing, silently) moved with it: it now applies to the BBO config files.
- `oracle_rules.pyth.pyth_price_feeds[].feed_id` is usually **different
  between testnet and mainnet** — look each up in its own Hermes
  (hermes-beta.pyth.network vs hermes.pyth.network); `price_info_object` must
  be the shared `PriceInfoObject` itself, **not** the
  `Field<PriceIdentifier, ID>` wrapper.
- The end-to-end listing runbook (create aggregator → wire the rule → create
  market) lives in
  [`waterx-contract/.claude/skills/list-perp-asset/SKILL.md`](https://github.com/WaterXProtocol/waterx-contract/blob/main/.claude/skills/list-perp-asset/SKILL.md).

## Update flow

On-chain state changes in [`waterx-contract`](https://github.com/WaterXProtocol/waterx-contract)
(deploy/upgrade/register), whose tooling syncs ids into `{network}.json` here;
the change lands as a PR. Deploy forensics (publish digests/checkpoints, the
tx log) live in [`deploys/`](./deploys/) — **not** in the served config —
so the contract repo's sync scripts must write there.

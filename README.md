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

- `symbol` is the oracle key (`BTCUSD`); `ticker` is the venue's own spelling —
  **never derive one from the other**. Crude oil is the standing example:
  `WTIUSD`/`BRENTUSD` trade as `CLUSDT`/`BZUSDT`, not `WTIUSDT`/`BRENTUSDT`.
  A wrong ticker does not error — the feed silently never fetches.
- `oracle_rules.waterx.venue_feeds[].sources[].name` and `method` are a **wire
  vocabulary** shared with `waterx_rule.move`'s on-chain u64 source registry
  and quote-service `resolve.rs`; CI pins the exact spelling
  (`schema/waterx-config.gate.json`). A source id must be **registered
  on-chain for the target network** before a feed lists it — an unregistered
  id aborts on-chain validation at feed time. Ids 1–11 are registered on BOTH
  networks (verified on-chain 2026-09-08; per-network registration history:
  WL-1968). The full id table is in [FIELDS.md](./docs/FIELDS.md) under
  `oracle_rules.waterx.venue_feeds — each entry`.
- The on-chain `FeedConfig` (`set_perp_feed`) pins `ticker`, `sources` and
  `method` **field-for-field**: a config entry that disagrees with the
  on-chain record aborts every publish tick for that symbol
  (`ESourceMismatch`). `kind` (in `symbols`) is NOT on-chain — it only drives
  per-kind publish cadence off-chain, so a kind change can never abort.
- `weights` are **off-chain only** (audit I-16): review weight changes as
  trust-surface changes.
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

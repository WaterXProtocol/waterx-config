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
the rendered field references are [`docs/FIELDS.md`](./docs/FIELDS.md) (current shape) and [`docs/FIELDS-TARGET.md`](./docs/FIELDS-TARGET.md) (the flip target — see [`docs/FLIP-PLAN.md`](./docs/FLIP-PLAN.md)). Both network
files are validated against it on every PR, and every keyspace/field difference
between networks or symbol maps must be declared in
[`schema/coverage-exceptions.json`](./schema/coverage-exceptions.json) — new,
undeclared drift fails CI.

**Do not hand-roll config types in a consuming repo.** Use the generated parsers:

- TypeScript: [`packages/ts`](./packages/ts) — `@waterx-protocol/config` (Zod
  validator + CDN loader; refuses raw.githubusercontent).
- Rust: [`packages/rust`](./packages/rust) — `waterx-config` crate
  (tolerant serde types — the strict gate is this repo's ajv CI — optional `fetch` feature).

Both are **generated from the schema** (`codegen.yml` fails any PR where they
drift); edit the schema, never the generated files.

### Field reference

The full field-by-field reference is generated from the schemas — do not
document fields by hand here: [`docs/FIELDS.md`](./docs/FIELDS.md) (current
shape) · [`docs/FIELDS-TARGET.md`](./docs/FIELDS-TARGET.md) (flip target).

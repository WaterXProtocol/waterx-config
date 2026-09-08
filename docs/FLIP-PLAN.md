# waterx-config format flip — decision record (EXECUTED)

Status: **done** — the served `mainnet.json`/`testnet.json` ARE the
consolidated shape (`schema_version: 2`) as of the `v2` branch. There is no
legacy format, no lift, and no parallel serving; this file is the record of
what changed and what consumers must do.

Promotion flow: `v2` merges into **staging** first (flipping the staging CDN
alias), then reaches main — and config.waterx.app — through the normal
staging→main promotion. The guard needs no special allowance for this.

## The shape

One `symbols` universe (the only place a symbol is introduced; every
symbol-keyed map is CI-checked ⊆ it), uniform `packages` identity blocks,
domain-grouped `objects`, and a named per-rule `oracle_rules` registry.
Full field reference: [FIELDS.md](./FIELDS.md).

## Consumer impact (breaking, accepted by decision 2026-09-07)

Merging to `main` deploys the new shape to config.waterx.app immediately
(60s edge TTL). **Merging to `staging` is NOT the safe half**: the staging
branch serves the live `staging.waterx-config.pages.dev` alias, which
waterx-sdk CI hard-defaults to (`WATERX_CONFIG_URL` fallback; the repo
variable override is unset) — so the staging PR breaks waterx-sdk CI on all
branches the moment it merges, and nothing guards merges into staging.
Sequence accordingly: pin waterx-sdk's `WATERX_CONFIG_URL` (or land its
migration) BEFORE the staging merge.

**Verified per-repo blast radius** (traced 2026-09-08; no consumer repo has a
migration in flight — every one must migrate to the generated parsers
(`@waterx/config` / the `waterx-config` crate) or repoint its reads first).
Note the SDK-CI hazard above bites at the **v2→staging** merge; the rest bite
at the staging→main promotion:

| consumer | what happens on flip | mode |
|---|---|---|
| waterx-quote-center | boots `bail!("no packages.waterx_rule.feeds")` → CrashLoopBackOff, no signed prices, both networks | loud |
| bucket-backend-mono | `Object.entries(undefined)` in registry `onModuleInit` → whole app restart loop | loud |
| data-infra **oracle service** | boot throw under both `ORACLE_SOURCE` values (this consumer was previously missing from this list) | loud |
| waterx-keeper | one `warn`, then **permanent fallback to the bundled snapshot**; refresh worker rejects every later remote config | **silent** |
| waterx-sdk | `validateConfig` passes (checks `published_at` only) but every object-id read is `undefined` → tx-build throws deep in @mysten/sui; `isConstantTicker("USDCUSD")` goes false → **the WLP collateral price stops refreshing** (no Pyth fallback exists for USDCUSD) | **silent** |
| waterx-fe | reads raw.githubusercontent.com @ `main` (violating this repo's own CDN rule) → flips at merge instant; read-plane serves **$0 prices** for unresolved tickers | **silent** |
| waterx-contract | next config PR red on ajv (intended), but the `price_info_object` backfill also SKIPS silently and nothing writes `objects.*`/`oracle_rules.*` | mixed |

The old→new path map:

| old path | new path |
|---|---|
| `packages.waterx_rule.feeds` | `oracle_rules.waterx.venue_feeds` (feed `kind` moved to `symbols`) |
| `packages.waterx_rule.enclave*` | `oracle_rules.waterx.enclave.{object,cap,config,pubkey}` |
| `packages.pyth_rule.{config,feeds}` | `oracle_rules.pyth.{pyth_config_object,pyth_price_feeds}` |
| `packages.pyth_lazer_rule.feeds` | `oracle_rules.pyth_lazer.lazer_feed_ids` |
| `packages.constant_rule.feeds` | `oracle_rules.constant.constant_prices` |
| `packages.supra_rule.feeds[].pair_id` | `oracle_rules.supra.pair_ids` |
| `packages.waterx_oracle.{oracle,listing_cap,aggregators}` | `objects.oracle.*` |
| `packages.waterx_perp.{markets,global_config,admin_cap,market_registry_wlp}` | `objects.perp.*` |
| `packages.wlp.*` | `objects.wlp.*` (`wlp_pool`→`pool`, `wlp_aum`→`aum`, `currency`→`currency_type`) |
| `packages.waterx_staking.{pools,rewarders,admin_cap}` | `objects.staking.*` |
| `packages.waterx_account.account_registry` | `objects.account.registry` |
| `packages.waterx_referral.referral_table` | `objects.referral.table` |
| `packages.waterx_credit.*` | `objects.credit.*` |
| `packages.native_custody.{vault,assets}` | `objects.custody.*` |
| `packages.wormhole_bridge.*` | `objects.bridge.*` (limits under `objects.bridge.limits`) |
| `packages.withdrawal_queue.*` | `objects.withdrawal_queue.*` |
| `packages.waterx_prediction*.*` | `objects.prediction.*` |
| `packages.*.{published_at,original_id,version,upgrade_capability,mvr}` | **unchanged** |
| `packages.waterx_rule.enabled` (testnet) | **dropped** — never read by any repo; last value `true`; recorded here, not archived in deploys/ |

Truly identity-only readers are unaffected — of the consumers traced, that is
**only data-infra's two indexers** (they read `packages.*.original_id` +
`network` and nothing else). The SDK is NOT identity-only (see the table
above), despite validating only `published_at`.

## Producer impact — ACTION REQUIRED in waterx-contract

`deploy.ts` / `setup-mvr.ts` still write `publish_digest`/`publish_checkpoint`
and `deploy_tx_log` into `{network}.json`, and must be repointed at
[`deploys/<network>.json`](../deploys/) (the forensics archive) and taught the
new layout for object-id syncs. Until then, the next deploy's config PR will
fail ajv here — deliberately, rather than silently reintroducing the old shape.

## Governance still owed (repo admin / npm org admin)

- The ruleset currently targets no refs (`ref_name.include: []`) so NO check
  is enforced — point it at `refs/heads/main` and require
  `schema-consistency-and-ts-parser`, `rust-parser-parses-instances`, `regen`
  and the guard. `regen` is safe to require: codegen.yml runs on every PR as
  the check's SINGLE producer and decides internally whether regeneration is
  needed — no path filter, so no deadlock and no ambiguous duplicate context.
- npm: add this repo as a **Trusted Publisher** for `@waterx/config` on
  npmjs.com (the org's existing OIDC model; publish.yml carries no token).

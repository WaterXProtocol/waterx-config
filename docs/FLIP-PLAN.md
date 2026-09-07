# waterx-config format flip — decision record (EXECUTED)

Status: **done** — the served `mainnet.json`/`testnet.json` ARE the
consolidated shape (`schema_version: 2`) as of the staging-v2/main-v2 branch
line. There is no legacy format, no lift, and no parallel serving; this file
is the record of what changed and what consumers must do.

## The shape

One `symbols` universe (the only place a symbol is introduced; every
symbol-keyed map is CI-checked ⊆ it), uniform `packages` identity blocks,
domain-grouped `objects`, and a named per-rule `oracle_rules` registry.
Full field reference: [FIELDS.md](./FIELDS.md).

## Consumer impact (breaking, accepted by decision 2026-09-07)

Merging to `main` deploys the new shape to config.waterx.app immediately.
Every consumer that reads legacy paths directly breaks until it migrates to
the generated parsers (`@waterx-protocol/config` / the `waterx-config` crate)
or repoints its reads:

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

Identity-only readers (`published_at`/`original_id` — the SDK's packageIds,
data-infra's indexer) are unaffected.

## Producer impact — ACTION REQUIRED in waterx-contract

`deploy.ts` / `setup-mvr.ts` still write `publish_digest`/`publish_checkpoint`
and `deploy_tx_log` into `{network}.json`, and must be repointed at
[`deploys/<network>.json`](../deploys/) (the forensics archive) and taught the
new layout for object-id syncs. Until then, the next deploy's config PR will
fail ajv here — deliberately, rather than silently reintroducing the old shape.

## Governance still owed (repo admin)

The ruleset currently targets no refs (`ref_name.include: []`) so NO check is
enforced — point it at `refs/heads/main`, require
`schema-consistency-and-ts-parser`, `rust-parser-parses-instances`, `regen`
(with a same-name no-op job for path-skipped PRs) and the guard; and retire
the `main-v2` allowance in guard-main-merges.yml after the promotion merges.

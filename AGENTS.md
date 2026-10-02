# waterx-config

On-chain deployment ids per WaterX network, served from `https://config.waterx.app/{network}.json`
by Cloudflare Pages wired to `main` (`_headers`: CORS and a 60 s client cache).

Both Claude Code (v2.1.281+) and Codex read this file. Do not add a CLAUDE.md anywhere in the repo: Claude Code ignores every AGENTS.md at or below a directory that has one.

**A push to `main` is a production
publish** — Pages deploys and purges the edge on merge, so a change to `mainnet.json` is a live
config change for the backend, SDK, frontend, keeper and quote-center at once.

Branches: `main` / `staging` serve the v1 lineage today; this branch (`main-v2`, with
`staging-v2`) carries the consolidated `schema_version: 2` shape and reaches production through
the v2 flip PR (`main-v2` → `main`; `docs/FLIP-PLAN.md` is the record and the per-consumer blast
radius). `.github/workflows/guard-main-merges.yml` fails any PR into `main` whose source is not
`staging`. A data change on the v1 pair usually needs a twin here, resolved to the v2 shape (the
merge commits "Merge branch 'main' into main-v2 — resolved to the v2 shape" are the pattern).
`publish.yml` publishes npm `@waterx/config` from `packages/ts`: a `prerelease` from any branch,
an official release from `main-v2` (or `main`), gated by the `RELEASE_PUBLISHERS` /
`PRERELEASE_PUBLISHERS` repo variables.

Content rules (`README.md` and `docs/FIELDS.md` are the reference):

- The schema is `schema/waterx-config.schema.json`; the TypeScript and Rust parsers, the Zod
  validator and `docs/FIELDS.md` are generated from it — edit the schema, never the generated
  files (`codegen.yml` fails a PR where they drift). `validate.yml` runs ajv on both instances,
  `scripts/check-consistency.mjs` (every symbol-keyed map ⊆ `symbols`; keyspace differences must
  be declared in `schema/coverage-exceptions.json`), `scripts/check-flip-state.mjs` (the
  removed-path ledger — a removed path cannot resurface) and both parsers' tests. Before pushing,
  run the two dependency-free checks: `node scripts/check-consistency.mjs && node
  scripts/check-flip-state.mjs`.
- `original_id` never changes across upgrades; an upgrade changes only `published_at` / `version`.
  Deploy forensics (publish digests, checkpoints, the tx log) go in `deploys/`, not in the served
  files.
- Which rules feed a symbol is declared per rule: `oracle_rules.pyth_lazer.lazer_feed_ids` and
  `oracle_rules.waterx.feeds`. A symbol in neither list is priced by no off-chain source; keep
  each list a superset of what the chain weights for that rule, or trades abort
  `EMissingPriceSource`. Venue composition lives in quote-center's BBO config, not here.
- Never write a parse result back to a config file — the parsers strip unknown fields;
  read-modify-write tools patch the original document and use the parser only to validate.
- Never read the files from `raw.githubusercontent.com` (GitHub answers 429); use the CDN URLs.

The request sets the scope: change the ids the task names, report anything else you notice as a
suggestion, and don't merge into a served branch or dispatch `publish.yml` yourself.
`.claude/settings.json` and `.codex/rules/publish.rules` make `gh pr merge`, `gh workflow run` and
a push to `main` / `staging` / `main-v2` / `staging-v2` prompt; Codex's rules see only leading
words, so its hook (`.codex/hooks.json`) blocks a publish that does not name its branch (`git
push` on `main-v2`, `HEAD:main-v2`) and asks for the plain form.
`.github/workflows/agent-harness.yml` runs `scripts/agent-hooks/test-agent-hooks.sh` and the
shared harness lint `scripts/agent-hooks/check-harness.sh` (vendored from `waterx-commons`; keep
its version line). Report only what a tool result from this session backs — the diff, the validate
run, the CDN response after a merge; say what is unverified.

Lessons live in `docs/knowledge-hub/`, one per file, `YYYY-MM-DD-<slug>.md` (format in its
`README.md`). Commit messages already carry tx digests and reasons; a lesson is for what the next
session would otherwise rediscover — add one when something cost real time, with why; update
rather than add a near-duplicate; delete a note proven wrong.

# waterx-config

On-chain deployment ids per WaterX network, served from `https://config.waterx.app/{network}.json`
by Cloudflare Pages wired to `main` (`_headers`: CORS and a 60 s client cache).

Both Claude Code (v2.1.281+) and Codex read this file. Do not add a CLAUDE.md anywhere in the repo: Claude Code ignores every AGENTS.md at or below a directory that has one.

**A push to `main` is a production
publish** — Pages deploys and purges the edge on merge, so a change to `mainnet.json` is a live
config change for the backend, SDK, frontend, keeper and quote-center at once.

Branches: feature branch → `staging` → `main`. `.github/workflows/guard-main-merges.yml` fails any
PR into `main` whose source is not `staging`, so open PRs against `staging`; `staging` is itself
served as the staging CDN alias (`staging.waterx-config.pages.dev`), so a staging merge is live
too. `main-v2` / `staging-v2` carry the consolidated `schema_version: 2` shape, with the schema,
generated parsers and deploy forensics (`schema`, `packages`, `deploys`) this lineage does not
have; a data change here usually needs a twin on the v2 pair, resolved to the v2 shape (the "Merge
branch 'main' into main-v2 — …, resolved to the v2 shape" commits are the pattern). `publish.yml`
(npm `@waterx/config`, dispatch-only) builds `packages/ts`, which exists only on the v2 pair.

Content rules (`README.md` is the schema reference):

- `original_id` never changes across upgrades; an upgrade changes only `published_at` / `version`.
- The legacy singular fields — `credit_registry`, `credit_type`, `vault`, `assets`, `queue`,
  `executors`, and the `usd` package block — stay as mirrors of the `USD` entries in
  `credit_registries` / `vaults` / `queues` / `usd_credit`. v1 consumers still read them, and a
  release that dropped them had to be repaired. An authorization list such as `executors` is taken
  from `queues.USD`, never from the singular field.
- `waterx_rule.feeds[].sources` and `method` must match the on-chain `set_perp_feed` config
  field-for-field or the rule aborts validation; `kind` is off-chain only. Testnet-only packages
  (`mock_*`, `testnet_faucet`, `supra_rule`) never appear in `mainnet.json`.
- Never read the files from `raw.githubusercontent.com` (GitHub answers 429); use the CDN URLs.
  Run `jq . mainnet.json testnet.json` before pushing — this lineage has no CI schema check.

The request sets the scope: change the ids the task names, report anything else you notice as a
suggestion, and don't merge into `staging` or `main` yourself. `.claude/settings.json` and
`.codex/rules/publish.rules` make `gh pr merge`, `gh workflow run` and a push to a served branch
prompt (the same plain forms in both). The hook splits the line with the shared quote-aware
segmenter (`scripts/agent-hooks/lib/`), so global options (`git -c …`, `gh -R …`), wrappers and
newlines are seen, comments are not commands, and a line it cannot parse or whose text names
git or gh inside another command (`ssh host 'git push …'`) asks. Codex's rules see only leading words, so its hook (`.codex/hooks.json`)
blocks a publish that does not name its branch (`git push` on `main`, `HEAD:main`) and asks for
the plain form.
`.github/workflows/agent-harness.yml` runs `scripts/agent-hooks/test-agent-hooks.sh` and the
shared harness lint `scripts/agent-hooks/check-harness.sh` (vendored from `waterx-commons`; keep
its version line). Report only what a tool result from this session backs — the diff, the `jq`
run, the CDN response after a merge; say what is unverified.

Lessons live in `docs/knowledge-hub/`, one per file, `YYYY-MM-DD-<slug>.md` (format in its
`README.md`). Commit messages already carry tx digests and reasons; a lesson is for what the next
session would otherwise rediscover — add one when something cost real time, with why; update
rather than add a near-duplicate; delete a note proven wrong.

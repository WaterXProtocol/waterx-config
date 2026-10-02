#!/usr/bin/env bash
# Tests for ask-before-publish.sh (Claude and --codex modes) with sample hook JSON on stdin and throwaway
# git checkouts for the bare-push case. Needs jq and git; never pushes.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
ask="$here/ask-before-publish.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
ok() { pass=$((pass + 1)); echo "ok   - $*"; }
fail() { echo "FAIL - $*" >&2; exit 1; }

hook_json() { jq -nc --arg c "$1" --arg d "${2:-/x}" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }

expect_ask() {
  out=$(hook_json "$1" "${2:-/x}" | "$ask") || fail "hook exited non-zero on: $1"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask" and .hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.permissionDecisionReason | test("publishes"))' >/dev/null \
    || fail "expected permissionDecision ask for: $1 (got: $out)"
  ok "asks: $1${2:+  (cwd on $(git -C "$2" rev-parse --abbrev-ref HEAD))}"
}
expect_codex_pass() {
  out=$(hook_json "$1" "${2:-/x}" | "$ask" --codex 2>&1) || fail "codex mode blocked: $1 ($out)"
  [ -z "$out" ] || fail "codex mode: expected no output for: $1 (got: $out)"
  ok "codex passes to its prompt rule: $1"
}
expect_codex_block() {
  set +e; err=$(hook_json "$1" "${2:-/x}" | "$ask" --codex 2>&1 >/dev/null); rc=$?; set -e
  [ "$rc" -eq 2 ] || fail "codex mode: expected exit 2 for: $1 (got $rc)"
  case "$err" in *"publishes"*"names its target"*) ;; *) fail "codex mode: reason missing for: $1 ($err)" ;; esac
  ok "codex blocks: $1"
}
expect_silent() {
  out=$(hook_json "$1" "${2:-/x}" | "$ask") || fail "hook exited non-zero on: $1"
  [ -z "$out" ] || fail "expected no output for: $1 (got: $out)"
  ok "silent: $1${2:+  (cwd on $(git -C "$2" rev-parse --abbrev-ref HEAD))}"
}

expect_ask 'gh pr merge 96 --squash'
expect_ask 'gh -R WaterXProtocol/waterx-config pr merge 96'
expect_ask 'gh workflow run publish.yml -f releaseType=patch'
expect_ask 'gh api -X PUT repos/WaterXProtocol/waterx-config/pulls/96/merge'
expect_ask 'git push origin main'
expect_ask 'git push origin HEAD:staging'
expect_ask 'git push -u origin main-v2'
expect_ask 'git push origin staging-v2'
expect_ask 'git push --force-with-lease origin chore/x'
expect_ask 'git push -f origin chore/x'
expect_ask 'git push origin --delete chore/x'
expect_ask 'jq . mainnet.json && git commit -am "ids" && git push origin main'
expect_ask 'git push origin chore/x && git push origin main'
expect_ask 'git push origin +chore/x'
expect_ask 'git push origin refs/heads/staging'
expect_ask 'git push --all origin'
expect_ask 'bash -c "git push origin main"'

expect_silent 'git push -u origin chore/testnet-waterx-feeds'
expect_silent 'git push origin HEAD:refs/heads/chore/x'
expect_silent 'git fetch origin && git status'
expect_silent 'git pull --rebase origin staging'
expect_silent 'git log --oneline origin/main..origin/staging'
expect_silent 'gh pr create --base staging --title x --body y'
expect_silent 'gh pr view 96 --json mergeable'
expect_silent 'gh workflow list'
expect_silent 'gh api repos/WaterXProtocol/waterx-config/pulls/96'
expect_silent 'curl -s https://config.waterx.app/mainnet.json | jq .network'
expect_silent 'grep -n "git push origin main" README.md'
expect_silent 'git commit -m "docs: never git push origin main by hand"'
expect_silent 'gh pr create --base staging --title x --body "merge with gh pr merge after review"'

expect_codex_pass 'git push -u origin chore/x'
expect_codex_pass 'git push origin main'
expect_codex_pass 'jq . mainnet.json && git push -u origin staging-v2'
expect_codex_pass 'gh pr merge 96 --squash'
expect_codex_block 'git push origin HEAD:main'
expect_codex_block 'gh -R WaterXProtocol/waterx-config pr merge 96'
expect_codex_block 'git push origin main 2>&1 | tail -1'

# Bare `git push`: decided by the branch the checkout in cwd is on.
repo="$tmp/repo"
git init -q "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$repo" checkout -q -b main 2>/dev/null || git -C "$repo" checkout -q main
expect_ask 'git push' "$repo"
git -C "$repo" checkout -q -b staging-v2
expect_ask 'git push -u origin HEAD' "$repo"
git -C "$repo" checkout -q -b chore/feature
expect_silent 'git push' "$repo"
expect_silent 'git push -u origin HEAD' "$repo"
git -C "$repo" checkout -q main
expect_ask "git -C $repo push"
expect_codex_block 'git push' "$repo"

out=$(printf '{}' | "$ask") && [ -z "$out" ] || fail "hook misbehaved on {}"
out=$(printf '' | "$ask") && [ -z "$out" ] || fail "hook misbehaved on empty stdin"
out=$(printf 'not json' | "$ask" --codex 2>&1) && [ -z "$out" ] || fail "codex mode misbehaved on malformed input"
out=$(jq -nc '{tool_name:"Bash",tool_input:{command:["bash","-lc","git push origin main"]}}' | "$ask") \
  && printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null || fail "array-shaped command not read"
ok "silent on empty or malformed input"

echo "agent hooks: $pass/$pass passed"

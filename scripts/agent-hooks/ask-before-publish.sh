#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): publishing needs a human, in both tools.
#
#   ask-before-publish.sh            Claude Code (.claude/settings.json)
#   ask-before-publish.sh --codex    Codex (.codex/hooks.json)
#
# A push to `main` deploys config.waterx.app; `staging` serves the staging CDN
# alias; `main-v2` / `staging-v2` are the v2 lineage; `publish.yml` publishes
# the npm package; `gh pr merge` does any of those. Reads the hook JSON on stdin
# and looks at every simple command in `tool_input.command` (split on `&&`,
# `||`, `;`, `|`, `&`) for:
#   - `gh pr merge`, `gh workflow run`, or a `gh api` call that merges a PR;
#   - `git push` naming a served branch (also `HEAD:main`, `refs/heads/main`),
#     forcing (`--force*`, `-f`, a `+` refspec), deleting (`--delete`, `-d`, a
#     `:branch` refspec), `--all` / `--mirror`, or naming no branch while the
#     checkout (`cwd`, or `git -C <dir>`) is on a served branch.
# Everything else (fetch, pull, status, a push of a feature branch) passes.
#
# Claude Code: answers permissionDecision "ask" (exit 0), so the user confirms.
# Codex: its hooks cannot ask ("ask" fails the hook and the call proceeds), so
# the prompt comes from .codex/rules/publish.rules, which only sees a command's
# leading words. This mode stays silent when every publishing command starts
# with one of those prefixes and the line has no redirection or substitution
# (Codex then prompts), and blocks with exit 2 otherwise, telling the agent to
# name the branch in the plain form.
set -u

mode=claude
[ "${1:-}" = "--codex" ] && mode=codex
here=$(cd "$(dirname "$0")" && pwd)
input=$(cat)

if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command? // empty | if type == "array" then join(" ") else . end' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd? // empty' 2>/dev/null)
else
  # No jq: scrape the string values (sed -E — BSD sed has no \| in basic regexps) and unescape.
  cmd=$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1 |
    sed 's/\\"/"/g; s/\\\\/\\/g')
  cwd=$(printf '%s' "$input" | sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)
fi
[ -n "${cmd:-}" ] || exit 0

served='(main|staging|main-v2|staging-v2)'
start='(^|[^[:alnum:]_.-])'
end="([[:space:]\"');&|]|\$)"
# Global flags before the verb, with or without a separate value: `gh -R org/repo pr merge`, `git -C dir push`.
flags='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'

# Is this one simple command a publish? Prints what it matched, or nothing.
publish_in() {
  local seg=$1 start=$start push dir arg branch nonflag=0 named=""
  # A git or gh command is judged by its own verb only, so a commit message or PR
  # body that mentions `git push origin main` is not a push.
  case "${seg%% *}" in git|gh) start='^' ;; esac
  if printf '%s' "$seg" | grep -Eq "${start}gh${flags}[[:space:]]+pr[[:space:]]+merge${end}"; then echo "gh pr merge"; return; fi
  if printf '%s' "$seg" | grep -Eq "${start}gh${flags}[[:space:]]+workflow[[:space:]]+run${end}"; then echo "gh workflow run"; return; fi
  if printf '%s' "$seg" | grep -Eq "${start}gh${flags}[[:space:]]+api[[:space:]].*/pulls/[^[:space:]]*/merge"; then echo "gh api …/pulls/<n>/merge"; return; fi
  printf '%s' "$seg" | grep -Eq "${start}git${flags}[[:space:]]+push${end}" || return
  push=$(printf '%s' "$seg" | grep -Eo "${start}git${flags}[[:space:]]+push.*" | head -1 | sed 's/^[^[:alnum:]]*//')
  dir=$(printf '%s' "$push" | sed -nE 's/^git.*[[:space:]]-C[[:space:]]+([^[:space:]]+).*[[:space:]]push.*/\1/p')
  # Word-split the arguments without letting a `*` in them glob.
  set -f
  # shellcheck disable=SC2086
  set -- $(printf '%s' "${push#*push}" | tr -d "\"'")
  set +f
  for arg in "$@"; do
    case "$arg" in
      --force*|-f|--delete|-d|--all|--mirror) echo "git push $arg"; return ;;
      -*) ;;
      *)
        nonflag=$((nonflag + 1))
        [ $nonflag -eq 1 ] && continue # the remote
        case "$arg" in +*|:*) echo "git push $arg (force / delete)"; return ;; esac
        branch=${arg##*:}; branch=${branch#refs/heads/}
        if printf '%s' "$branch" | grep -Eq "^${served}$"; then echo "git push to $branch"; return; fi
        [ "$branch" = HEAD ] || named=1
        ;;
    esac
  done
  [ -n "$named" ] && return
  # No branch named (bare `git push`, `git push origin`, `git push -u origin HEAD`):
  # the branch the checkout is on decides.
  case "$dir" in "") dir=$cwd ;; /*) ;; *) dir="$cwd/$dir" ;; esac
  [ -n "$dir" ] && [ -d "$dir" ] || return
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if printf '%s' "$branch" | grep -Eq "^${served}$"; then echo "git push while on $branch"; fi
}

# Leading words of the Codex prompt rules, one per line ("git push origin main").
codex_prefixes() {
  sed -n 's/.*pattern[[:space:]]*=[[:space:]]*\[\([^]]*\)\].*/\1/p' "$here"/../../.codex/rules/*.rules 2>/dev/null |
    sed 's/"//g; s/,[[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

matched=""
uncovered=""
while IFS= read -r seg; do
  seg=$(printf '%s' "$seg" | sed 's/^[[:space:]({!]*//; s/[[:space:]]*$//')
  [ -n "$seg" ] || continue
  # Commands that only print or search text cannot publish.
  case "${seg%% *}" in grep|egrep|rg|echo|printf|cat|head|tail|less|sed|awk|jq|wc) continue ;; esac
  hit=$(publish_in "$seg")
  [ -n "$hit" ] || continue
  [ -n "$matched" ] || matched=$hit
  if [ "$mode" = codex ]; then
    covered=""
    while IFS= read -r pre; do
      [ -n "$pre" ] || continue
      case "$seg" in "$pre"|"$pre "*) covered=1; break ;; esac
    done <<EOF
$(codex_prefixes)
EOF
    [ -n "$covered" ] || { [ -n "$uncovered" ] || uncovered=$seg; }
  fi
done <<EOF
$(printf '%s\n' "$cmd" | awk '{ gsub(/\|\||&&|[;|&]/, "\n"); print }')
EOF
[ -n "$matched" ] || exit 0

reason="'$matched' publishes: a push to main deploys config.waterx.app, staging serves the staging CDN alias, main-v2 / staging-v2 are the v2 lineage, and publish.yml publishes @waterx/config. Only proceed with an explicit same-turn go-ahead from the user; otherwise open a PR against staging and stop."

if [ "$mode" = codex ]; then
  if [ -z "$uncovered" ] && ! printf '%s' "$cmd" | grep -q '[<>`]\|\$('; then
    exit 0 # .codex/rules/publish.rules prompts for it
  fi
  printf '%s\n' "$reason" "Codex can only ask the user when the command is plain and names its target in the leading words (for example 'git push origin staging' or 'gh pr merge 12'), with no redirection, substitution or wrapper; '${uncovered:-$matched}' is not, so it was blocked. Re-run it in that form, or hand it to the user." >&2
  exit 2
fi

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
else
  esc=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$esc"
fi
exit 0

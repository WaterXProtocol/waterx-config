#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): publishing needs a human, in both tools.
#
#   ask-before-publish.sh            Claude Code (.claude/settings.json)
#   ask-before-publish.sh --codex    Codex (.codex/hooks.json)
#
# A push to `main` deploys config.waterx.app; `staging` serves the staging CDN
# alias; `main-v2` / `staging-v2` are the v2 lineage; `publish.yml` publishes
# the npm package; `gh pr merge` does any of those. Splits `tool_input.command`
# into simple commands with the shared quote-aware segmenter
# (lib/shell-segments.sh, vendored from waterx-commons): separators and newlines
# outside quotes, comments dropped, `bash -c` / `eval` / `env` / `command` /
# `time` unwrapped, substitutions parsed as their own commands, and the global
# options of git and gh moved aside (`git -c k=v push`, `gh -R org/repo pr
# merge`). Each command is matched on its own verb, so quoted prose (a commit
# message, a PR body that mentions `git push origin main`) is never a command:
#   - `gh pr merge`, `gh workflow run`, or a `gh api` call that merges a PR;
#   - `git push` naming a served branch (also `HEAD:main`, `refs/heads/main`),
#     forcing (`--force*`, `-f`, a `+` refspec), deleting (`--delete`, `-d`, a
#     `:branch` refspec), `--all` / `--mirror`, or naming no branch while the
#     checkout (`cwd`, or `git -C <dir>`) is on a served branch.
# Everything else (fetch, pull, status, a push of a feature branch) passes.
# FAIL CLOSED: a part the segmenter cannot parse that names git or gh together
# with push / merge / workflow asks.
#
# Claude Code: answers permissionDecision "ask" (exit 0), so the user confirms.
# Codex: its hooks cannot ask ("ask" fails the hook and the call proceeds), so
# the prompt comes from .codex/rules/publish.rules, which only sees a command's
# leading words. This mode stays silent when every publishing command is typed
# plainly (no wrapper, redirection or substitution anywhere in the line) and
# starts with one of those prefixes, so Codex prompts; otherwise it blocks with
# exit 2 and tells the agent to name the branch in the plain form.
set -u

mode=claude
[ "${1:-}" = "--codex" ] && mode=codex
here=$(cd "$(dirname "$0")" && pwd)
input=$(cat)

# shellcheck source=lib/shell-segments.sh
. "$here/lib/shell-segments.sh"
tab=$(printf '\t')
cmd=$(printf '%s' "$input" | shseg_json_get tool_input.command); rc=$?
# Not JSON: judge the raw text as one unparseable part (asks only if it names a publish).
[ "$rc" -eq 2 ] && cmd=$input
cwd=$(printf '%s' "$input" | shseg_json_get cwd 2>/dev/null)
[ -n "${cmd:-}" ] || exit 0

served='(main|staging|main-v2|staging-v2)'

# Is this one parsed command a publish? $1 tool, $2 its global options, then its
# arguments. Prints what it matched, or nothing.
publish_in() {
  local tool=$1 globals=$2 arg branch dir="" nonflag=0 named=""
  shift 2
  if [ "$tool" = gh ]; then
    case "${1:-} ${2:-}" in
      "pr merge") echo "gh pr merge"; return ;;
      "workflow run") echo "gh workflow run"; return ;;
    esac
    if [ "${1:-}" = api ]; then
      for arg in "$@"; do
        case "$arg" in */pulls/*/merge | */pulls/*/merge\?*) echo "gh api …/pulls/<n>/merge"; return ;; esac
      done
    fi
    return
  fi
  [ "$tool" = git ] && [ "${1:-}" = push ] || return
  shift
  for arg in "$@"; do
    case "$arg" in
      --force* | -f | --delete | -d | --all | --mirror) echo "git push $arg"; return ;;
      -*) ;;
      *)
        nonflag=$((nonflag + 1))
        [ $nonflag -eq 1 ] && continue # the remote
        case "$arg" in +* | :*) echo "git push $arg (force / delete)"; return ;; esac
        branch=${arg##*:}; branch=${branch#refs/heads/}
        if printf '%s' "$branch" | grep -Eq "^${served}$"; then echo "git push to $branch"; return; fi
        [ "$branch" = HEAD ] || named=1
        ;;
    esac
  done
  [ -n "$named" ] && return
  # No branch named (bare `git push`, `git push origin`, `git push -u origin HEAD`):
  # the branch the checkout is on decides. `git -C <dir>` sits in the globals.
  case " $globals " in *" -C "*) dir=${globals#*-C }; dir=${dir%% *} ;; esac
  case "$dir" in "") dir=$cwd ;; /*) ;; *) dir="$cwd/$dir" ;; esac
  [ -n "$dir" ] && [ -d "$dir" ] || return
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if printf '%s' "$branch" | grep -Eq "^${served}$"; then echo "git push while on $branch"; fi
}

# Leading words of the Codex prompt rules, one per line ("git push origin main").
prefixes=$(sed -n 's/^prefix_rule(.*pattern[[:space:]]*=[[:space:]]*\[\([^]]*\)\].*/\1/p' "$here"/../../.codex/rules/*.rules 2>/dev/null |
  sed 's/"//g; s/,[[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')
covered_by_rule() {
  local pre
  while IFS= read -r pre; do
    [ -n "$pre" ] || continue
    case "$1" in "$pre" | "$pre "*) return 0 ;; esac
  done <<EOF
$prefixes
EOF
  return 1
}

matched=""
uncovered=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  # Split on TAB by hand: `read -a` would collapse the empty globals field.
  F=()
  rest=$line
  while :; do
    case "$rest" in *"$tab"*) F+=("${rest%%"$tab"*}"); rest=${rest#*"$tab"} ;; *) F+=("$rest"); break ;; esac
  done
  if [ "${F[0]}" = UNPARSEABLE ]; then
    raw=${F[2]:-}
    if { shseg_names_tool git "$raw" || shseg_names_tool gh "$raw"; } &&
      printf '%s\n' "$raw" | grep -Eq '(^|[^[:alnum:]_-])(push|merge|workflow)([^[:alnum:]_-]|$)'; then
      [ -n "$matched" ] || matched="a publish the hook cannot parse (${F[1]})"
      [ -n "$uncovered" ] || uncovered=$raw
    fi
    continue
  fi
  hit=$(publish_in "${F[1]}" "${F[2]}" ${F[4]+"${F[@]:4}"})
  [ -n "$hit" ] || continue
  [ -n "$matched" ] || matched=$hit
  if [ "${F[0]}" != plain ] || ! covered_by_rule "${F[3]}"; then
    [ -n "$uncovered" ] || uncovered=${F[3]}
  fi
done <<EOF
$(shseg_segments --long "$cmd")
EOF
[ -n "$matched" ] || exit 0

reason="'$matched' publishes: a push to main deploys config.waterx.app, staging serves the staging CDN alias, main-v2 / staging-v2 are the v2 lineage, and publish.yml publishes @waterx/config. Only proceed with an explicit same-turn go-ahead from the user; otherwise open a PR against staging and stop."

if [ "$mode" = codex ]; then
  [ -z "$uncovered" ] && exit 0 # .codex/rules/publish.rules prompts for it
  printf '%s\n' "$reason" "Codex can only ask the user when the command is plain and names its target in the leading words (for example 'git push origin staging' or 'gh pr merge 12'), with no global option before the verb, redirection, substitution or wrapper; '$uncovered' is not, so it was blocked. Re-run it in that form, or hand it to the user." >&2
  exit 2
fi

esc=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$esc"
exit 0

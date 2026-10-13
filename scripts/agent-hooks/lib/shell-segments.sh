#!/bin/sh
# waterx-commons/harness/hooks/lib/shell-segments.sh v1.2.3
#
# A quote-aware shell command segmenter for agent hooks (STANDARD.md rule 12). Repos vendor this
# file unchanged as scripts/agent-hooks/lib/shell-segments.sh; keep the version line above intact.
#
# It turns the command string of a Bash tool call into the simple commands it would run, one per
# line, so a hook classifies parsed commands instead of grepping text:
#   - splits on ; && || | |& & ( ) and newlines OUTSIDE quotes; drops # comments;
#   - treats here-document bodies as data, except when a shell reads them (bash <<EOF);
#   - parses $( ), backticks, <( ) and >( ) (also inside double quotes and unquoted here-documents)
#     as separate commands, and leaves a placeholder ("$(...)", "<(...)") in the outer word, so text
#     inside a substitution never counts as an argument of the outer command;
#   - unwraps bash/sh/zsh/dash/ksh/fish -c, eval, env (incl. -S), command, builtin, exec, nohup,
#     time, sudo, doas, su/runuser/sg -c, nice, ionice, timeout/gtimeout, stdbuf, xargs, parallel,
#     watch, flock, chroot, setsid, script (-c, and BSD's FILE COMMAND), taskset, chrt, caffeinate,
#     unbuffer, nsenter, unshare, pkexec, systemd-run, firejail, strace, direnv exec, leading
#     NAME=value assignments, reserved words (if/then/do/!/{ ...), and a path on the tool
#     (/usr/local/bin/kubectl -> kubectl). A wrapper reads only ITS OWN options, up to its own
#     boundary (its positionals, "--" or the first non-option), the way getopt reads them: a value
#     attached or in the next word, clusters, --long=value and --long value (runuser -ubob --,
#     script -c'cmd', timeout -s9 5; v1.2.3); the command after it keeps its options (flock /tmp/l
#     git -c k=v commit -> git commit; waterx-fe#1149 rounds 4-5);
#   - emits the command operand of find -exec/-execdir/-ok/-okdir (`\;` and `{} +`) as its own
#     command, and find itself with that operand removed;
#   - moves the global options of git, gh, kubectl, helm, argocd, gcloud, terraform, tofu and make
#     out of the argument list (kubectl -n ns --context c delete pod x -> kubectl delete pod x).
#
# Output, one line per simple command (fields separated by a TAB; a newline, TAB or CR inside a
# value is printed as \n, \t, \r; an empty argument is an empty field, which `read` with IFS=TAB
# collapses, so split with awk -F'\t' when an argument's position matters):
#   default   <tool> <arg>...                          normalised: global options removed
#   --long    <origin> <tool> <globals> <words> <arg>...
#             origin  "plain" when Codex prefix rules can see the command as typed: top level, no
#                     wrapper, assignment, path on the tool, redirection, substitution, subshell or
#                     here-document anywhere in the line; "wrapped" otherwise
#             globals the removed global options, space-joined ("-" when none, so the field never
#                     collapses under IFS=TAB)
#             words   the command's words as typed (after quote removal), space-joined
#   UNPARSEABLE <reason> <raw text>                    (both modes) a part it could not parse with
#             confidence: unterminated quote or substitution, a command word computed at run time
#             ($TOOL, "$(which kubectl)"), an unknown option before a known tool's subcommand, or
#             nesting deeper than 6 levels. The raw text lets a hook check whether it names the tool.
#             With --guard "TOOL...", the fail-closed backstop for ask hooks (v1.2.1): a simple
#             command whose RAW TEXT names a guarded tool as a word ANYWHERE (inside single or
#             double quotes, $( ), backticks, a here-document body, a here-string or a redirection
#             target too) comes back UNPARSEABLE, with that text, unless it parsed as a guarded tool
#             itself (the hook classifies it), as a command known not to run its arguments (echo,
#             grep, cat, ... the INERT list), or as a wrapper whose command this file unwrapped
#             (bash -c, sudo, find -exec, ...; the unwrapped command is checked on its own line).
#             So `ssh host 'kubectl delete pod x'`, `gh pr create --body '... kubectl ...'` and
#             `git commit -m '... kubectl ...'` all come back UNPARSEABLE: a spurious prompt is
#             acceptable, a silent write is not. Two cases look at the WHOLE input instead of the
#             command's own text: a command word computed at run time (K=kubectl; $K delete) and a
#             shell, interpreter or ssh that may read its commands from stdin (echo '...' | sh,
#             python3 <<EOF). Without --guard (block hooks) nothing of this is printed.
#
# How hooks use it (STANDARD.md rule 12):
#   ask hooks   FAIL CLOSED: pass --guard with the guarded tools; ask when a parsed line matches,
#               AND when an UNPARSEABLE line's raw text names the tool; match --dry-run style
#               exemptions against that line's own arguments.
#   block hooks FAIL OPEN: act only on a parsed line in command position; ignore UNPARSEABLE.
#
# Use as a library (POSIX sh, bash 3.2, dash; needs only awk — SHSEG_AWK_BIN picks another one):
#   . "$(dirname "$0")/lib/shell-segments.sh"
#   cmd=$(printf '%s' "$input" | shseg_json_get tool_input.command)   # 0 found, 1 absent, 2 bad JSON
#   shseg_segments "$cmd" | while IFS="$(printf '\t')" read -r tool a1 a2 rest; do ...; done
#   shseg_segments --long --guard "kubectl argocd" "$cmd"            # ask hooks: with the backstop
#   shseg_prompt_prefixes .codex/rules/*.rules    # Codex prompt-rule prefixes, one per line (v1.2.2)
# or as a command:
#   shell-segments.sh [--long] [--guard "TOOL..."] [--] [COMMAND]
#                                                segment COMMAND, or stdin when absent
#   shell-segments.sh --json-get PATH            print the JSON value at PATH (stdin); arrays of
#                                                strings come back shell-quoted and space-joined
#   shell-segments.sh --self-test | --version
# A JSON value is decoded fully (\n, \", \uXXXX), so a multi-line command splits on its newlines;
# scraping it with sed leaves "\n" in the text and hides every command after the first line.

SHSEG_VERSION=1.2.3

SHSEG_AWK='
function esc(x) { gsub(/\n/, "\\n", x); gsub(/\t/, "\\t", x); gsub(/\r/, "\\r", x); return x }
function unparseable(reason, raw) { print "UNPARSEABLE\t" reason "\t" esc(raw) }
function enqueue(script, depth) {
  if (depth > MAXDEPTH) { unparseable("nesting deeper than " MAXDEPTH " levels", script); return }
  NQ++; Q[NQ] = script; QD[NQ] = depth
}
function skip_bt(s, k,    n, c) {
  n = length(s)
  while (k <= n) { c = substr(s, k, 1); if (c == "\\") { k += 2; continue } if (c == "`") return k; k++ }
  return 0
}
function unbt(x,    out, k, n, c, c2) {
  out = ""; n = length(x)
  for (k = 1; k <= n; k++) {
    c = substr(x, k, 1); c2 = substr(x, k + 1, 1)
    if (c == "\\" && index("`$\\", c2) && c2 != "") { out = out c2; k++ } else out = out c
  }
  return out
}
function skip_dq(s, k,    n, c, j) {
  n = length(s)
  while (k <= n) {
    c = substr(s, k, 1)
    if (c == "\\") { k += 2; continue }
    if (c == "\"") return k
    if (c == "$" && substr(s, k + 1, 1) == "(") { j = match_paren(s, k + 2); if (!j) return 0; k = j + 1; continue }
    if (c == "$" && substr(s, k + 1, 1) == "{") { j = match_brace(s, k + 2); if (!j) return 0; k = j + 1; continue }
    if (c == "`") { j = skip_bt(s, k + 1); if (!j) return 0; k = j + 1; continue }
    k++
  }
  return 0
}
function match_paren(s, k,    n, c, d, j) {
  n = length(s); d = 1
  while (k <= n) {
    c = substr(s, k, 1)
    if (c == "\\") { k += 2; continue }
    if (c == SQ) { j = index(substr(s, k + 1), SQ); if (!j) return 0; k += j + 1; continue }
    if (c == "\"") { j = skip_dq(s, k + 1); if (!j) return 0; k = j + 1; continue }
    if (c == "`") { j = skip_bt(s, k + 1); if (!j) return 0; k = j + 1; continue }
    if (c == "#" && (k == 1 || index(" \t\n;(|&", substr(s, k - 1, 1)))) {
      while (k <= n && substr(s, k, 1) != "\n") k++
      continue
    }
    if (c == "(") d++
    else if (c == ")") { d--; if (d == 0) return k }
    k++
  }
  return 0
}
function match_brace(s, k,    n, c, d, j) {
  n = length(s); d = 1
  while (k <= n) {
    c = substr(s, k, 1)
    if (c == "\\") { k += 2; continue }
    if (c == SQ) { j = index(substr(s, k + 1), SQ); if (!j) return 0; k += j + 1; continue }
    if (c == "\"") { j = skip_dq(s, k + 1); if (!j) return 0; k = j + 1; continue }
    if (c == "{") d++
    else if (c == "}") { d--; if (d == 0) return k }
    k++
  }
  return 0
}
# Substitutions inside an unquoted here-document body run when the shell reads the body.
function scan_body(b,    k, n, c, j) {
  n = length(b); k = 1
  while (k <= n) {
    c = substr(b, k, 1)
    if (c == "\\") { k += 2; continue }
    if (c == "$" && substr(b, k + 1, 2) == "((") { j = match_paren(b, k + 2); if (!j) return; k = j + 1; continue }
    if (c == "$" && substr(b, k + 1, 1) == "(") { j = match_paren(b, k + 2); if (!j) return; enqueue(substr(b, k + 2, j - k - 2), CUR_DEPTH + 1); k = j + 1; continue }
    if (c == "`") { j = skip_bt(b, k + 1); if (!j) return; enqueue(unbt(substr(b, k + 1, j - k - 1)), CUR_DEPTH + 1); k = j + 1; continue }
    k++
  }
}
function read_dq(s, k,    n, c, c2, j, v) {
  n = length(s); v = ""; DQDYN = 0
  while (k <= n) {
    c = substr(s, k, 1)
    if (c == "\"") { DQV = v; return k }
    if (c == "\\") {
      c2 = substr(s, k + 1, 1)
      if (c2 == "\n") { k += 2; continue }
      if (c2 != "" && index("$`\"\\", c2)) { v = v c2; k += 2; continue }
      v = v c; k++; continue
    }
    if (c == "$" && substr(s, k + 1, 2) == "((") { j = match_paren(s, k + 2); if (!j) return 0; v = v substr(s, k, j - k + 1); DQDYN = 1; k = j + 1; continue }
    if (c == "$" && substr(s, k + 1, 1) == "(") {
      j = match_paren(s, k + 2); if (!j) return 0
      enqueue(substr(s, k + 2, j - k - 2), CUR_DEPTH + 1); COMPLEX = 1
      v = v "$(...)"; DQDYN = 1; k = j + 1; continue
    }
    if (c == "$" && substr(s, k + 1, 1) == "{") { j = match_brace(s, k + 2); if (!j) return 0; v = v substr(s, k, j - k + 1); DQDYN = 1; k = j + 1; continue }
    if (c == "`") {
      j = skip_bt(s, k + 1); if (!j) return 0
      enqueue(unbt(substr(s, k + 1, j - k - 1)), CUR_DEPTH + 1); COMPLEX = 1
      v = v "$(...)"; DQDYN = 1; k = j + 1; continue
    }
    if (c == "$") DQDYN = 1
    v = v c; k++
  }
  return 0
}
function endword() {
  if (!INW) return
  NT++; T_type[NT] = "W"; T_val[NT] = W; T_raw[NT] = WR; T_dyn[NT] = WDYN
  W = ""; WR = ""; INW = 0; WDYN = 0
}
function addtok(ty, v) { NT++; T_type[NT] = ty; T_val[NT] = v; T_raw[NT] = v; T_dyn[NT] = 0 }
function read_heredocs(s, i,    h, n, j, line, cmp, body, nexti) {
  n = length(s)
  for (h = 1; h <= NH; h++) {
    body = ""
    while (i <= n) {
      j = index(substr(s, i), "\n")
      if (j) { line = substr(s, i, j - 1); nexti = i + j } else { line = substr(s, i); nexti = n + 1 }
      i = nexti
      cmp = line; if (H_strip[h]) sub(/^\t+/, "", cmp)
      if (cmp == H_delim[h]) break
      body = body line "\n"
    }
    T_val[H_tok[h]] = body
    if (!H_q[h]) scan_body(body)
  }
  NH = 0
  return i
}
# Lexes s into T_*[1..NT]. Returns "" or the reason it could not.
function lex(s,    n, i, c, c2, j, k, op, d, dq, dch) {
  NT = 0; NH = 0; COMPLEX = 0; W = ""; WR = ""; INW = 0; WDYN = 0
  n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1); c2 = substr(s, i + 1, 1)
    if (c == "\\") {
      if (c2 == "\n") { i += 2; continue }
      W = W c2; WR = WR c c2; INW = 1; i += 2; continue
    }
    if (c == " " || c == "\t" || c == "\r") { endword(); i++; continue }
    if (c == "\n") { endword(); addtok("OP", "NL"); i++; if (NH) i = read_heredocs(s, i); continue }
    if (c == "#" && !INW) { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
    if (c == SQ) {
      j = index(substr(s, i + 1), SQ); if (!j) return "unterminated single quote"
      W = W substr(s, i + 1, j - 1); WR = WR substr(s, i, j + 1); INW = 1; i += j + 1; continue
    }
    if (c == "$" && c2 == SQ) {
      k = i + 2; d = ""
      while (k <= n && substr(s, k, 1) != SQ) {
        dch = substr(s, k, 1)
        if (dch == "\\") {
          dch = substr(s, k + 1, 1); k += 2
          if (dch == "n") d = d "\n"; else if (dch == "t") d = d "\t"; else if (dch == "r") d = d "\r"; else d = d dch
          continue
        }
        d = d dch; k++
      }
      if (k > n) return "unterminated $\047 quote"
      W = W d; WR = WR substr(s, i, k - i + 1); INW = 1; i = k + 1; continue
    }
    if (c == "\"") {
      j = read_dq(s, i + 1); if (!j) return "unterminated double quote or substitution inside one"
      W = W DQV; WR = WR substr(s, i, j - i + 1); INW = 1; if (DQDYN) WDYN = 1; i = j + 1; continue
    }
    if (c == "$" && substr(s, i + 1, 2) == "((") {
      j = match_paren(s, i + 2); if (!j) return "unterminated $(("
      W = W substr(s, i, j - i + 1); WR = WR substr(s, i, j - i + 1); INW = 1; WDYN = 1; i = j + 1; continue
    }
    if (c == "$" && c2 == "(") {
      j = match_paren(s, i + 2); if (!j) return "unterminated $("
      enqueue(substr(s, i + 2, j - i - 2), CUR_DEPTH + 1); COMPLEX = 1
      W = W "$(...)"; WR = WR substr(s, i, j - i + 1); INW = 1; WDYN = 1; i = j + 1; continue
    }
    if (c == "$" && c2 == "{") {
      j = match_brace(s, i + 2); if (!j) return "unterminated ${"
      W = W substr(s, i, j - i + 1); WR = WR substr(s, i, j - i + 1); INW = 1; WDYN = 1; i = j + 1; continue
    }
    if (c == "$") { W = W c; WR = WR c; INW = 1; WDYN = 1; i++; continue }
    if (c == "`") {
      j = skip_bt(s, i + 1); if (!j) return "unterminated backtick"
      enqueue(unbt(substr(s, i + 1, j - i - 1)), CUR_DEPTH + 1); COMPLEX = 1
      W = W "$(...)"; WR = WR substr(s, i, j - i + 1); INW = 1; WDYN = 1; i = j + 1; continue
    }
    if ((c == "<" || c == ">") && c2 == "(") {
      j = match_paren(s, i + 2); if (!j) return "unterminated process substitution"
      enqueue(substr(s, i + 2, j - i - 2), CUR_DEPTH + 1); COMPLEX = 1
      W = W c "(...)"; WR = WR substr(s, i, j - i + 1); INW = 1; WDYN = 1; i = j + 1; continue
    }
    if (c == "&") {
      endword()
      if (c2 == "&") { addtok("OP", "&&"); i += 2; continue }
      if (c2 == ">") { COMPLEX = 1; addtok("R", "&>"); i += (substr(s, i + 2, 1) == ">") ? 3 : 2; continue }
      addtok("OP", "&"); i++; continue
    }
    if (c == "|") {
      endword()
      if (c2 == "|") { addtok("OP", "||"); i += 2; continue }
      addtok("OP", "|"); i += (c2 == "&") ? 2 : 1; continue
    }
    if (c == ";") { endword(); addtok("OP", (c2 == ";") ? ";;" : ";"); i += (c2 == ";") ? 2 : 1; if (substr(s, i, 1) == "&") i++; continue }
    if (c == "(" || c == ")") { endword(); COMPLEX = 1; addtok("OP", c); i++; continue }
    if (c == "<" || c == ">") {
      if (INW && WR ~ /^[0-9]+$/) { W = ""; WR = ""; INW = 0; WDYN = 0 } else endword()
      COMPLEX = 1; op = c; k = i + 1
      if (c == "<" && c2 == "<") {
        if (substr(s, k + 1, 1) == "<") { op = "<<<"; k += 2 }
        else {
          op = "<<"; k++
          if (substr(s, k, 1) == "-") { op = "<<-"; k++ }
          while (k <= n && index(" \t", substr(s, k, 1))) k++
          d = ""; dq = 0
          while (k <= n) {
            dch = substr(s, k, 1)
            if (index(" \t\n;&|<>()", dch)) break
            if (dch == SQ || dch == "\"") { dq = 1; k++; continue }
            if (dch == "\\") { dq = 1; d = d substr(s, k + 1, 1); k += 2; continue }
            d = d dch; k++
          }
          if (d == "") return "here-document without a delimiter"
          addtok("H", "")
          NH++; H_delim[NH] = d; H_strip[NH] = (op == "<<-"); H_q[NH] = dq; H_tok[NH] = NT
          i = k; continue
        }
      } else if (c == ">" && (c2 == ">" || c2 == "|")) { op = op c2; k++ }
      else if (c == "<" && c2 == ">") { op = "<>"; k++ }
      else if (c2 == "&") {
        op = op "&"; k++
        if (index("0123456789-", substr(s, k, 1)) && substr(s, k, 1) != "") {
          while (k <= n && index("0123456789-", substr(s, k, 1))) k++
          addtok("RX", op); i = k; continue
        }
      }
      addtok("R", op); i = k; continue
    }
    W = W c; WR = WR c; INW = 1; i++
  }
  endword()
  return ""
}
function is_assign(raw) { return raw ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/ }
function has(list, w) { return index(list, " " w " ") > 0 }
function base(p) { sub(/.*\//, "", p); return p }
function joinv(from, to,    j, out) { out = ""; for (j = from; j <= to; j++) out = out (j > from ? " " : "") SV[j]; return out }
function joinr(from, to,    j, out) { out = ""; for (j = from; j <= to; j++) out = out (j > from ? " " : "") SR[j]; return out }
function reset_seg() { NS = 0; SEG_REDIR = 0; SEG_HB = ""; SEG_HASH = 0; PEND_RT = 0; SEG_TXT = "" }
function parse(    t, ty, lastop) {
  reset_seg(); CASEN = 0; lastop = ""
  for (t = 1; t <= NT; t++) {
    ty = T_type[t]
    if (ty == "W") {
      SEG_TXT = SEG_TXT " " T_raw[t]
      if (PEND_RT) { PEND_RT = 0; continue }
      NS++; SV[NS] = T_val[t]; SR[NS] = T_raw[t]; SDY[NS] = T_dyn[t]; continue
    }
    if (ty == "R") { SEG_REDIR = 1; PEND_RT = 1; continue }
    if (ty == "RX") { SEG_REDIR = 1; continue }
    if (ty == "H") { SEG_REDIR = 1; SEG_HASH = 1; SEG_HB = SEG_HB T_val[t]; SEG_TXT = SEG_TXT " " T_val[t]; continue }
    # A case pattern ("b)" after ";;") is not a command.
    if (!(T_val[t] == ")" && CASEN > 0 && lastop == ";;")) flush()
    reset_seg(); lastop = T_val[t]
  }
  flush()
}
# Normalises the global options of tool over A[1..NA] into O[1..NO] and GL. Returns "" or a reason.
function norm(tool,    j, a, name, eq, nr, k, L, rest, keep, p) {
  NO = 0; GL = ""; nr = 0
  if (tool == "make" || tool == "gmake") {
    for (j = 1; j <= NA; j++) {
      a = A[j]
      if (a == "--") { for (j = j + 1; j <= NA; j++) O[++NO] = A[j]; break }
      if (a ~ /^--./) {
        name = substr(a, 3); eq = index(name, "="); if (eq) name = substr(name, 1, eq - 1)
        if (has(MK_VAL, name)) { if (eq || j == NA) GL = GL " " a; else { GL = GL " " a " " A[j + 1]; j++ } continue }
        if (has(MK_OPT, name)) { GL = GL " " a; if (!eq && j < NA && A[j + 1] ~ /^[0-9.]+$/) { GL = GL " " A[j + 1]; j++ } continue }
        O[++NO] = a; continue
      }
      if (a ~ /^-./) {
        keep = "-"
        for (p = 2; p <= length(a); p++) {
          L = substr(a, p, 1); rest = substr(a, p + 1)
          if (index("CfIoWE", L)) { if (rest != "" || j == NA) GL = GL " -" L rest; else { GL = GL " -" L " " A[j + 1]; j++ } break }
          if (index("jlO", L)) {
            if (rest == "" && L != "O" && j < NA && A[j + 1] ~ /^[0-9.]+$/) { GL = GL " -" L " " A[j + 1]; j++ } else GL = GL " -" L rest
            break
          }
          keep = keep L
        }
        if (keep != "-") O[++NO] = keep
        continue
      }
      O[++NO] = a
    }
    sub(/^ /, "", GL); return ""
  }
  if (!(tool in VAL)) { for (j = 1; j <= NA; j++) O[++NO] = A[j]; return "" }
  for (j = 1; j <= NA; j++) {
    a = A[j]
    if (a == "--") { GL = GL " --"; j++; break }
    if (substr(a, 1, 1) != "-" || a == "-") break
    name = a; sub(/^--?/, "", name); eq = index(name, "="); if (eq) name = substr(name, 1, eq - 1)
    if (has(RELOC[tool], name)) { RL[++nr] = a; continue }
    if (has(VAL[tool], name)) { if (eq || j == NA) GL = GL " " a; else { GL = GL " " a " " A[j + 1]; j++ } continue }
    if (has(BOOL[tool], name)) { GL = GL " " a; continue }
    if (a ~ /^-[A-Za-z0-9]./ && has(VAL[tool], substr(a, 2, 1))) { GL = GL " " a; continue }
    return "unknown option " a " before the " tool " subcommand"
  }
  for (; j <= NA; j++) O[++NO] = A[j]
  for (k = 1; k <= nr; k++) O[++NO] = RL[k]
  sub(/^ /, "", GL); return ""
}
function emit(origin, tool, from, to,    j, line, why, ops) {
  NA = 0; for (j = from; j <= to; j++) A[++NA] = SV[j]
  # --guard bookkeeping: a command that is neither a guarded tool nor known to be inert may run
  # text it was given; a shell, interpreter or ssh without a script operand may run its stdin.
  if (!has(GUARD, tool) && !has(INERT, tool) && !(tool == "command" && (A[1] == "-v" || A[1] == "-V"))) { SEG_NONEX = 1; if (SEG_TOOL == "") SEG_TOOL = tool }
  if (tool == "ssh") SEG_STDIN = 1
  else if (has(STDIN_EXEC, tool)) {
    ops = 0; for (j = 1; j <= NA; j++) { if (A[j] == "-s" || A[j] == "-") { ops = 0; break } if (A[j] !~ /^-/) ops++ }
    if (ops == 0) SEG_STDIN = 1
  }
  why = norm(tool)
  if (why != "") { unparseable(why, joinr(1, NS)); return }
  if (LONG) line = origin "\t" esc(tool) "\t" (GL == "" ? "-" : esc(GL)) "\t" esc(joinv(WSTART, E)); else line = esc(tool)
  for (j = 1; j <= NO; j++) line = line "\t" esc(O[j])
  print line
}
# names(text, t): 1 when t occurs in text as a word (not inside a longer [A-Za-z0-9_.-] run).
function names(text, t,    s, p, b, a) {
  s = text
  while ((p = index(s, t)) > 0) {
    b = (p == 1) ? "" : substr(s, p - 1, 1); a = substr(s, p + length(t), 1)
    if (b !~ /[A-Za-z0-9_.-]/ && a !~ /[A-Za-z0-9_.-]/) return 1
    s = substr(s, p + 1)
  }
  return 0
}
# The --guard backstop for the simple command just flushed (see the header).
function guard_check(    n, g, j, txt) {
  if (GUARD == "" || !(SEG_NONEX || SEG_COMPUTED)) return
  n = split(GUARD, g, " "); txt = SEG_TXT; sub(/^ /, "", txt)
  if (SEG_NONEX) for (j = 1; j <= n; j++) if (g[j] != "" && names(txt, g[j])) {
    unparseable("guarded tool " g[j] " is named in the text of " SEG_TOOL ", which may run it", txt); return
  }
  if (SEG_COMPUTED || SEG_STDIN) for (j = 1; j <= n; j++) if (g[j] != "" && names(ROOT, g[j])) {
    if (SEG_COMPUTED) unparseable("guarded tool " g[j] " is named in a line whose command word is computed at run time", ROOT)
    else unparseable("guarded tool " g[j] " is named in a line where " SEG_TOOL " may read commands from stdin", ROOT)
    return
  }
}
# wopts(k, sv, lv, ov, mode): parse the OWN options of a wrapper from SV[k] the way getopt does (v1.2.3,
# waterx-fe#1149 round 5). sv: the short letters that take a value, attached (-ubob, -cCMD) or as
# the next word (-u bob), also as the last letter of a cluster (-lc cmd); ov: short letters whose
# optional value can only be attached (-m/proc/1/ns/mnt); lv: " long names " that take a value
# (--user=bob or --user bob; an unambiguous prefix of one counts as it); any other --name takes
# one only as --name=value. mode "+" stops at the first non-option, like an optstring starting with
# "+"; mode "p" steps over non-options (su: the shell receives "-c CMD" after USER). "--" ends the
# options and is consumed (WDD = 1). Sets OPT[letter or long name] = value ("" for a flag) and
# returns the index of the first word after the options. stop: " names " after which parsing ends
# (env -S STRING: the words after STRING follow the split command, they are not env options).
function wopts(k, sv, lv, ov, mode, stop,    v, p, L, rest, name, eq) {
  split("", OPT); WDD = 0
  while (k <= E) {
    v = SV[k]
    if (v == "--") { WDD = 1; k++; break }
    if (v !~ /^-./) { if (mode == "p") { k++; continue } break }
    k++
    if (substr(v, 1, 2) == "--") {
      name = substr(v, 3); eq = index(name, "=")
      if (eq) { v = lname(substr(name, 1, eq - 1), lv); OPT[v] = substr(name, eq + 1); if (has(stop, v)) break; continue }
      name = lname(name, lv)
      if (has(lv, name)) { if (k <= E) { OPT[name] = SV[k]; k++ } else OPT[name] = "" } else OPT[name] = ""
      if (has(stop, name)) break
      continue
    }
    for (p = 2; p <= length(v); p++) {
      L = substr(v, p, 1); rest = substr(v, p + 1)
      if (index(sv, L)) { if (rest != "") OPT[L] = rest; else if (k <= E) { OPT[L] = SV[k]; k++ } else OPT[L] = ""; break }
      if (index(ov, L)) { OPT[L] = rest; break }
      OPT[L] = ""
    }
    if (has(stop, L)) break
  }
  return k
}
# lname(name, lv): name, or the one long option in lv that name is an unambiguous prefix of.
function lname(name, lv,    n, w, j, hit) {
  if (name == "" || has(lv, name)) return name
  n = split(lv, w, " "); hit = ""
  for (j = 1; j <= n; j++) if (index(w[j], name) == 1) { if (hit != "") return name; hit = w[j] }
  return (hit == "" ? name : hit)
}
# optget(a, b): the value wopts recorded for option a or its other spelling b, or "\001" when absent.
function optget(a, b) { if (a in OPT) return OPT[a]; if (b != "" && b in OPT) return OPT[b]; return "\001" }
function flush(    k, v, wr) {
  if (NS == 0) return
  wr = (CUR_DEPTH > 0 || COMPLEX || SEG_REDIR)
  k = 1
  while (k <= NS) {
    v = SV[k]; if (SR[k] != v) break
    if (v == "esac" && CASEN > 0) CASEN--
    if (has(" ! { } if then else elif fi do done while until esac ", v)) { k++; continue }
    if (v == "time") { wr = 1; k++; if (k <= NS && SV[k] == "-p") k++; continue }
    if (v == "case") { CASEN++; return }
    if (v == "for" || v == "select" || v == "[[" || v == "]]") return
    if (v == "function") { k += 2; continue }
    break
  }
  while (k <= NS && is_assign(SR[k])) { k++; wr = 1 }
  SEG_NONEX = 0; SEG_STDIN = 0; SEG_COMPUTED = 0; SEG_TOOL = ""
  unwrap(k, NS, wr)
  guard_check()
}
# unwrap(k, e, wr): peel wrappers off the simple command in SV[k..e] and emit what runs. Sets the
# globals E (end of the range) and WSTART (its first word) that emit() reads.
function unwrap(k, e, wr,    v, t, hasc, kb, j, s0, a, b, keep, cmd, pk, pe) {
  E = e; WSTART = k
  while (k <= E) {
    if (SDY[k]) { SEG_COMPUTED = 1; unparseable("command word is computed at run time", joinr(1, NS)); return }
    t = base(SV[k]); if (t != SV[k]) wr = 1
    if (t == "") return
    if (t == "gtimeout") t = "timeout"
    if (t == "env") {
      # env [opts] [NAME=value]... [COMMAND]: options and assignments, then the command.
      wr = 1; k++
      while (1) {
        k = wopts(k, "uCPS", " unset chdir split-string ", "", "+", " S split-string ")
        cmd = optget("S", "split-string")
        if (cmd != "\001") { enqueue("env " cmd (k <= E ? " " joinv(k, E) : ""), CUR_DEPTH + 1); return }
        if (WDD || k > E || !is_assign(SV[k])) break
        while (k <= E && is_assign(SV[k])) k++
      }
      if (k > E) { emit_self("env", WSTART, wr); return }
      continue
    }
    if (t == "command" || t == "builtin" || t == "nohup" || t == "exec") {
      if (t == "command" && (SV[k + 1] == "-v" || SV[k + 1] == "-V")) break
      wr = 1; k = wopts(k + 1, (t == "exec" ? "a" : ""), "", "", "+")
      if (k > E) { emit_self(t, WSTART, wr); return }
      continue
    }
    if (t == "time") {
      wr = 1; k = wopts(k + 1, "of", " output format ", "", "+")
      continue
    }
    if (t == "sudo" || t == "doas") {
      wr = 1; k = wopts(k + 1, "ughpCDrtUTRac", " user group host prompt close-from chdir role type other-user command-timeout chroot login-class auth-type ", "", "+")
      if (k > E) { emit_self(t, WSTART, wr); return }
      continue
    }
    if (t == "timeout") { wr = 1; k = wopts(k + 1, "sk", " signal kill-after ", "", "+"); k++; continue }
    # Prefix wrappers: options (the tables WS/WL/WO, see BEGIN), WPOS[t] positionals, then the command.
    if (t in WPOS) {
      wr = 1; s0 = k; k = wopts(k + 1, WS[t], WL[t], WO[t], "+")
      # ionice/taskset/chrt -p PID (and ionice -P/-u) act on a running process: there is no command.
      if ((t == "ionice" || t == "taskset" || t == "chrt") && (optget("p", "pid") != "\001" || (t == "ionice" && (optget("P", "pgid") != "\001" || optget("u", "uid") != "\001")))) { emit_self(t, WSTART, wr); return }
      k += WPOS[t]
      if (k > E) { emit_self(t, s0, wr); return }
      continue
    }
    if (t == "xargs") {
      wr = 1; k = wopts(k + 1, "aEILnsPdJRS", " arg-file delimiter max-args max-procs max-chars process-slot-var ", "eil", "+")
      if (k > E) { emit_self("xargs", WSTART, wr); return }
      continue
    }
    if (t == "watch") {
      wr = 1; k = wopts(k + 1, "nq", " interval equexit ", "d", "+")
      if (k <= E) enqueue(joinv(k, E), CUR_DEPTH + 1)
      return
    }
    if (t == "parallel") {
      wr = 1; s0 = k; k = wopts(k + 1, "jSadICNnLEl", PAR_VAL, "", "+")
      for (j = k; j <= E && SV[j] !~ /^::::?\+?$/; j++) ;
      if (k > E || j == k) { emit_self("parallel", s0, wr); return }
      # One word holding spaces is a command line parallel hands to a shell.
      if (j == k + 1 && SV[k] ~ /[ \t;|&]/) { enqueue(SV[k], CUR_DEPTH + 1); return }
      pe = E; unwrap(k, j - 1, 1); E = pe
      return
    }
    if (t == "su" || t == "runuser") {
      wr = 1; s0 = k
      k = wopts(k + 1, RU_S, RU_L, "", "+")
      # runuser [opts] -u USER [--] COMMAND...: the command starts after the options.
      if (t == "runuser" && optget("u", "user") != "\001") {
        if (k > E) { emit_self(t, s0, wr); return }
        continue
      }
      # su/runuser [opts] [-] [USER [ARGS]]: ARGS go to the login shell of USER, so a -c COMMAND after USER
      # runs too; look for it (attached or not) in every option before "--".
      wopts(s0 + 1, RU_S, RU_L, "", "p")
      cmd = optget("c", "command"); if (cmd == "\001") cmd = optget("session-command", "")
      if (cmd != "\001") { enqueue(cmd, CUR_DEPTH + 1); return }
      emit_self(t, s0, wr); return
    }
    if (t == "sg") {
      # sg [-] GROUP [-c] COMMAND: only the word right after GROUP can be the -c of sg.
      wr = 1; k++; if (k <= E && SV[k] == "-") k++
      k++
      if (k > E) { emit_self(t, WSTART, wr); return }
      if (SV[k] == "-c") { if (k < E) enqueue(SV[k + 1], CUR_DEPTH + 1); return }
      enqueue(joinv(k, E), CUR_DEPTH + 1); return
    }
    if (t == "flock" || t == "script") {
      # flock [opts] FILE (-c STRING | COMMAND...)   script [opts] [FILE] (-c STRING | COMMAND... (BSD))
      # The wrapper options end at FILE; -c is looked for there and right after FILE only.
      wr = 1; s0 = k
      if (t == "flock") k = wopts(k + 1, "wEc", " timeout conflict-exit-code command ", "", "+")
      else k = wopts(k + 1, "cBEIOTmto", " command log-io echo log-in log-out log-timing logging-format output-limit ", "", "+")
      cmd = optget("c", "command")
      if (cmd != "\001") { enqueue(cmd, CUR_DEPTH + 1); return }
      k++
      if (k > E) { emit_self(t, s0, wr); return }
      if (SV[k] == "-c" || SV[k] == "--command") { if (k < E) enqueue(SV[k + 1], CUR_DEPTH + 1); return }
      if (index(SV[k], "--command=") == 1) { enqueue(substr(SV[k], 11), CUR_DEPTH + 1); return }
      continue
    }
    if (t == "find") {
      # find ... -exec CMD... ; | -exec CMD... {} +   (also -execdir, -ok, -okdir): each CMD runs.
      keep = ""; pe = E; pk = WSTART
      for (j = k + 1; j <= pe; j++) {
        keep = keep "\001" SV[j]
        if (SV[j] == "-exec" || SV[j] == "-execdir" || SV[j] == "-ok" || SV[j] == "-okdir") {
          a = j + 1
          for (b = a; b <= pe; b++) if (SV[b] == ";" || (SV[b] == "+" && b > a && SV[b - 1] == "{}")) break
          if (b > a) unwrap(a, b - 1, 1)
          E = pe; WSTART = pk
          j = b; if (b <= pe) keep = keep "\001" SV[b]
        }
      }
      NA = (keep == "" ? 0 : split(substr(keep, 2), A, "\001"))
      emit_args("wrapped", "find")
      return
    }
    if (t == "direnv" && SV[k + 1] == "exec") { wr = 1; k += 3; continue }
    if (t == "eval") { if (k < E) enqueue(joinv(k + 1, E), CUR_DEPTH + 1); return }
    if (has(" bash sh zsh dash ksh fish ", t)) {
      hasc = 0; kb = k; k++
      while (k <= E && (SV[k] ~ /^[-+]/)) {
        v = SV[k]; k++
        if (v == "--" || v == "-") break
        if (v ~ /^[-+][oO]$/ || v == "--rcfile" || v == "--init-file") { k++; continue }
        if (v ~ /^-[A-Za-z]*c[A-Za-z]*$/) hasc = 1
      }
      if (hasc) { if (k <= E) enqueue(SV[k], CUR_DEPTH + 1); return }
      if (SEG_HASH && (k > E)) { enqueue(SEG_HB, CUR_DEPTH + 1); return }
      k = kb; break
    }
    break
  }
  if (k > E) return
  emit(wr ? "wrapped" : "plain", base(SV[k]), k + 1, E)
}
# emit_args(origin, tool): emit tool with the arguments already in A[1..NA] (find, whose -exec
# operands were emitted on their own lines).
function emit_args(origin, tool,    j, line) {
  if (LONG) line = origin "\t" esc(tool) "\t-\t" esc(joinv(WSTART, E)); else line = esc(tool)
  for (j = 1; j <= NA; j++) line = line "\t" esc(A[j])
  print line
}
function emit_self(t, from, wr) { emit(wr ? "wrapped" : "plain", t, from + 1, E) }
BEGIN {
  SQ = sprintf("%c", 39); MAXDEPTH = 6; LONG = (mode == "long")
  GUARD = ""; if (guard != "") { GUARD = guard; gsub(/[,\t]/, " ", GUARD); GUARD = " " GUARD " " }
  # Commands that never run another program or text given in their arguments (the --guard backstop
  # skips them). Not here on purpose: man (-P runs a pager string), less/more (+!cmd), rg (--pre),
  # sort (--compress-program), awk/sed/find/git/gh and every interpreter.
  INERT = " echo printf cat head tail wc grep egrep fgrep ag ack ls stat file which whereis type hash help test [ true false jq yq uniq cut tr diff cmp basename dirname realpath readlink touch mkdir rm cp mv ln chmod chown tee base64 md5sum shasum sha256sum cd pwd "
  # Shells and interpreters that run commands from stdin when given no script operand (ssh always may).
  STDIN_EXEC = " bash sh zsh dash ksh fish csh tcsh python python2 python3 perl ruby node deno bun php lua tclsh osascript parallel source . "
  # Prefix wrappers: WPOS = positionals before the command; WS/WL/WO = the options that take a
  # value, in wopts() form: short letters, " long names ", short letters with an attached-only value.
  WPOS["nice"] = 0; WS["nice"] = "n"; WL["nice"] = " adjustment "
  WPOS["stdbuf"] = 0; WS["stdbuf"] = "ioe"; WL["stdbuf"] = " input output error "
  WPOS["ionice"] = 0; WS["ionice"] = "cnpPu"; WL["ionice"] = " class classdata pid pgid uid "
  WPOS["setsid"] = 0
  WPOS["chroot"] = 1; WL["chroot"] = " userspec groups "
  WPOS["taskset"] = 1
  WPOS["chrt"] = 1; WS["chrt"] = "TPD"; WL["chrt"] = " sched-runtime sched-period sched-deadline "
  WPOS["caffeinate"] = 0; WS["caffeinate"] = "tw"
  WPOS["unbuffer"] = 0
  WPOS["nsenter"] = 0; WS["nsenter"] = "tSGW"; WL["nsenter"] = " target setuid setgid wdns "; WO["nsenter"] = "muinpCUTrw"
  WPOS["unshare"] = 0; WS["unshare"] = "RwSG"; WL["unshare"] = " root wd setuid setgid propagation setgroups map-user map-group map-users map-groups "
  WPOS["pkexec"] = 0; WL["pkexec"] = " user "
  WPOS["systemd-run"] = 0; WS["systemd-run"] = "puEMH"; WL["systemd-run"] = " property unit setenv machine host description slice uid gid nice working-directory service-type timer-property path-property socket-property on-active on-boot on-startup on-unit-active on-unit-inactive on-calendar "
  WPOS["firejail"] = 0
  WPOS["strace"] = 0; WS["strace"] = "abeEIoOpPsSuUX"; WL["strace"] = " output trace signal abbrev verbose raw read write fault inject status attach user env string-limit columns summary-sort-by trace-path "
  # su and runuser: -c/--command/--session-command carry the command; -u/--user (runuser) the user.
  RU_S = "cgGswu"; RU_L = " command session-command group supp-group shell whitelist-environment user "
  PAR_VAL = " jobs sshlogin sshloginfile slf arg-file delimiter colsep joblog results res timeout tmpdir workdir wd max-args max-replace-args env memfree load delay retries halt tagstring basefile bf return transferfile tf sshdelay termseq "
  VAL["kubectl"] = " n namespace context cluster user kubeconfig s server token as as-group as-uid request-timeout certificate-authority client-certificate client-key tls-server-name cache-dir profile profile-output log-file log-dir log-file-max-size log-flush-frequency v vmodule password username stderrthreshold "
  BOOL["kubectl"] = " insecure-skip-tls-verify warnings-as-errors disable-compression match-server-version alsologtostderr logtostderr skip-headers skip-log-headers one-output add-dir-header help h "
  RELOC["kubectl"] = " dry-run "
  VAL["gcloud"] = " project account billing-project configuration flags-file flatten format impersonate-service-account trace-token verbosity access-token-file region zone "
  BOOL["gcloud"] = " quiet q log-http no-log-http user-output-enabled no-user-output-enabled help h "
  VAL["terraform"] = " chdir "; BOOL["terraform"] = " help h version v "
  VAL["tofu"] = VAL["terraform"]; BOOL["tofu"] = BOOL["terraform"]
  VAL["helm"] = " n namespace kube-context kubeconfig kube-apiserver kube-as-group kube-as-user kube-ca-file kube-token kube-tls-server-name registry-config repository-cache repository-config burst-limit qps content-cache "
  BOOL["helm"] = " debug kube-insecure-skip-tls-verify help h "
  VAL["argocd"] = " server auth-token config argocd-context header logformat loglevel port-forward-namespace kube-context client-crt client-crt-key server-crt redis-haproxy-name redis-name repo-server-name http-retry-max controller-name redis-compress server-name "
  BOOL["argocd"] = " grpc-web insecure plaintext port-forward core prompts-enabled help h "
  VAL["git"] = " C c git-dir work-tree namespace super-prefix config-env attr-source "
  BOOL["git"] = " no-pager p paginate P bare no-replace-objects literal-pathspecs glob-pathspecs noglob-pathspecs icase-pathspecs no-optional-locks no-lazy-fetch no-advice html-path man-path info-path version help exec-path "
  VAL["gh"] = " R repo "; BOOL["gh"] = " help "
  MK_VAL = " directory file makefile include-dir old-file assume-old what-if new-file assume-new eval "
  MK_OPT = " jobs load-average max-load output-sync debug shuffle jobserver-style "
  input = ""; cnt = 0
  while ((getline line) > 0) input = (cnt++ ? input "\n" : "") line
  ROOT = input
  NQ = 1; Q[1] = input; QD[1] = 0
  for (qi = 1; qi <= NQ; qi++) {
    if (qi > 64) { unparseable("more than 64 nested scripts", ROOT); break }
    CUR_DEPTH = QD[qi]
    err = lex(Q[qi])
    if (err != "") { unparseable(err, Q[qi]); continue }
    parse()
  }
}'

SHSEG_JSON_AWK='
function ws() { while (i <= n && index(" \t\r\n", substr(s, i, 1))) i++ }
function hexv(h,    k, v, d) {
  v = 0
  for (k = 1; k <= length(h); k++) { d = index("0123456789abcdef", tolower(substr(h, k, 1))); if (!d) return -1; v = v * 16 + d - 1 }
  return v
}
function utf8(cp) {
  if (cp < 128) return sprintf("%c", cp)
  if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
  if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
  return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
}
function pstring(    c, out, cp, lo) {
  i++; out = ""
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\"") { i++; STR = out; return 1 }
    if (c == "\\") {
      c = substr(s, i + 1, 1); i += 2
      if (c == "n") out = out "\n"; else if (c == "t") out = out "\t"; else if (c == "r") out = out "\r"
      else if (c == "b") out = out "\b"; else if (c == "f") out = out "\f"
      else if (c == "u") {
        cp = hexv(substr(s, i, 4)); if (cp < 0) return 0; i += 4
        if (cp >= 55296 && cp <= 56319 && substr(s, i, 2) == "\\u") { lo = hexv(substr(s, i + 2, 4)); if (lo < 0) return 0; i += 6; cp = 65536 + (cp - 55296) * 1024 + (lo - 56320) }
        out = out utf8(cp)
      } else if (c == "\"" || c == "\\" || c == "/") out = out c
      else return 0
      continue
    }
    out = out c; i++
  }
  return 0
}
function shq(x) { gsub(SQ, SQ "\\" SQ SQ, x); return SQ x SQ }
function pvalue(path,    c, key, idx, tok) {
  ws(); c = substr(s, i, 1)
  if (c == "{") {
    i++; ws(); if (substr(s, i, 1) == "}") { i++; return 1 }
    while (1) {
      ws(); if (substr(s, i, 1) != "\"") return 0
      if (!pstring()) return 0
      key = STR; ws(); if (substr(s, i, 1) != ":") return 0
      i++
      if (!pvalue(path == "" ? key : path "." key)) return 0
      ws(); c = substr(s, i, 1); i++
      if (c == ",") continue
      if (c == "}") return 1
      return 0
    }
  }
  if (c == "[") {
    i++; ws(); idx = 0
    if (path == WANT && !FOUND) { FOUND = 1; VALUE = ""; ARR = 1 }
    if (substr(s, i, 1) == "]") { i++; return 1 }
    while (1) {
      ws()
      if (path == WANT && ARR == 1 && substr(s, i, 1) == "\"") { if (!pstring()) return 0; VALUE = VALUE (idx ? " " : "") shq(STR) }
      else { if (path == WANT) ARR = 2; if (!pvalue(path "." idx)) return 0 }
      idx++; ws(); c = substr(s, i, 1); i++
      if (c == ",") continue
      if (c == "]") return 1
      return 0
    }
  }
  if (c == "\"") { if (!pstring()) return 0; if (path == WANT && !FOUND) { FOUND = 1; VALUE = STR }; return 1 }
  tok = ""
  while (i <= n && index("-+.0123456789eEtruefalsn", substr(s, i, 1))) { tok = tok substr(s, i, 1); i++ }
  if (tok == "") return 0
  if (tok != "true" && tok != "false" && tok != "null" && tok !~ /^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$/) return 0
  if (path == WANT && !FOUND && tok != "null") { FOUND = 1; VALUE = tok }
  return 1
}
BEGIN {
  SQ = sprintf("%c", 39); WANT = want; s = ""; cnt = 0
  while ((getline line) > 0) s = (cnt++ ? s "\n" : "") line
  n = length(s); i = 1
  if (!pvalue("")) exit 2
  ws(); if (i <= n) exit 2
  if (!FOUND || ARR == 2) exit 1
  printf "%s", VALUE
  exit 0
}'

# shseg_segments [--long] [--guard "TOOL..."] [--] COMMAND — print the simple commands in COMMAND
# (see the header). --guard (or $SHSEG_GUARD) turns on the fail-closed backstop for those tools.
shseg_segments() {
  _shseg_mode=short; _shseg_guard=${SHSEG_GUARD:-}
  while :; do
    case "${1:-}" in
      --long) _shseg_mode=long; shift ;;
      --guard) _shseg_guard=${2:-}; shift 2 ;;
      --guard=*) _shseg_guard=${1#--guard=}; shift ;;
      *) break ;;
    esac
  done
  [ "${1:-}" = "--" ] && shift
  printf '%s' "${1:-}" | LC_ALL=C "${SHSEG_AWK_BIN:-awk}" -v mode="$_shseg_mode" -v guard="$_shseg_guard" "$SHSEG_AWK"
}

# shseg_json_get PATH — the JSON value at the dotted PATH (e.g. tool_input.command), from stdin.
# Exit 0 found (value printed without a trailing newline), 1 absent or null, 2 not valid JSON.
shseg_json_get() {
  LC_ALL=C "${SHSEG_AWK_BIN:-awk}" -v want="${1:-}" "$SHSEG_JSON_AWK"
}

# shseg_names_tool TOOL LINE — 0 when an UNPARSEABLE LINE's raw text names TOOL as a word
# (also as /path/TOOL), so an ask hook can fail closed on it.
shseg_names_tool() {
  # The raw text arrives escaped (\n, \t, \r): turn those back into blanks so a tool at the start
  # of a line still counts as a word.
  printf '%s\n' "$2" | sed 's/\\[ntr]/ /g' | grep -Eq "(^|[^[:alnum:]_.-])(/[^[:space:]]*/)?$1([^[:alnum:]_.-]|\$)"
}

# The Codex prompt-rule reader: every prefix_rule(..., decision = "prompt") pattern in the .rules
# text on stdin, words space-joined, one per line; a list of alternatives inside a pattern expands
# to one line per choice (["gh", ["pr", "run"], "merge"]); single- and double-quoted strings,
# comments and multi-line calls are read. harness/lint/check-harness.sh carries the same program
# as PROMPT_RULES_AWK (the lint is vendored alone, so it keeps its own copy): the two must stay
# identical, and harness/lint/check-harness.test.sh fails when their output differs.
SHSEG_PROMPT_RULES_AWK='
function addtok(t, v) { NT++; TT[NT] = t; TV[NT] = v }
function expand(e, prefix,    k, m, parts) {
  if (e > NE) { print substr(prefix, 2); return }
  m = split(EL[e], parts, "\034")
  for (k = 1; k <= m; k++) expand(e + 1, prefix " " parts[k])
}
BEGIN {
  s = ""; while ((getline line) > 0) s = s line "\n"
  n = length(s); i = 1; NT = 0
  while (i <= n) {
    c = substr(s, i, 1)
    if (index(" \t\r\n", c)) { i++; continue }
    if (c == "#") { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
    if (c == "\"" || c == "\047") {
      q = c; v = ""; i++
      while (i <= n && substr(s, i, 1) != q) { if (substr(s, i, 1) == "\\") { i++ } v = v substr(s, i, 1); i++ }
      i++; addtok("S", v); continue
    }
    if (c ~ /[A-Za-z_]/) { v = ""; while (i <= n && substr(s, i, 1) ~ /[A-Za-z0-9_]/) { v = v substr(s, i, 1); i++ } addtok("I", v); continue }
    addtok("P", c); i++
  }
  for (t = 1; t <= NT; t++) {
    if (!(TT[t] == "I" && TV[t] == "prefix_rule" && TV[t + 1] == "(")) continue
    t += 2; d = 1; key = ""; decision = "allow"; NE = 0; inpat = 0; depth = 0
    for (; t <= NT && d > 0; t++) {
      if (TT[t] == "P" && (TV[t] == "(" || TV[t] == "[" || TV[t] == "{")) { d++; if (inpat && TV[t] == "[") { depth++; if (depth == 2) { NE++; EL[NE] = ""; alt = 1 } } continue }
      if (TT[t] == "P" && (TV[t] == ")" || TV[t] == "]" || TV[t] == "}")) { d--; if (inpat && TV[t] == "]") { depth--; if (depth == 0) inpat = 0 } continue }
      if (d == 1 && TT[t] == "I" && TV[t + 1] == "=") { key = TV[t]; t++; if (key == "pattern") inpat = 1; continue }
      if (d == 1 && TT[t] == "S" && key == "decision") { decision = TV[t]; continue }
      if (inpat && TT[t] == "S") {
        if (depth == 1) { NE++; EL[NE] = TV[t] }
        else if (depth == 2) { EL[NE] = EL[NE] (EL[NE] == "" ? "" : "\034") TV[t] }
      }
    }
    t--
    if (decision == "prompt" && NE > 0) expand(1, "")
  }
}'

# shseg_prompt_prefixes [FILE...] — the Codex prompt-rule prefixes in the .rules FILEs (stdin when
# none), one per line, sorted and unique: what a Codex hook compares a plain command's words with.
shseg_prompt_prefixes() {
  cat "$@" 2>/dev/null | LC_ALL=C "${SHSEG_AWK_BIN:-awk}" "$SHSEG_PROMPT_RULES_AWK" | sed 's/[[:space:]][[:space:]]*/ /g' | sort -u
}

_shseg_self_test() {
  _p=0; _f=0
  _t() { # name expected-lines-with-|-for-TAB input [--long]
    if [ "${4:-}" = "--long" ]; then _got=$(shseg_segments --long "$3" | tr '\t' '|'); else _got=$(shseg_segments "$3" | tr '\t' '|'); fi
    if [ "$_got" = "$2" ]; then _p=$((_p + 1)); else _f=$((_f + 1)); printf 'FAIL %s\n  input:    %s\n  expected: %s\n  got:      %s\n' "$1" "$3" "$2" "$_got"; fi
  }
  _g() { # name expected-lines guard input
    _got=$(shseg_segments --guard "$3" "$4" | tr '\t' '|')
    if [ "$_got" = "$2" ]; then _p=$((_p + 1)); else _f=$((_f + 1)); printf 'FAIL %s\n  input:    %s\n  expected: %s\n  got:      %s\n' "$1" "$4" "$2" "$_got"; fi
  }
  _j() { # name expected-exit expected-output path json
    _got=$(printf '%s' "$5" | shseg_json_get "$4"); _rc=$?
    if [ "$_rc" = "$2" ] && [ "$_got" = "$3" ]; then _p=$((_p + 1)); else _f=$((_f + 1)); printf 'FAIL %s (exit %s, wanted %s)\n  expected: %s\n  got:      %s\n' "$1" "$_rc" "$2" "$3" "$_got"; fi
  }
  NL='
'
  # --- splitting, quoting, comments ---------------------------------------------------------
  _t "split on ; && || | & newline" "a|1${NL}b${NL}c${NL}d${NL}e${NL}f" "a 1; b && c || d | e & f"
  _t "operators inside quotes do not split" "echo|a; b && c" "echo 'a; b && c'"
  _t "comment dropped" "kubectl|delete|pod|api" "kubectl delete pod api # --dry-run=client"
  _t "hash inside a word is not a comment" "echo|a#b" "echo a#b"
  _t "line continuation" "kubectl|delete|pod|x" "kubectl delete \\${NL}pod x"
  _t "redirections removed" "kubectl|apply|-f|x.yaml" "kubectl apply -f x.yaml > out.txt 2>&1 </dev/null"
  _t "subshell and group" "kubectl|delete|ns|a${NL}kubectl|get|pods" "(kubectl delete ns a); { kubectl get pods; }"
  _t "if/then reserved words" "test|-f|x${NL}kubectl|apply|-f|x" "if test -f x; then kubectl apply -f x; fi"
  _t "for header is not a command" "kubectl|delete|ns|\$n" "for n in a b; do kubectl delete ns \$n; done"
  # --- waterx-fe #1149: multiline quoted PR body mentioning git commit (block hook must not fire) --
  _t "fe#1149 multiline quoted body is one gh command" "gh|pr|create|--body|hello\\ngit commit\\nworld" "gh pr create --body \"hello${NL}git commit${NL}world\""
  _t "fe#1149 single-quoted body" "gh|pr|create|--body|x\\ngit commit -m y" "gh pr create --body 'x${NL}git commit -m y'"
  _t "real commit after a body" "gh|pr|create|--body|a\\nb${NL}git|commit|-m|x" "gh pr create --body \"a${NL}b\" && git commit -m x"
  _t "git global options" "cd|/tmp${NL}git|commit|-m|x" "cd /tmp && git -C repo -c a=b --no-pager commit -m x"
  _t "heredoc body is data" "git|commit|-F|-" "git commit -F - <<'EOF'${NL}kubectl delete ns prod${NL}EOF"
  _t "fe#1149 PR body from a quoted here-document in \$( )" "gh|pr|create|--body|\$(...)${NL}cat" "gh pr create --body \"\$(cat <<'EOF'${NL}- git commit hooks; kubectl delete ns prod${NL}EOF${NL})\""
  _t "git commit-tree is not git commit" "git|commit-tree|x" "git commit-tree x"
  _t "pipe into xargs" "kubectl|get|pods${NL}kubectl|delete" "kubectl get pods | xargs kubectl delete"
  _t "case arms are commands" "kubectl|delete|ns|a${NL}echo|no" "case \"\$x\" in a) kubectl delete ns a;; b) echo no;; esac"
  _t "echo of git commit is not a commit" "echo|git commit" "echo 'git commit'"
  # --- gcp-infra #195: global options before the subcommand -------------------------------------
  _t "gcp#195 gcloud --project X run services delete" "gcloud|run|services|delete|svc|--region=asia-southeast1" "gcloud --project waterx-infra run services delete svc --region=asia-southeast1"
  _t "gcp#195 gcloud --quiet compute instances reset" "gcloud|compute|instances|reset|clickhouse-staging|--zone=asia-southeast1-a" "gcloud --quiet compute instances reset clickhouse-staging --zone=asia-southeast1-a"
  _t "gcp#195 make --directory d apply-production" "make|apply-production" "make --directory stacks/waterx/platform apply-production"
  _t "make --directory=d" "make|apply-staging" "make --directory=stacks/waterx/core apply-staging"
  _t "make -C d / -Cd / -sC d" "make|apply-a${NL}make|apply-b${NL}make|-s|apply-c" "make -C d apply-a; make -Cd apply-b; make -sC d apply-c"
  _t "make -n stays visible" "make|-n|apply-production" "make -n -C d apply-production"
  _t "terraform -chdir" "terraform|apply|-auto-approve" "terraform -chdir=stacks/x apply -auto-approve"
  _t "direnv exec . make" "make|apply-staging" "direnv exec . make apply-staging"
  _t "globals in --long" "plain|gcloud|--project waterx-infra|gcloud --project waterx-infra run services delete svc|run|services|delete|svc" "gcloud --project waterx-infra run services delete svc" --long
  # --- k8s-infra #230 ---------------------------------------------------------------------------
  _t "k8s#230 kubectl run" "kubectl|run|shell|--image=busybox" "kubectl run shell --image=busybox"
  _t "k8s#230 kubectl -n ns run" "kubectl|run|shell|--image=busybox" "kubectl -n production run shell --image=busybox"
  _t "k8s#230 kubectl debug" "kubectl|debug|-it|pod/api|--image=busybox" "kubectl --context prod debug -it pod/api --image=busybox"
  _t "k8s#230 kubectl auth reconcile" "kubectl|auth|reconcile|-f|rbac.yaml" "kubectl auth reconcile -f rbac.yaml"
  _t "k8s#230 kubectl certificate approve" "kubectl|certificate|approve|csr-1" "kubectl --kubeconfig=k certificate approve csr-1"
  _t "k8s#230 --dry-run only in a comment" "kubectl|delete|pod|api" "kubectl -n production delete pod api # dry-run alternative: --dry-run=client"
  _t "k8s#230 --dry-run only in a process substitution" "kubectl|apply|-f|<(...)${NL}kubectl|create|cm|x|--dry-run=client|-o|yaml" "kubectl apply -f <(kubectl create cm x --dry-run=client -o yaml)"
  _t "k8s#230 --dry-run in another segment" "kubectl|apply|-f|a.yaml|--dry-run=client${NL}kubectl|apply|-f|a.yaml" "kubectl apply -f a.yaml --dry-run=client && kubectl apply -f a.yaml"
  _t "--dry-run before the verb stays with its command" "kubectl|delete|pod|x|--dry-run=client" "kubectl --dry-run=client delete pod x"
  _t "flag-before-verb with --flag=value" "kubectl|delete|pod|x" "kubectl --namespace=prod --context=c delete pod x"
  _t "unknown option before the verb is unparseable" "UNPARSEABLE|unknown option --frobnicate before the kubectl subcommand|kubectl --frobnicate x delete pod y" "kubectl --frobnicate x delete pod y"
  _t "helm global options" "helm|upgrade|api|./chart" "helm --kube-context prod -n api upgrade api ./chart"
  _t "argocd global options" "argocd|app|sync|api" "argocd --grpc-web --server cd.example app sync api"
  # --- wrappers ---------------------------------------------------------------------------------
  _t "bash -c wrapper" "kubectl|delete|ns|prod" "bash -c 'kubectl delete ns prod'"
  _t "bash -lc wrapper, nested sh -c" "kubectl|delete|ns|prod" "bash -lc \"sh -c 'kubectl delete ns prod'\""
  _t "absolute tool path" "kubectl|delete|ns|prod" "/usr/local/bin/kubectl delete ns prod"
  _t "env prefix" "kubectl|delete|ns|prod" "env KUBECONFIG=/k kubectl delete ns prod"
  _t "env -S" "kubectl|delete|ns|prod" "env -S 'kubectl delete' ns prod"
  _t "sudo prefix" "kubectl|delete|ns|prod" "sudo -u root -E kubectl delete ns prod"
  _t "command prefix" "kubectl|delete|ns|prod" "command kubectl delete ns prod"
  _t "command -v is a lookup" "command|-v|kubectl" "command -v kubectl"
  _t "assignments, nohup, time, nice, timeout" "kubectl|delete|ns|a${NL}kubectl|delete|ns|b${NL}kubectl|delete|ns|c" "A=1 B=2 nohup kubectl delete ns a; time nice -n 5 kubectl delete ns b; timeout -s KILL 30s kubectl delete ns c"
  _t "xargs runs its command" "echo|a${NL}kubectl|delete|pod" "echo a | xargs -n 1 kubectl delete pod"
  _t "eval" "kubectl|delete|ns|prod" "eval 'kubectl delete ns prod'"
  _t "bash reading a here-document" "kubectl|delete|ns|prod" "bash <<'EOF'${NL}kubectl delete ns prod${NL}EOF"
  _t "command substitution runs" "echo|\$(...)${NL}kubectl|delete|ns|prod" "echo \"\$(kubectl delete ns prod)\""
  _t "backticks run" "echo|\$(...)${NL}kubectl|delete|ns|prod" "echo \`kubectl delete ns prod\`"
  _t "substitution in an unquoted here-document runs" "cat${NL}kubectl|delete|ns|prod" "cat <<EOF${NL}\$(kubectl delete ns prod)${NL}EOF"
  _t "quoted here-document does not run" "cat" "cat <<'EOF'${NL}\$(kubectl delete ns prod)${NL}EOF"
  _t "quoted tool name" "kubectl|delete|ns|prod" "\"kubectl\" delete ns prod"
  _t "backslashed tool name" "kubectl|delete|ns|prod" "\\kubectl delete ns prod"
  # --- k8s-infra #230 round 4: exec-style wrappers run their command operand ---------------------
  _t "k8s#230r4 find -exec kubectl ... \;" "kubectl|delete|pod|api${NL}find|/tmp|-prune|-exec|;" "find /tmp -prune -exec kubectl delete pod api \;"
  _t "k8s#230r4 find -exec argocd ... \;" "argocd|app|delete|my-app${NL}find|/tmp|-prune|-exec|;" "find /tmp -prune -exec argocd app delete my-app \;"
  _t "find -exec ... {} +" "kubectl|apply|-f|{}${NL}find|.|-name|*.yaml|-exec|+" "find . -name '*.yaml' -exec kubectl apply -f {} +"
  _t "find -execdir with a quoted ;" "argocd|app|delete|a${NL}find|.|-execdir|;" "find . -execdir argocd app delete a ';'"
  _t "find -ok, gcloud globals inside" "gcloud|run|services|delete|s${NL}find|.|-ok|;" "find . -ok gcloud --project p run services delete s \;"
  _t "find -okdir sh -c terraform" "find|.|-okdir|;${NL}terraform|apply" "find . -okdir sh -c 'terraform apply' \;"
  _t "find -exec git commit" "git|commit|-m|x${NL}find|.|-maxdepth|0|-exec|;" "find . -maxdepth 0 -exec git commit -m x \;"
  _t "two -exec operands" "kubectl|get|pods${NL}kubectl|delete|pod|x${NL}find|.|-exec|;|-exec|;" "find . -exec kubectl get pods \; -exec kubectl delete pod x \;"
  _t "find -exec without a terminator still runs" "kubectl|delete|pod|x${NL}find|.|-exec" "find . -exec kubectl delete pod x"
  _t "find without -exec" "find|.|-name|git commit" "find . -name 'git commit'"
  _t "xargs -I {} -P" "ls${NL}kubectl|delete|pod|{}" "ls | xargs -I {} -P 4 kubectl delete pod {}"
  _t "xargs long options with values" "git|commit|-m|x" "xargs --max-procs 2 --arg-file f git commit -m x"
  _t "parallel ::: " "kubectl|delete|pod" "parallel -j 4 kubectl delete pod ::: a b"
  _t "parallel one-word command line" "argocd|app|delete|{}" "parallel 'argocd app delete {}' ::: a b"
  _t "gtimeout, watch" "terraform|apply${NL}kubectl|delete|pod|x" "gtimeout 5 terraform apply; watch -n 5 kubectl delete pod x"
  _t "ionice, nice, stdbuf" "kubectl|delete|pod|x${NL}git|commit|-m|x" "ionice -c 3 nice -n 5 kubectl delete pod x; stdbuf -oL git commit -m x"
  _t "flock FILE COMMAND, flock -c" "kubectl|delete|pod|x${NL}terraform|apply" "flock /tmp/l kubectl delete pod x; flock -w 5 /tmp/l -c 'terraform apply'"
  _t "chroot, setsid" "argocd|app|delete|a${NL}kubectl|delete|pod|x" "chroot --userspec=u:g /srv argocd app delete a; setsid -f kubectl delete pod x"
  _t "script -c, BSD script FILE COMMAND" "kubectl|delete|pod|x${NL}gcloud|compute|instances|delete|vm" "script -q -c 'gcloud compute instances delete vm' /dev/null; script -q /dev/null kubectl delete pod x"
  _t "su -c, su -lc, runuser, sg -c" "kubectl|delete|pod|y${NL}kubectl|delete|ns|x${NL}terraform|apply${NL}git|commit|-m|z" "su -c 'kubectl delete ns x' root; su -lc 'terraform apply' root; runuser -u bob -- kubectl delete pod y; sg docker -c 'git commit -m z'"
  _t "exec, eval, env -S, fish -c" "kubectl|delete|ns|a${NL}argocd|app|delete|b${NL}terraform|destroy${NL}gcloud|run|services|delete|s" "exec kubectl delete ns a; eval 'argocd app delete b'; env -S 'terraform destroy'; fish -c 'gcloud run services delete s'"
  _t "taskset, chrt, caffeinate, unbuffer" "kubectl|delete|pod|a${NL}kubectl|delete|pod|b${NL}terraform|apply${NL}git|commit|-m|x" "taskset -c 0 kubectl delete pod a; chrt -f 10 kubectl delete pod b; caffeinate -i terraform apply; unbuffer git commit -m x"
  _t "nsenter, unshare, pkexec, systemd-run, firejail, strace" "kubectl|delete|pod|a${NL}kubectl|delete|pod|b${NL}argocd|app|delete|c${NL}terraform|apply${NL}git|commit|-m|x${NL}kubectl|delete|pod|d" "nsenter -t 1 -m kubectl delete pod a; unshare -r kubectl delete pod b; pkexec --user root argocd app delete c; systemd-run --unit x terraform apply; firejail --quiet git commit -m x; strace -f -o out kubectl delete pod d"
  _t "pid modes are not wrappers" "taskset|-p|1${NL}ionice|-p|1" "taskset -p 1; ionice -p 1"
  _t "nested find -exec find -exec" "git|commit|-m|x${NL}find|.|-exec${NL}find|.|-exec|;|;" "find . -exec find . -exec git commit -m x \; \;"
  # --- the --guard backstop: an unknown wrapper naming a guarded tool fails closed ---------------
  _g "ssh host kubectl" "ssh|host|kubectl|delete|pod|x${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh host kubectl delete pod x" "kubectl argocd" "ssh host kubectl delete pod x"
  _g "unknown wrapper with a path on the tool" "npx|-y|/usr/bin/argocd|app|delete|a${NL}UNPARSEABLE|guarded tool argocd is named in the text of npx, which may run it|npx -y /usr/bin/argocd app delete a" "kubectl argocd" "npx -y /usr/bin/argocd app delete a"
  _g "unknown wrapper, terraform" "somewrap|--run|terraform|apply${NL}UNPARSEABLE|guarded tool terraform is named in the text of somewrap, which may run it|somewrap --run terraform apply" "terraform" "somewrap --run terraform apply"
  _g "comma-separated guard list" "ssh|h|gcloud|run|deploy${NL}UNPARSEABLE|guarded tool gcloud is named in the text of ssh, which may run it|ssh h gcloud run deploy" "kubectl,gcloud" "ssh h gcloud run deploy"
  _g "inert commands do not trip it" "echo|kubectl|delete${NL}grep|-r|kubectl|.${NL}command|-v|kubectl${NL}which|argocd${NL}cd|/r${NL}echo|kubectl delete pod x" "kubectl argocd" "echo kubectl delete; grep -r kubectl .; command -v kubectl; which argocd; cd /r; echo 'kubectl delete pod x' > notes.txt"
  _g "v1.2.1: quoted text of a command that may run it prompts (gh, git)" "gh|pr|create|--body|run kubectl delete pod x${NL}UNPARSEABLE|guarded tool kubectl is named in the text of gh, which may run it|gh pr create --body 'run kubectl delete pod x'${NL}git|commit|-m|argocd app delete${NL}UNPARSEABLE|guarded tool argocd is named in the text of git, which may run it|git commit -m 'argocd app delete'" "kubectl argocd" "gh pr create --body 'run kubectl delete pod x'; git commit -m 'argocd app delete'"
  _g "the guarded tool itself and parsed find are not flagged" "kubectl|get|pods${NL}kubectl|get|pods${NL}find|.|-exec|;" "kubectl" "kubectl get pods; find . -exec kubectl get pods \;"
  _g "a word inside a longer name is not the tool" "ssh|h|kubectl-foo|my-kubectl${NL}git|log|--|helm.yaml" "kubectl helm" "ssh h kubectl-foo my-kubectl; git log -- helm.yaml"
  # --- k8s-infra #230 round 5: the remote command of ssh is one quoted word -----------------------
  _g "k8s#230r5 ssh host 'kubectl ...'" "ssh|bastion|kubectl delete pod api${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh bastion 'kubectl delete pod api'" "kubectl argocd helm" "ssh bastion 'kubectl delete pod api'"
  _g "k8s#230r5 ssh host 'argocd ...'" "ssh|bastion|argocd app delete my-app${NL}UNPARSEABLE|guarded tool argocd is named in the text of ssh, which may run it|ssh bastion 'argocd app delete my-app'" "kubectl argocd helm" "ssh bastion 'argocd app delete my-app'"
  _g "k8s#230r5 ssh host sh -c '...'" "ssh|bastion|sh|-c|kubectl delete pod api${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh bastion sh -c 'kubectl delete pod api'" "kubectl argocd helm" "ssh bastion sh -c 'kubectl delete pod api'"
  _g "ssh host \"kubectl ...\" (double quotes)" "ssh|bastion|kubectl delete pod api${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh bastion \"kubectl delete pod api\"" "kubectl" "ssh bastion \"kubectl delete pod api\""
  _g "ssh -t host \"sudo kubectl ...\"" "ssh|-t|host|sudo kubectl delete pod api${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh -t host \"sudo kubectl delete pod api\"" "kubectl" "ssh -t host \"sudo kubectl delete pod api\""
  _g "ssh host -- kubectl ..." "ssh|host|--|kubectl|delete|pod|api${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh host -- kubectl delete pod api" "kubectl" "ssh host -- kubectl delete pod api"
  _g "ssh host \"kubectl get ...\" prompts too (remote text is not parsed)" "ssh|bastion|kubectl get pods${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh bastion \"kubectl get pods\"" "kubectl" "ssh bastion \"kubectl get pods\""
  _g "bash -lc nested twice around ssh" "ssh|h|kubectl delete pod x${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh h 'kubectl delete pod x'" "kubectl" "bash -lc \"bash -lc \\\"ssh h 'kubectl delete pod x'\\\"\""
  _g "bash -lc nested twice, parsed tool" "kubectl|delete|pod|x" "kubectl" "bash -lc \"bash -lc 'kubectl delete pod x'\""
  _g "\$(echo kubectl) delete" "UNPARSEABLE|command word is computed at run time|\$(echo kubectl) delete pod x${NL}UNPARSEABLE|guarded tool kubectl is named in a line whose command word is computed at run time|\$(echo kubectl) delete pod x${NL}echo|kubectl" "kubectl" "\$(echo kubectl) delete pod x"
  _g "backtick command word" "UNPARSEABLE|command word is computed at run time|\`echo argocd\` app delete a${NL}UNPARSEABLE|guarded tool argocd is named in a line whose command word is computed at run time|\`echo argocd\` app delete a${NL}echo|argocd" "argocd" "\`echo argocd\` app delete a"
  _g "variable command word looks at the whole line" "UNPARSEABLE|command word is computed at run time|\$K delete pod x${NL}UNPARSEABLE|guarded tool kubectl is named in a line whose command word is computed at run time|K=kubectl; \$K delete pod x" "kubectl" "K=kubectl; \$K delete pod x"
  _g "here-string to ssh" "ssh|host${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh host 'kubectl delete pod x'" "kubectl" "ssh host <<< 'kubectl delete pod x'"
  _g "here-string to bash" "bash${NL}UNPARSEABLE|guarded tool helm is named in the text of bash, which may run it|bash 'helm uninstall grafana'" "helm" "bash <<< 'helm uninstall grafana'"
  _g "here-document to ssh" "ssh|host${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh host kubectl delete pod x\\n" "kubectl" "ssh host <<'EOF'${NL}kubectl delete pod x${NL}EOF"
  _g "here-document piped into ssh" "cat${NL}ssh|host${NL}UNPARSEABLE|guarded tool argocd is named in a line where ssh may read commands from stdin|cat <<EOF | ssh host\\nargocd app delete a\\nEOF" "argocd" "cat <<EOF | ssh host${NL}argocd app delete a${NL}EOF"
  _g "echo piped into sh" "echo|kubectl delete pod x${NL}sh${NL}UNPARSEABLE|guarded tool kubectl is named in a line where sh may read commands from stdin|echo 'kubectl delete pod x' | sh" "kubectl" "echo 'kubectl delete pod x' | sh"
  _g "interpreter -c string" "python3|-c|import os; os.system(\"kubectl delete pod x\")${NL}UNPARSEABLE|guarded tool kubectl is named in the text of python3, which may run it|python3 -c 'import os; os.system(\"kubectl delete pod x\")'" "kubectl" "python3 -c 'import os; os.system(\"kubectl delete pod x\")'"
  _g "substitution inside an inert command is checked on its own" "echo|\$(...)${NL}ssh|h|kubectl delete pod x${NL}UNPARSEABLE|guarded tool kubectl is named in the text of ssh, which may run it|ssh h 'kubectl delete pod x'" "kubectl" "echo \"\$(ssh h 'kubectl delete pod x')\""
  _g "a script operand is not stdin; pipelines of reads stay quiet" "ruby|check.rb|prod${NL}kubectl|get|pods${NL}awk|{print \$1}${NL}cd|/r${NL}kubectl|get|pods" "kubectl" "ruby check.rb prod; kubectl get pods | awk '{print \$1}'; cd /r && kubectl get pods"
  _t "no --guard: old output" "ssh|host|kubectl|delete|pod|x" "ssh host kubectl delete pod x"
  _t "no --guard (block hooks): quoted text never trips anything" "ssh|bastion|kubectl delete pod api${NL}gh|pr|create|--body|git commit -m x${NL}echo|git commit${NL}sh" "ssh bastion 'kubectl delete pod api'; gh pr create --body 'git commit -m x'; echo 'git commit' | sh"
  # --- waterx-fe #1149 round 4: a wrapper reads ITS OWN options only -----------------------------
  _t "fe#1149r4 flock FILE git -c ... commit" "git|commit|-m|x" "flock /tmp/l git -c user.name=x commit -m x"
  _t "fe#1149r4 BSD script FILE git -c ... commit" "git|commit|-m|x" "script -q /dev/null git -c user.name=x commit -m x"
  _t "script -c after FILE (util-linux permutes)" "git|commit|-m|x" "script log -c 'git commit -m x'"
  _t "runuser -u USER COMMAND -c ..." "git|commit|-m|x" "runuser -u bob git -c k=v commit -m x"
  _t "sg GROUP COMMAND -c ..." "git|commit|-m|x" "sg docker git -c k=v commit -m x"
  # Every wrapper, with a command whose own options look like wrapper options, in block mode and in
  # --guard mode (the guarded tools are the payloads, so both modes print the same).
  while IFS='|' read -r _pre _suf _extra; do
    [ -n "$_pre" ] || continue
    for _cmd in "git -c k=v commit -m x" "kubectl --context c delete pod x"; do
      case "$_cmd" in git*) _want="git|commit|-m|x" ;; *) _want="kubectl|delete|pod|x" ;; esac
      [ -n "$_extra" ] && _want="$_want${NL}$_extra"
      _t "wrapper option scope: $_pre ... $_suf" "$_want" "$_pre $_cmd$_suf"
      _g "wrapper option scope (--guard): $_pre ... $_suf" "$_want" "git kubectl" "$_pre $_cmd$_suf"
    done
  done <<'WRAPPERS'
env A=1 -u B||
command||
nohup||
exec||
time -p||
sudo -u root -E||
doas -u root||
timeout -s KILL 5||
gtimeout 5||
nice -n 5||
ionice -c 3||
stdbuf -oL||
setsid -f||
chroot --userspec=u:g /srv||
taskset -c 0||
chrt -f 10||
caffeinate -i||
unbuffer||
nsenter -t 1 -m||
unshare -r||
pkexec --user root||
systemd-run --unit x||
firejail --quiet||
strace -f -o out||
xargs -n 1||
flock /tmp/l||
flock -w 5 /tmp/l||
script -q /dev/null||
runuser -u bob --||
runuser -u bob||
sg docker||
direnv exec .||
find . -exec| \;|find|.|-exec|;
parallel| ::: a|
watch -n 5||
sudo env A=1 nice||
env -uB A=1||
env -iuB||
env -iu B --||
env --unset=B -C /tmp||
env --unset B -C/tmp||
command -p||
exec -a name||
exec -aname||
/usr/bin/time -oout -f %e||
command time --output=out --format %e||
sudo -uroot -E||
sudo -Euroot --||
sudo --user=root -g wheel||
sudo --user root -gwheel||
doas -uroot||
timeout -s9 5||
timeout -sKILL -k5 5||
timeout --signal=KILL --kill-after 5 5||
gtimeout -s9 -- 5||
nice -n5||
nice --adjustment=5||
nice --adjustment 5||
nice --adj 5||
ionice -c3 -n7||
ionice --class=3 --classdata 7||
stdbuf -o L -eL||
stdbuf --output=L --error L||
setsid -w||
chroot --userspec u:g --groups=g /srv||
taskset -ac 0-3||
chrt -T5 -f 10||
chrt --sched-runtime 5 -f 10||
caffeinate -t60 -i||
caffeinate -it 60||
nsenter -t1 -m||
nsenter -m/proc/1/ns/mnt -t 1||
nsenter --target=1 --mount||
nsenter --target 1 -S0 -G 0||
unshare -R/srv -r||
unshare -w /tmp -r||
unshare --setuid=0 --wd /tmp||
pkexec --user=root||
systemd-run -ux -pK=V||
systemd-run -u x -p K=V --||
systemd-run --unit=x --property K=V||
firejail --profile=x||
strace -oout -f||
strace -e trace=file -o out||
strace -feopen --output out||
xargs -I{}||
xargs -n1 -P4||
xargs -L 1 -0||
xargs -i||
xargs --max-args=1 --delimiter x||
watch -n5 -d||
watch --interval=5 --differences||
flock -w5 /tmp/l||
flock -xw 5 /tmp/l||
flock --timeout=5 -E1 /tmp/l||
flock --timeout 5 -- /tmp/l||
script -qt0 /dev/null||
script -t 0 -q /dev/null||
runuser -ubob --||
runuser -ubob||
runuser --user=bob --||
runuser --user bob||
runuser -lubob --||
parallel -j4| ::: a|
parallel --jobs 4 --halt now,fail=1| ::: a|
WRAPPERS
  # The same, for wrappers that take the command as ONE string (%s is the command): attached
  # (-c'cmd'), separate, --long=, --long, after USER/FILE, and the reviewer forms of round 5.
  while IFS= read -r _tpl; do
    [ -n "$_tpl" ] || continue
    for _cmd in "git -c k=v commit -m x" "kubectl --context c delete pod x"; do
      case "$_cmd" in git*) _want="git|commit|-m|x" ;; *) _want="kubectl|delete|pod|x" ;; esac
      _in="${_tpl%%%s*}$_cmd${_tpl#*%s}"
      _t "command-string option: $_tpl" "$_want" "$_in"
      _g "command-string option (--guard): $_tpl" "$_want" "git kubectl" "$_in"
    done
  done <<'STRINGS'
su -c'%s'
su -c '%s'
su -lc'%s'
su --command='%s'
su --command '%s'
su --comm '%s'
su --session-command='%s' bob
su - bob -c '%s'
su -s /bin/sh bob -c'%s'
su -sbash bob -c '%s'
runuser -c'%s' bob
runuser -l bob -c '%s'
runuser -gwheel -c '%s' bob
script -q -c'%s' /dev/null
script -qc '%s' /dev/null
script --command='%s' /dev/null
script --command '%s' /dev/null
script -q /dev/null -c '%s'
script -t0 -q /dev/null --command='%s'
flock /tmp/l -c '%s'
flock -w5 /tmp/l -c '%s'
flock -c'%s' /tmp/l
env -S'%s'
env -iS '%s'
env --split-string='%s'
env -uVAR -S '%s'
sg docker -c '%s'
watch -n5 '%s'
eval '%s'
bash -c '%s'
sh -lc '%s'
sudo -uroot sh -c '%s'
timeout -s9 5 bash -c '%s'
xargs -I{} sh -c '%s'
nice -n5 bash -c '%s'
STRINGS
  # waterx-fe #1149 round 5: getopt-attached values (reproduced by the reviewer).
  _t "fe#1149r5 runuser -ubob -- git commit" "git|commit|-m|x" "runuser -ubob -- git commit -m x"
  _t "fe#1149r5 script -q -c'git commit' /dev/null" "git|commit|-m|x" "script -q -c'git commit -m x' /dev/null"
  _t "fe#1149r5 su -cfoo runs foo" "foo" "su -cfoo"
  _t "env -S stops env option parsing" "git|commit|-m|x" "env -iS'git commit' -m x"
  _t "pid modes with attached values are not wrappers" "taskset|-pc|0|1${NL}ionice|-c3|-p1${NL}chrt|-p|5|1" "taskset -pc 0 1; ionice -c3 -p1; chrt -p 5 1"
  # --- origin (Codex prefix-rule visibility) ----------------------------------------------------
  _t "plain" "plain|kubectl|-|kubectl delete pod x|delete|pod|x" "kubectl delete pod x" --long
  _t "absolute path is wrapped" "wrapped|kubectl|-|/bin/kubectl delete pod x|delete|pod|x" "/bin/kubectl delete pod x" --long
  _t "redirection anywhere is wrapped" "wrapped|kubectl|-|kubectl delete pod x|delete|pod|x" "kubectl delete pod x 2>/dev/null" --long
  _t "from bash -c is wrapped" "wrapped|kubectl|-|kubectl delete pod x|delete|pod|x" "bash -c 'kubectl delete pod x'" --long
  # --- fail closed ------------------------------------------------------------------------------
  _t "unterminated quote" "UNPARSEABLE|unterminated double quote or substitution inside one|kubectl delete \"pod" "kubectl delete \"pod"
  _t "computed command word" "UNPARSEABLE|command word is computed at run time|\$K delete ns prod" "\$K delete ns prod"
  _t "computed command word from a substitution" "UNPARSEABLE|command word is computed at run time|\$(which kubectl) delete ns prod${NL}which|kubectl" "\$(which kubectl) delete ns prod"
  _t "empty input" "" ""
  # --- JSON -------------------------------------------------------------------------------------
  _j "json string with escapes" 0 "gh pr create --body \"a${NL}git commit\"" tool_input.command '{"tool_name":"Bash","tool_input":{"command":"gh pr create --body \"a\ngit commit\""}}'
  _j "json key inside a string is not a key" 0 "real" tool_input.command '{"tool_input":{"description":"\"command\": \"fake\"","command":"real"}}'
  _j "json unicode" 0 "é→" x '{"x":"é→"}'
  _j "json array is shell-quoted" 0 "'bash' '-lc' 'it'\\''s'" tool_input.command '{"tool_input":{"command":["bash","-lc","it'"'"'s"]}}'
  _j "json absent" 1 "" tool_input.command '{"tool_input":{}}'
  _j "json malformed" 2 "" tool_input.command '{"tool_input":{"command":"x"'
  _j "json top-level cwd" 0 "/repo" cwd '{"cwd":"/repo","tool_input":{"command":"x","cwd":"/other"}}'
  # --- prompt rules (v1.2.2: one reader for the hook and the lint) ---------------------------------
  _got=$(printf '%s\n' "# a comment naming prefix_rule(pattern = [\"no\"], decision = \"prompt\")" \
    "prefix_rule(pattern = ['gh', ['pr', \"run\"], 'merge'], decision = 'prompt')" \
    'prefix_rule(' '    pattern = ["kubectl", ["cordon", "drain"]],  # nested list' '    decision = "prompt",' \
    '    justification = "pattern = [\"not\", \"this\"]",' ')' \
    'prefix_rule(pattern = ["git", "status"])' 'prefix_rule(pattern = ["rm", "-rf"], decision = "forbidden")' | shseg_prompt_prefixes | tr '\n' '|')
  if [ "$_got" = "gh pr merge|gh run merge|kubectl cordon|kubectl drain|" ]; then _p=$((_p + 1)); else _f=$((_f + 1)); printf 'FAIL shseg_prompt_prefixes\n  got: %s\n' "$_got"; fi
  # --- names_tool ---------------------------------------------------------------------------------
  if shseg_names_tool kubectl "UNPARSEABLE	x	\$K; /usr/bin/kubectl delete" && ! shseg_names_tool kubectl "UNPARSEABLE	x	kubectl-foo"; then _p=$((_p + 1)); else _f=$((_f + 1)); echo "FAIL shseg_names_tool"; fi
  printf 'shell-segments self-test: %s passed, %s failed\n' "$_p" "$_f"
  [ "$_f" -eq 0 ]
}

case "${0##*/}" in
  shell-segments.sh)
    case "${1:-}" in
      --version) echo "shell-segments.sh v$SHSEG_VERSION" ;;
      --self-test) _shseg_self_test ;;
      --json-get) shseg_json_get "${2:-}" ;;
      -h|--help) sed -n '2,77p' "$0" ;;
      *)
        _shseg_long=""; _shseg_g=${SHSEG_GUARD:-}
        while :; do
          case "${1:-}" in
            --long) _shseg_long=--long; shift ;;
            --guard) _shseg_g=${2:-}; shift 2 ;;
            --guard=*) _shseg_g=${1#--guard=}; shift ;;
            *) break ;;
          esac
        done
        [ "${1:-}" = "--" ] && shift
        if [ $# -gt 0 ]; then shseg_segments $_shseg_long --guard "$_shseg_g" -- "$1"; else shseg_segments $_shseg_long --guard "$_shseg_g" -- "$(cat)"; fi ;;
    esac ;;
esac

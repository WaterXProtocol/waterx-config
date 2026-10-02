#!/bin/sh
# waterx-commons/harness/hooks/lib/shell-segments.sh v1.0.0
#
# A quote-aware shell command segmenter for agent hooks (STANDARD.md rule R2). Repos vendor this
# file unchanged as scripts/agent-hooks/lib/shell-segments.sh; keep the version line above intact.
#
# It turns the command string of a Bash tool call into the simple commands it would run, one per
# line, so a hook classifies parsed commands instead of grepping text:
#   - splits on ; && || | |& & ( ) and newlines OUTSIDE quotes; drops # comments;
#   - treats here-document bodies as data, except when a shell reads them (bash <<EOF);
#   - parses $( ), backticks, <( ) and >( ) (also inside double quotes and unquoted here-documents)
#     as separate commands, and leaves a placeholder ("$(...)", "<(...)") in the outer word, so text
#     inside a substitution never counts as an argument of the outer command;
#   - unwraps bash/sh/zsh/dash/ksh -c, eval, env (incl. -S), command, builtin, exec, nohup, time,
#     sudo, doas, nice, timeout, stdbuf, xargs, watch, direnv exec, leading NAME=value assignments,
#     reserved words (if/then/do/!/{ ...), and a path on the tool (/usr/local/bin/kubectl -> kubectl);
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
#
# How hooks use it (STANDARD.md rule R2):
#   ask hooks   FAIL CLOSED: ask when a parsed line matches, AND when an UNPARSEABLE line's raw text
#               names the tool; match --dry-run style exemptions against that line's own arguments.
#   block hooks FAIL OPEN: act only on a parsed line in command position; ignore UNPARSEABLE.
#
# Use as a library (POSIX sh, bash 3.2, dash; needs only awk — SHSEG_AWK_BIN picks another one):
#   . "$(dirname "$0")/lib/shell-segments.sh"
#   cmd=$(printf '%s' "$input" | shseg_json_get tool_input.command)   # 0 found, 1 absent, 2 bad JSON
#   shseg_segments "$cmd" | while IFS="$(printf '\t')" read -r tool a1 a2 rest; do ...; done
# or as a command:
#   shell-segments.sh [--long] [--] [COMMAND]    segment COMMAND, or stdin when absent
#   shell-segments.sh --json-get PATH            print the JSON value at PATH (stdin); arrays of
#                                                strings come back shell-quoted and space-joined
#   shell-segments.sh --self-test | --version
# A JSON value is decoded fully (\n, \", \uXXXX), so a multi-line command splits on its newlines;
# scraping it with sed leaves "\n" in the text and hides every command after the first line.

SHSEG_VERSION=1.0.0

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
function reset_seg() { NS = 0; SEG_REDIR = 0; SEG_HB = ""; SEG_HASH = 0; PEND_RT = 0 }
function parse(    t, ty, lastop) {
  reset_seg(); CASEN = 0; lastop = ""
  for (t = 1; t <= NT; t++) {
    ty = T_type[t]
    if (ty == "W") {
      if (PEND_RT) { PEND_RT = 0; continue }
      NS++; SV[NS] = T_val[t]; SR[NS] = T_raw[t]; SDY[NS] = T_dyn[t]; continue
    }
    if (ty == "R") { SEG_REDIR = 1; PEND_RT = 1; continue }
    if (ty == "RX") { SEG_REDIR = 1; continue }
    if (ty == "H") { SEG_REDIR = 1; SEG_HASH = 1; SEG_HB = SEG_HB T_val[t]; continue }
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
function emit(origin, tool, from, to,    j, line, why) {
  NA = 0; for (j = from; j <= to; j++) A[++NA] = SV[j]
  why = norm(tool)
  if (why != "") { unparseable(why, joinr(1, NS)); return }
  if (LONG) line = origin "\t" esc(tool) "\t" (GL == "" ? "-" : esc(GL)) "\t" esc(joinv(WSTART, NS)); else line = esc(tool)
  for (j = 1; j <= NO; j++) line = line "\t" esc(O[j])
  print line
}
function flush(    k, v, wr, t, hasc, kb) {
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
  WSTART = k
  while (k <= NS) {
    if (SDY[k]) { unparseable("command word is computed at run time", joinr(1, NS)); return }
    t = base(SV[k]); if (t != SV[k]) wr = 1
    if (t == "") return
    if (t == "env") {
      wr = 1; k++
      while (k <= NS) {
        v = SV[k]
        if (v == "--") { k++; break }
        if (v == "-u" || v == "-C" || v == "--unset" || v == "--chdir") { k += 2; continue }
        if (v == "-S" || v == "--split-string") { enqueue(joinv(k + 1, NS), CUR_DEPTH + 1); return }
        if (v ~ /^-S./) { enqueue(substr(v, 3) (k < NS ? " " joinv(k + 1, NS) : ""), CUR_DEPTH + 1); return }
        if (v ~ /^--split-string=/) { enqueue(substr(v, 16) (k < NS ? " " joinv(k + 1, NS) : ""), CUR_DEPTH + 1); return }
        if (v ~ /^-/ || is_assign(v)) { k++; continue }
        break
      }
      if (k > NS) { emit_self("env", WSTART, wr); return }
      continue
    }
    if (t == "command" || t == "builtin" || t == "nohup" || t == "exec") {
      if (t == "command" && (SV[k + 1] == "-v" || SV[k + 1] == "-V")) break
      wr = 1; k++
      while (k <= NS && SV[k] ~ /^-/) { if (t == "exec" && SV[k] == "-a") k++; k++ }
      if (k > NS) { emit_self(t, WSTART, wr); return }
      continue
    }
    if (t == "time") {
      wr = 1; k++
      while (k <= NS && SV[k] ~ /^-/) { if (SV[k] == "-o" || SV[k] == "-f") k++; k++ }
      continue
    }
    if (t == "sudo" || t == "doas") {
      wr = 1; k++
      while (k <= NS && SV[k] ~ /^-/) {
        v = SV[k]; k++
        if (v == "--") break
        if (v ~ /^-[ughpCDrtUTR]$/ || v ~ /^--(user|group|host|prompt|close-from|chdir|role|type|other-user|command-timeout|chroot)$/) k++
      }
      if (k > NS) { emit_self(t, WSTART, wr); return }
      continue
    }
    if (t == "nice") {
      wr = 1; k++
      while (k <= NS && SV[k] ~ /^-/) { if (SV[k] == "-n" || SV[k] == "--adjustment") k++; k++ }
      continue
    }
    if (t == "timeout") {
      wr = 1; k++
      while (k <= NS && SV[k] ~ /^-/) { if (SV[k] ~ /^(-s|-k|--signal|--kill-after)$/) k++; k++ }
      k++
      continue
    }
    if (t == "stdbuf") {
      wr = 1; k++
      while (k <= NS && SV[k] ~ /^-/) { if (SV[k] ~ /^-[ioe]$/) k++; k++ }
      continue
    }
    if (t == "xargs") {
      wr = 1; k++
      while (k <= NS && SV[k] ~ /^-/) { if (SV[k] ~ /^-[IELnPsda]$/) k++; k++ }
      if (k > NS) { emit_self("xargs", WSTART, wr); return }
      continue
    }
    if (t == "watch") {
      wr = 1; k++
      while (k <= NS && SV[k] ~ /^-/) { if (SV[k] == "-n" || SV[k] == "--interval") k++; k++ }
      if (k <= NS) enqueue(joinv(k, NS), CUR_DEPTH + 1)
      return
    }
    if (t == "direnv" && SV[k + 1] == "exec") { wr = 1; k += 3; continue }
    if (t == "eval") { if (k < NS) enqueue(joinv(k + 1, NS), CUR_DEPTH + 1); return }
    if (has(" bash sh zsh dash ksh ", t)) {
      hasc = 0; kb = k; k++
      while (k <= NS && (SV[k] ~ /^[-+]/)) {
        v = SV[k]; k++
        if (v == "--" || v == "-") break
        if (v ~ /^[-+][oO]$/ || v == "--rcfile" || v == "--init-file") { k++; continue }
        if (v ~ /^-[A-Za-z]*c[A-Za-z]*$/) hasc = 1
      }
      if (hasc) { if (k <= NS) enqueue(SV[k], CUR_DEPTH + 1); return }
      if (SEG_HASH && (k > NS)) { enqueue(SEG_HB, CUR_DEPTH + 1); return }
      k = kb; break
    }
    break
  }
  if (k > NS) return
  emit(wr ? "wrapped" : "plain", base(SV[k]), k + 1, NS)
}
function emit_self(t, from, wr) { emit(wr ? "wrapped" : "plain", t, from + 1, NS) }
BEGIN {
  SQ = sprintf("%c", 39); MAXDEPTH = 6; LONG = (mode == "long")
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
  NQ = 1; Q[1] = input; QD[1] = 0
  for (qi = 1; qi <= NQ; qi++) {
    if (qi > 64) { unparseable("more than 64 nested scripts", ""); break }
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

# shseg_segments [--long] COMMAND — print the simple commands in COMMAND (see the header).
shseg_segments() {
  _shseg_mode=short
  if [ "${1:-}" = "--long" ]; then _shseg_mode=long; shift; fi
  [ "${1:-}" = "--" ] && shift
  printf '%s' "${1:-}" | LC_ALL=C "${SHSEG_AWK_BIN:-awk}" -v mode="$_shseg_mode" "$SHSEG_AWK"
}

# shseg_json_get PATH — the JSON value at the dotted PATH (e.g. tool_input.command), from stdin.
# Exit 0 found (value printed without a trailing newline), 1 absent or null, 2 not valid JSON.
shseg_json_get() {
  LC_ALL=C "${SHSEG_AWK_BIN:-awk}" -v want="${1:-}" "$SHSEG_JSON_AWK"
}

# shseg_names_tool TOOL LINE — 0 when an UNPARSEABLE LINE's raw text names TOOL as a word
# (also as /path/TOOL), so an ask hook can fail closed on it.
shseg_names_tool() {
  printf '%s\n' "$2" | grep -Eq "(^|[^[:alnum:]_.-])(/[^[:space:]]*/)?$1([^[:alnum:]_.-]|\$)"
}

_shseg_self_test() {
  _p=0; _f=0
  _t() { # name expected-lines-with-|-for-TAB input [--long]
    if [ "${4:-}" = "--long" ]; then _got=$(shseg_segments --long "$3" | tr '\t' '|'); else _got=$(shseg_segments "$3" | tr '\t' '|'); fi
    if [ "$_got" = "$2" ]; then _p=$((_p + 1)); else _f=$((_f + 1)); printf 'FAIL %s\n  input:    %s\n  expected: %s\n  got:      %s\n' "$1" "$3" "$2" "$_got"; fi
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
      -h|--help) sed -n '2,51p' "$0" ;;
      *)
        _shseg_long=""
        if [ "${1:-}" = "--long" ]; then _shseg_long=--long; shift; fi
        [ "${1:-}" = "--" ] && shift
        if [ $# -gt 0 ]; then shseg_segments $_shseg_long "$1"; else shseg_segments $_shseg_long "$(cat)"; fi ;;
    esac ;;
esac

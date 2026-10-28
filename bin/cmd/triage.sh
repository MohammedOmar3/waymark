# waymark triage helpers + commands (sourced by bin/waymark; uses exit)
# Thin command files (status/inbox/dismiss/defer/handoff/commit.sh) set
# wm_tri_cmd and source this file. `waymark triage <cmd> ...` also works.
# Inbox candidate block (written by hooks, parsed here):
#   ## I-<id8>-<n> — <state>
#   - kind: failure | remember
#   - repo: <repo>
#   - time: <wm_now>
#   - command: <single line>
#   - exit: <code>
#   (blank) ```-fenced output lines / prompt text
# Non-terminal states: new gated deferred mandatory.  Terminal: dismissed,
# recorded <ID>.  Edits take lock "inbox" and rewrite via tmp file + mv.

wm_tri_die() { printf 'waymark %s: %s\n' "${wm_tri_cmd:-triage}" "$1" >&2; exit "${2:-2}"; }

# wm_tri_oneline <text> -> WM_L (no CR/LF, trimmed)
wm_tri_oneline() {
  local v="$1"
  v="${v//$'\r'/}"
  v="${v//$'\n'/ }"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  WM_L="$v"
}

# wm_tri_cand_file <layer> <I-id8-n> -> WM_CF ; exits 2 when unknown
wm_tri_cand_file() {
  local layer="$1" id="$2" id8 rest
  case "$id" in
    I-?*-[0-9]*) ;;
    *) wm_tri_die "bad candidate id: $id" ;;
  esac
  rest="${id#I-}"; id8="${rest%-*}"
  case "$id8$rest" in *[!A-Za-z0-9-]*) wm_tri_die "bad candidate id: $id" ;; esac
  WM_CF="$layer/inbox/$id8.md"
  [ -f "$WM_CF" ] || wm_tri_die "unknown candidate: $id"
  awk -v p="## $id " 'substr($0, 1, length(p)) == p { f = 1; exit } END { exit !f }' "$WM_CF" \
    || wm_tri_die "unknown candidate: $id"
}

# wm_tri_list_raw <file>: one line per candidate: ID<TAB>state<TAB>repo<TAB>first line
wm_tri_list_raw() {
  awk '
  function flush() { if (id != "") print id "\t" st "\t" repo "\t" first }
  { sub(/\r$/, "") }
  substr($0, 1, 5) == "## I-" {
    flush()
    r = substr($0, 4); sp = index(r, " ")
    id = (sp ? substr(r, 1, sp - 1) : r); st = (sp ? substr(r, sp + 1) : "")
    sub(/^[^A-Za-z]+/, "", st)
    repo = ""; first = ""; body = 0; fence = 0
    next
  }
  id == "" { next }
  body == 0 && !fence && $0 ~ /^- (kind|repo|time|command|exit):/ {
    if ($0 ~ /^- repo:/) { repo = substr($0, 8); sub(/^[ \t]+/, "", repo) }
    next
  }
  {
    if (first != "") next
    if ($0 ~ /^```/) { fence = 1; body = 1; next }
    if ($0 ~ /^[ \t]*$/) next
    body = 1
    first = $0; gsub(/\t/, " ", first)
  }
  END { flush() }' "$1"
}

# wm_tri_set_state <layer> <I-…> <state>
wm_tri_set_state() {
  local layer="$1" id="$2" state="$3" tmp
  wm_tri_cand_file "$layer" "$id"
  wm_lock inbox || wm_tri_die "could not take inbox lock" 3
  tmp="$WM_CF.tmp.$$"
  WM_ID="$id" WM_ST="$state" awk '
  BEGIN { p = "## " ENVIRON["WM_ID"] " "; cr = sprintf("%c", 13) }
  substr($0, 1, length(p)) == p && !done {
    c = ($0 ~ /\r$/) ? cr : ""
    print "## " ENVIRON["WM_ID"] " — " ENVIRON["WM_ST"] c; done = 1; next
  }
  { print }' "$WM_CF" > "$tmp" && mv -f "$tmp" "$WM_CF"
  local rc=$?
  rm -f "$tmp"
  wm_unlock inbox
  return $rc
}

wm_tri_session() { # -> WM_SES from $1 or env
  WM_SES="${1:-${WAYMARK_SESSION:-}}"
}

wm_tri_status() {
  local id="" st="" layer file tmp rc commit_rc
  [ $# -eq 2 ] || wm_tri_die "usage: waymark status <G-####> open|fixed|obsolete"
  id="$1"; st="$2"
  case "$id" in G-[0-9][0-9][0-9][0-9]*) ;; *) wm_tri_die "bad gotcha id: $id" ;; esac
  case "$id" in *[!0-9G-]*) wm_tri_die "bad gotcha id: $id" ;; esac
  case "$st" in open|fixed|obsolete) ;; *) wm_tri_die "bad status: $st (open|fixed|obsolete)" ;; esac
  layer="$(wm_layer_root)" || wm_tri_die "no layer found"
  file="$layer/gotchas.md"
  [ -f "$file" ] || wm_tri_die "unknown id: $id"
  wm_lock ids || wm_tri_die "could not take ids lock" 3
  tmp="$file.tmp.$$"
  WM_ID="$id" WM_ST="$st" awk '
  BEGIN { p = "## " ENVIRON["WM_ID"] " "; cr = sprintf("%c", 13) }
  {
    line = $0; sub(/\r$/, "", line)
    if (substr(line, 1, 3) == "## ") { inent = (substr(line, 1, length(p)) == p) ; if (inent) found = 1 }
    if (inent && !done && substr(line, 1, 13) == "- **Status:**") {
      c = ($0 ~ /\r$/) ? cr : ""
      print "- **Status:** " ENVIRON["WM_ST"] c; done = 1; next
    }
    print
  }
  END { if (!found) exit 3; if (!done) exit 4 }' "$file" > "$tmp"
  rc=$?
  if [ $rc -eq 0 ]; then mv -f "$tmp" "$file"; fi
  rm -f "$tmp"
  wm_unlock ids
  [ $rc -eq 0 ] || wm_tri_die "unknown id (or no Status line): $id"
  printf '%s %s\n' "$id" "$st"
  wm_commit "memory: $id status $st"
  commit_rc=$?
  case $commit_rc in
    0) exit 0 ;;
    2) printf 'waymark status: scan failed; change left uncommitted (see active/.scan-failed.log)\n' >&2; exit 2 ;;
    *) exit "$commit_rc" ;;
  esac
}

wm_tri_inbox() {
  local ses="" all=0 layer f line st w
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) ses="${2:-}"; shift 2 || shift ;;
      --session=*) ses="${1#--session=}"; shift ;;
      --all) all=1; shift ;;
      *) wm_tri_die "unknown argument: $1" 64 ;;
    esac
  done
  layer="$(wm_layer_root)" || wm_tri_die "no layer found"
  [ "$all" = 1 ] && ses="" || wm_tri_session "$ses"
  [ "$all" = 1 ] || ses="$WM_SES"
  if [ -n "$ses" ]; then set -- "$layer/inbox/$ses.md"; else set -- "$layer"/inbox/*.md; fi
  for f in "$@"; do
    [ -f "$f" ] || continue
    wm_tri_list_raw "$f" | while IFS= read -r line; do
      line="${line%$'\r'}"
      st="$(printf '%s' "$line" | cut -f2)"; w="${st%% *}"
      case "$w" in new|gated|deferred|mandatory) ;; *) continue ;; esac
      printf '%s\n' "$line" | awk -F'\t' '{ f = $4; if (length(f) > 100) f = substr(f, 1, 100) "..."; printf "%s  %s  %s  %s\n", $1, $2, $3, f }'
    done
  done
  exit 0
}

wm_tri_mark() { # <dismissed|deferred> <I-…>
  local layer
  [ $# -eq 2 ] && [ -n "$2" ] || wm_tri_die "usage: waymark ${wm_tri_cmd} <I-id8-n>"
  layer="$(wm_layer_root)" || wm_tri_die "no layer found"
  wm_tri_set_state "$layer" "$2" "$1" || wm_tri_die "could not update $2" 3
  printf '%s %s\n' "$2" "$1"
  exit 0
}

wm_tri_handoff() {
  local text="" ses="" layer have=0 f tmp rc
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) ses="${2:-}"; shift 2 || shift ;;
      --session=*) ses="${1#--session=}"; shift ;;
      *) if [ "$have" = 0 ]; then text="$1"; have=1; else text="$text $1"; fi; shift ;;
    esac
  done
  wm_tri_oneline "$text"; text="$WM_L"
  [ -n "$text" ] || wm_tri_die "usage: waymark handoff <text> [--session <id8>]"
  wm_tri_session "$ses"; ses="$WM_SES"
  [ -n "$ses" ] || wm_tri_die "no session (use --session <id8> or set WAYMARK_SESSION)"
  case "$ses" in *[!A-Za-z0-9]*) wm_tri_die "bad session id: $ses" ;; esac
  layer="$(wm_layer_root)" || wm_tri_die "no layer found"
  f=""
  for f in "$layer"/active/*--"$ses".md; do [ -f "$f" ] && break; f=""; done
  [ -n "$f" ] || wm_tri_die "no active file for session $ses"
  wm_lock "active-$ses" || wm_tri_die "could not take active lock" 3
  tmp="$f.tmp.$$"
  WM_TXT="$text" awk '
  { line = $0; sub(/\r$/, "", line) }
  substr(line, 1, 8) == "handoff:" && !done { print "handoff: " ENVIRON["WM_TXT"]; done = 1; next }
  { print }
  END { if (!done) print "handoff: " ENVIRON["WM_TXT"] }' "$f" > "$tmp" && mv -f "$tmp" "$f"
  rc=$?
  rm -f "$tmp"
  wm_unlock "active-$ses"
  [ $rc -eq 0 ] || wm_tri_die "could not write $f" 3
  printf 'handoff set for session %s\n' "$ses"
  exit 0
}

wm_tri_commit() {
  local msg="$*" rc
  [ -n "$msg" ] || wm_tri_die "usage: waymark commit <message>"
  wm_layer_root >/dev/null || wm_tri_die "no layer found"
  wm_commit "$msg"; rc=$?
  case $rc in
    0) printf 'ok\n'; exit 0 ;;
    2) printf 'waymark commit: scan failed; nothing committed (see active/.scan-failed.log)\n' >&2; exit 2 ;;
    3) printf 'waymark commit: git or lock failure\n' >&2; exit 3 ;;
    *) exit "$rc" ;;
  esac
}

# ---------------------------------------------------------------- dispatch --
if [ -z "${wm_tri_cmd:-}" ]; then
  wm_tri_cmd="${1:-}"; [ $# -gt 0 ] && shift
fi
case "$wm_tri_cmd" in
  status) wm_tri_status "$@" ;;
  inbox) wm_tri_inbox "$@" ;;
  dismiss) wm_tri_mark dismissed "$@" ;;
  defer) wm_tri_mark deferred "$@" ;;
  handoff) wm_tri_handoff "$@" ;;
  commit) wm_tri_commit "$@" ;;
  __lib) : ;;
  *) printf 'usage: waymark triage status|inbox|dismiss|defer|handoff|commit\n' >&2; exit 64 ;;
esac

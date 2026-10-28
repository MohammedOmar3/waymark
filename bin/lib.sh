#!/usr/bin/env bash
# waymark shared helpers. Source this file; do not execute it.
# Hot path for every hook: prefer builtins and parameter expansion over forks.
# Compatible with bash 3.2 (macOS /bin/bash) through 5.x. No eval, no heredocs.

# ---------------------------------------------------------------- time ----
if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 2 ]; }; then
  wm_now() { printf '%(%Y-%m-%dT%H:%M:%S)T\n' -1; }
  wm__now() { printf -v WM_NOW '%(%Y-%m-%dT%H:%M:%S)T' -1; }   # no subshell
  wm_today() { printf '%(%Y-%m-%d)T\n' -1; }
  wm__epoch() { printf '%(%s)T' -1; }
else
  wm_now() { date +%Y-%m-%dT%H:%M:%S; }
  wm__now() { WM_NOW="$(date +%Y-%m-%dT%H:%M:%S)"; }
  wm_today() { date +%Y-%m-%d; }
  wm__epoch() { date +%s; }
fi

# ---------------------------------------------------------------- paths ----
wm_config_home() { printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# wm_path <path> -> POSIX form (Windows drive/backslash paths from hook stdin).
wm_path() {
  local p="$1" bs='\'
  case "$p" in
    *"$bs"*|[A-Za-z]:*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -u -- "$p" 2>/dev/null && return 0
      fi
      p="${p//"$bs"//}"
      ;;
  esac
  printf '%s\n' "$p"
}

# ----------------------------------------------------------------- conf ----
# wm_conf_get <file> <key>
wm_conf_get() {
  wm__conf_get "$1" "$2" || return 1
  printf '%s\n' "$WM_CV"
}

# wm__conf_get <file> <key> -> WM_CV (no subshell; for hot paths)
wm__conf_get() {
  local line
  WM_CV=""
  [ -f "$1" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "$2="*) WM_CV="${line#*=}"; return 0 ;;
    esac
  done < "$1"
  return 1
}

# wm_conf_set <file> <key> <value>  (replace first match, else append)
wm_conf_set() {
  local f="$1" k="$2" v="$3" line done_=0 tmp
  tmp="$f.tmp.$$"
  : > "$tmp" || return 1
  if [ -f "$f" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      case "$line" in
        "$k="*) if [ "$done_" = 0 ]; then printf '%s=%s\n' "$k" "$v" >> "$tmp"; done_=1; fi ;;
        *) printf '%s\n' "$line" >> "$tmp" ;;
      esac
    done < "$f"
  fi
  [ "$done_" = 1 ] || printf '%s=%s\n' "$k" "$v" >> "$tmp"
  mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

# wm_layer_root -> prints layer path; exit 1 if no valid layer.
wm_layer_root() {
  wm__layer_find || return 1
  printf '%s\n' "$WM_LAYER"
}

# wm__layer_find -> WM_LAYER (no subshell unless a Windows path needs converting)
wm__layer_find() {
  local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" c
  for c in "${WAYMARK_ROOT:-}" "__CONF__" "$cfg/waymark"; do
    if [ "$c" = "__CONF__" ]; then
      wm__conf_get "$cfg/waymark.conf" root || continue
      c="$WM_CV"
    fi
    case "$c" in *'\'*|[A-Za-z]:*) c="$(wm_path "$c")" ;; esac
    if [ -n "$c" ] && [ -f "$c/layer.conf" ]; then
      WM_LAYER="$c"
      return 0
    fi
  done
  return 1
}

# ----------------------------------------------------------------- repo ----
# wm_repo_name [dir] -> spec §6: basename of the parent of the absolute git
# common dir (so linked worktrees map to the main repo); if that is unusable
# (e.g. separate git dir, bare repo) fall back to basename of the toplevel;
# "none" outside git. Uses git -C, so no cd and no CDPATH exposure.
wm_repo_name() {
  wm__repo_name "$@"
  printf '%s\n' "$WM_RN"
}

# wm__repo_name [dir] -> WM_RN (one git spawn, no extra subshell)
wm__repo_name() {
  local dir="${1:-.}" common parent top
  common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  common="${common%/}"
  case "$common" in
    */.git)
      parent="${common%/.git}"
      if [ -n "${parent##*/}" ]; then WM_RN="${parent##*/}"; return 0; fi
      ;;
  esac
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
  top="${top%/}"
  if [ -n "${top##*/}" ]; then WM_RN="${top##*/}"; return 0; fi
  WM_RN=none
}

# Awk JSON scanner (run under LC_ALL=C). WM_K is a newline-separated list of
# dotted key paths.
#   WM_MODE=val : for each scalar at a wanted path print "<path>\t<t><raw>"
#                 (t = s string / l literal); first occurrence wins; stops once
#                 every wanted path was found. Strings stay escaped.
#   WM_MODE=keys: print each key of the object at any wanted path.
WM__AWK='
function jstr(   j, c) {
  j = i + 1
  while (j <= len) {
    c = substr(buf, j, 1)
    if (c == "\\") { j += 2; continue }
    if (c == "\"") break
    j++
  }
  sval = substr(buf, i + 1, j - i - 1)
  i = j + 1
}
function path(n,   s, m) {
  if (n < 1) return ""
  s = key[1]
  for (m = 2; m <= n; m++) s = s "." key[m]
  return s
}
{ buf = buf $0 " " }
END {
  len = length(buf); i = 1; d = 0
  mode = ENVIRON["WM_MODE"]
  n = split(ENVIRON["WM_K"], arr, "\n"); left = 0
  for (m = 1; m <= n; m++) if (arr[m] != "") { want[arr[m]] = 1; left++ }
  while (i <= len) {
    c = substr(buf, i, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r" || c == ":") { i++; continue }
    if (c == ",") { if (typ[d] == "o") ek[d] = 1; else key[d]++; i++; continue }
    if (c == "{") { d++; typ[d] = "o"; ek[d] = 1; key[d] = ""; i++; continue }
    if (c == "[") { d++; typ[d] = "a"; key[d] = 0; i++; continue }
    if (c == "}" || c == "]") { d--; i++; continue }
    if (c == "\"") {
      jstr()
      if (typ[d] == "o" && ek[d]) {
        if (mode == "keys" && (path(d - 1) in want)) print sval
        key[d] = sval; ek[d] = 0
      } else if (mode == "val") {
        p = path(d)
        if ((p in want) && !(p in seen)) { print p "\ts" sval; seen[p] = 1; if (--left == 0) exit }
      }
      continue
    }
    j = i
    while (j <= len && index(",}] \t\r\n", substr(buf, j, 1)) == 0) j++
    lit = substr(buf, i, j - i); i = j
    if (mode == "val") {
      p = path(d)
      if ((p in want) && !(p in seen)) { print p "\tl" lit; seen[p] = 1; if (--left == 0) exit }
    }
  }
}'

# wm_repo_tags [dir] -> sorted unique tags from package.json deps via layer tags.conf
wm_repo_tags() {
  wm__repo_tags "$@"
  [ -z "$WM_TG" ] || printf '%s\n' "$WM_TG"
}

# wm__repo_tags [dir] -> WM_TG (space-separated; empty when none). Spawns one
# awk (reads package.json directly); dedupe and sort are done in bash.
wm__repo_tags() {
  local IFS=' ' dir="${1:-.}" layer names n line g tag i j
  local -a arr=()
  WM_TG=""
  [ -f "$dir/package.json" ] || return 0
  wm__layer_find || return 0
  layer="$WM_LAYER"
  [ -f "$layer/tags.conf" ] || return 0
  names="$(LC_ALL=C WM_MODE=keys WM_K=$'dependencies\ndevDependencies' awk "$WM__AWK" "$dir/package.json")"
  while [ -n "$names" ]; do
    case "$names" in *$'\n'*) n="${names%%$'\n'*}"; names="${names#*$'\n'}" ;; *) n="$names"; names="" ;; esac
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      case "$line" in ''|'#'*) continue ;; esac
      g="${line%%=*}"; tag="${line#*=}"
      # shellcheck disable=SC2053
      if [[ $n == $g ]]; then
        for j in ${arr[@]+"${arr[@]}"}; do [ "$j" = "$tag" ] && continue 2; done
        i=${#arr[@]}
        while [ "$i" -gt 0 ] && [[ ${arr[$((i - 1))]} > $tag ]]; do arr[$i]="${arr[$((i - 1))]}"; i=$((i - 1)); done
        arr[$i]="$tag"
        break
      fi
    done < "$layer/tags.conf"
  done
  [ ${#arr[@]} -gt 0 ] || return 0
  WM_TG="${arr[*]}"
}

# ----------------------------------------------------------------- json ----
# Append the UTF-8 byte for value $1 (0-255) to WM_U.
wm__byte() {
  local o
  printf -v o '%03o' "$1"
  printf -v o "\\$o"
  WM_U="$WM_U$o"
}

# wm__unescape <raw-json-string-body> -> WM_U
wm__unescape() {
  local s="$1" rest c hex cp
  WM_U=""
  while :; do
    case "$s" in
      *\\*) ;;
      *) WM_U="$WM_U$s"; break ;;
    esac
    WM_U="$WM_U${s%%\\*}"
    rest="${s#*\\}"
    c="${rest:0:1}"
    rest="${rest:1}"
    case "$c" in
      n) WM_U="$WM_U"$'\n' ;;
      t) WM_U="$WM_U"$'\t' ;;
      r) WM_U="$WM_U"$'\r' ;;
      b) WM_U="$WM_U"$'\b' ;;
      f) WM_U="$WM_U"$'\f' ;;
      u)
        hex="${rest:0:4}"
        case "$hex" in
          *[!0-9a-fA-F]*|'') WM_U="${WM_U}u" ;;
          *)
            rest="${rest:4}"
            cp=$((16#$hex))
            if [ "$cp" -eq 0 ]; then :
            elif [ "$cp" -lt 128 ]; then wm__byte "$cp"
            elif [ "$cp" -lt 2048 ]; then
              wm__byte $((192 | (cp >> 6))); wm__byte $((128 | (cp & 63)))
            else
              wm__byte $((224 | (cp >> 12))); wm__byte $((128 | ((cp >> 6) & 63))); wm__byte $((128 | (cp & 63)))
            fi
            ;;
        esac
        ;;
      *) WM_U="$WM_U$c" ;;   # \" \\ \/ and anything unknown
    esac
    s="$rest"
  done
}

# wm__san <key> -> WM_SAN : key made safe for a variable name (non [A-Za-z0-9_] -> _)
wm__san() {
  local k="$1" out="" c
  case "$k" in
    *[!A-Za-z0-9_]*)
      while [ -n "$k" ]; do
        c="${k:0:1}"; k="${k:1}"
        case "$c" in [A-Za-z0-9_]) out="$out$c" ;; *) out="${out}_" ;; esac
      done
      WM_SAN="$out" ;;
    *) WM_SAN="$k" ;;
  esac
}

# wm__json_scan <json> <newline-separated dotted keys> -> WM_JOUT
# One awk spawn; awk runs byte-wise (LC_ALL=C) so the scan is linear.
wm__json_scan() {
  local j="$1"
  case "$j" in *$'\n'*) j="${j//$'\n'/ }" ;; esac
  WM_JOUT="$(printf '%s' "$j" | LC_ALL=C WM_MODE=val WM_K="$2" awk "$WM__AWK")"
}

# wm_json_read <json> <prefix> <key>...
# Sets <prefix>_<sanitized key> for each key (dots -> _), empty when absent or
# null, and <prefix>__missing (space-separated absent keys). One awk spawn total.
wm_json_read() {
  local json="$1" prefix="$2" k keys=""
  shift 2
  for k in "$@"; do keys="$keys$k"$'\n'; done
  wm__json_scan "$json" "$keys"
  wm__json_assign "$prefix" "$@"
}

# wm_json_read_stdin <prefix> <key>...  Same as wm_json_read but the awk scanner
# reads the JSON straight from stdin: no printf pipeline, no copy of a large
# payload through a shell variable. Consumes stdin.
wm_json_read_stdin() {
  local prefix="$1" k keys=""
  shift
  for k in "$@"; do keys="$keys$k"$'\n'; done
  WM_JOUT="$(LC_ALL=C WM_MODE=val WM_K="$keys" awk "$WM__AWK")"
  wm__json_assign "$prefix" "$@"
}

# wm__json_assign <prefix> <key>... : turn $WM_JOUT into variables
wm__json_assign() {
  local prefix="$1" k out line key rest t v found=$'\n' missing=""
  shift
  for k in "$@"; do
    wm__san "$k"
    printf -v "${prefix}_$WM_SAN" '%s' ""
  done
  out="$WM_JOUT"
  while [ -n "$out" ]; do
    case "$out" in *$'\n'*) line="${out%%$'\n'*}"; out="${out#*$'\n'}" ;; *) line="$out"; out="" ;; esac
    key="${line%%$'\t'*}"; rest="${line#*$'\t'}"
    t="${rest:0:1}"; v="${rest:1}"
    if [ "$t" = s ]; then wm__unescape "$v"; v="$WM_U"
    elif [ "$v" = null ]; then continue; fi
    wm__san "$key"
    printf -v "${prefix}_$WM_SAN" '%s' "$v"
    found="$found$key"$'\n'
  done
  for k in "$@"; do
    case "$found" in *$'\n'"$k"$'\n'*) ;; *) missing="$missing $k" ;; esac
  done
  printf -v "${prefix}__missing" '%s' "${missing# }"
  return 0
}

# wm__json_get <json> <dotted.key> -> WM_JT (s|l) and WM_JV (raw); rc 1 if absent
wm__json_get() {
  local rest
  wm__json_scan "$1" "$2"
  [ -n "$WM_JOUT" ] || return 1
  rest="${WM_JOUT#*$'\t'}"
  WM_JT="${rest:0:1}"
  WM_JV="${rest:1}"
}

wm_json_str() {
  wm__json_get "$1" "$2" || return 1
  if [ "$WM_JT" = s ]; then
    wm__unescape "$WM_JV"
    printf '%s\n' "$WM_U"
  else
    case "$WM_JV" in
      true|false|-[0-9]*|[0-9]*) printf '%s\n' "$WM_JV" ;;
      *) return 1 ;;   # null, objects, junk: print nothing
    esac
  fi
}

wm_json_bool() {
  wm__json_get "$1" "$2" || return 1
  [ "$WM_JT" = l ] || return 1
  case "$WM_JV" in true|false) printf '%s\n' "$WM_JV" ;; *) return 1 ;; esac
}

wm_json_num() {
  wm__json_get "$1" "$2" || return 1
  [ "$WM_JT" = l ] || return 1
  case "$WM_JV" in -|*[!0-9eE.+-]*|'') return 1 ;; esac
  printf '%s\n' "$WM_JV"
}

# wm__escape <string> -> WM_E
wm__escape() {
  local s="$1" bs='\' dq='"' n o ch u
  s="${s//"$bs"/"$bs$bs"}"
  s="${s//"$dq"/"$bs$dq"}"
  s="${s//$'\n'/"${bs}n"}"
  s="${s//$'\r'/"${bs}r"}"
  s="${s//$'\t'/"${bs}t"}"
  s="${s//$'\b'/"${bs}b"}"
  s="${s//$'\f'/"${bs}f"}"
  case "$s" in
    *[[:cntrl:]]*)
      for n in 1 2 3 4 5 6 7 11 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
        printf -v o '%03o' "$n"
        printf -v ch "\\$o"
        printf -v u '\\u%04x' "$n"
        s="${s//"$ch"/"$u"}"
      done
      ;;
  esac
  WM_E="$s"
}

wm_json_escape() {
  wm__escape "$1"
  printf '%s\n' "$WM_E"
}

# ----------------------------------------------------------- hook guard ----
# Reusable by every hook script. Contract: a hook exits 0 and prints valid JSON
# or nothing, whatever a sourced file (e.g. a stale layer copy of this lib) does.
#   . "$plugin/bin/lib.sh"; wm_hook_guard <EventName>      # first thing
#   wm_source_layer_lib "$layer" "$plugin/bin/lib.sh"      # instead of a bare `.`
# Hooks that print set WM_HOOK_EMITTED=1 (wm__out does it); on any exit without
# output, the EXIT trap prints a minimal context for SessionStart only (other
# events must stay silent) and forces exit 0. WM_HOOK_ID is shown in that text.
: "${WM_HOOK_EMITTED:=0}"


wm_hook_guard() {
  WM_HOOK_EVENT="$1"
  trap wm__hook_exit EXIT
}

wm__hook_exit() {
  if [ "$WM_HOOK_EMITTED" != 1 ] && [ "${WM_HOOK_EVENT:-}" = SessionStart ]; then
    wm__m="{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"waymark: session-start hit an error; session: ${WM_HOOK_ID:-unknown0}\"}}"
    # fd 8 = stdout saved before sourcing untrusted files (an `exit` inside a
    # redirected `.` would otherwise leave stdout pointing at /dev/null)
    { printf '%s\n' "$wm__m" >&8; } 2>/dev/null || printf '%s\n' "$wm__m"
  fi
  exit 0
}

# wm_source_layer_lib <layer> <plugin-lib>: source <layer>/bin/lib.sh with all output
# discarded, undo any set -e/-u it left behind, re-arm the guard, and fall back
# to the plugin's own lib when the copy lacks a function hooks rely on.
wm_source_layer_lib() {
  local f="$1/bin/lib.sh" fn
  [ -f "$f" ] || return 0
  exec 8>&1
  . "$f" >/dev/null 2>&1
  set +eu
  exec 8>&-
  trap wm__hook_exit EXIT
  for fn in wm__layer_find wm__repo_name wm__repo_tags wm__now wm_json_read_stdin wm_emit_context wm_path; do
    if ! declare -F "$fn" >/dev/null 2>&1; then
      . "$2" >/dev/null 2>&1
      break
    fi
  done
  return 0
}

# ----------------------------------------------------------------- emit ----
# Hook output goes through cat when available (EPIPE on Git Bash, superpowers #1612); kept on purpose.
wm__out() {
  WM_HOOK_EMITTED=1
  if command -v cat >/dev/null 2>&1; then printf '%s\n' "$1" | cat; else printf '%s\n' "$1"; fi
}

wm_emit_context() {
  wm__escape "$1"; local ev="$WM_E"
  wm__escape "$2"
  wm__out "{\"hookSpecificOutput\":{\"hookEventName\":\"$ev\",\"additionalContext\":\"$WM_E\"}}"
}

wm_emit_block() {
  wm__escape "$1"
  wm__out "{\"decision\":\"block\",\"reason\":\"$WM_E\"}"
}

wm_emit_deny() {
  wm__escape "$1"
  wm__out "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$WM_E\"}}"
}

# ---------------------------------------------------------------- locks ----
# wm_lock <name>: mkdir lock, 50 x 0.1s retries, stale after 30s. rc 1 on give-up.
wm_lock() {
  local layer d i mt now st
  layer="$(wm_layer_root)" || return 1
  mkdir -p "$layer/.locks" 2>/dev/null || return 1
  d="$layer/.locks/$1"
  for i in $(seq 1 50); do
    if mkdir "$d" 2>/dev/null; then return 0; fi
    mt="$(wm__mtime "$d")"
    if [ -n "$mt" ]; then
      now="$(wm__epoch)"
      if [ $((now - mt)) -gt 30 ]; then
        # Steal atomically: rename (only one racer wins), re-check what we
        # actually moved, never treat removal as acquisition; loop to mkdir.
        st="$d.stale.$RANDOM$RANDOM"
        if mv "$d" "$st" 2>/dev/null; then
          mt="$(wm__mtime "$st")"
          if [ -n "$mt" ] && [ $((now - mt)) -le 30 ]; then
            # raced: we moved a lock someone just took; put it back if we can
            mv "$st" "$d" 2>/dev/null || rm -rf "$st" 2>/dev/null
          else
            rm -rf "$st" 2>/dev/null
          fi
        fi
        continue
      fi
    fi
    sleep 0.1
  done
  return 1
}

wm__mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

wm_unlock() {
  local layer
  layer="$(wm_layer_root)" || return 1
  rmdir "$layer/.locks/$1" 2>/dev/null
  return 0
}

# --------------------------------------------------------------- commit ----
# wm_commit <message>: 0 ok/no-op, 2 scan failed or scanner missing, 3 git failure.
wm_commit() {
  local layer log try
  layer="$(wm_layer_root)" || return 1
  [ -n "$(git -C "$layer" status --porcelain 2>/dev/null)" ] || return 0
  log="$layer/active/.scan-failed.log"
  mkdir -p "$layer/active" 2>/dev/null
  if [ ! -f "$layer/bin/waymark" ]; then
    printf 'scanner missing: %s/bin/waymark\n' "$layer" > "$log"
    return 2
  fi
  if ! (cd "$layer" && bash "$layer/bin/waymark" scan --root "$layer") > "$log" 2>&1; then
    return 2
  fi
  for try in 0 1 2 3 4 5; do
    if [ -e "$layer/.git/index.lock" ]; then
      [ "$try" -lt 5 ] && sleep 0.2
      continue
    fi
    if git -C "$layer" add -A >/dev/null 2>&1 && git -C "$layer" commit -q -m "$1" >/dev/null 2>&1; then
      rm -f "$log"
      return 0
    fi
    # a concurrent commit may already have taken our changes
    [ -n "$(git -C "$layer" status --porcelain 2>/dev/null)" ] || { rm -f "$log"; return 0; }
    if [ ! -e "$layer/.git/index.lock" ] && [ "$try" -ge 2 ]; then return 3; fi
    [ "$try" -lt 5 ] && sleep 0.2
  done
  return 3
}

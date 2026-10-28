#!/usr/bin/env bash
# waymark shared helpers. Source this file; do not execute it.
# Hot path for every hook: prefer builtins and parameter expansion over forks.
# Compatible with bash 3.2 (macOS /bin/bash) through 5.x. No eval, no heredocs.

# ---------------------------------------------------------------- time ----
if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 2 ]; }; then
  wm_now() { printf '%(%Y-%m-%dT%H:%M:%S)T\n' -1; }
  wm_today() { printf '%(%Y-%m-%d)T\n' -1; }
  wm__epoch() { printf '%(%s)T' -1; }
else
  wm_now() { date +%Y-%m-%dT%H:%M:%S; }
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
  local line
  [ -f "$1" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "$2="*) printf '%s\n' "${line#*=}"; return 0 ;;
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
  mv -f "$tmp" "$f"
}

# wm_layer_root -> prints layer path; exit 1 if no valid layer.
wm_layer_root() {
  local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" c r
  for c in "${WAYMARK_ROOT:-}" "__CONF__" "$cfg/waymark"; do
    if [ "$c" = "__CONF__" ]; then
      r="$(wm_conf_get "$cfg/waymark.conf" root)" || continue
      c="$(wm_path "$r")"
    fi
    if [ -n "$c" ] && [ -f "$c/layer.conf" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

# ----------------------------------------------------------------- repo ----
# wm_repo_name [dir] -> basename of the main worktree's root; "none" outside git.
wm_repo_name() {
  local common
  common="$(cd "${1:-.}" 2>/dev/null && c="$(git rev-parse --git-common-dir 2>/dev/null)" && cd "$c" 2>/dev/null && pwd)" || { printf 'none\n'; return 0; }
  [ -n "$common" ] || { printf 'none\n'; return 0; }
  common="${common%/}"
  case "$common" in
    */.git) common="${common%/.git}" ;;
    *.git) common="${common%.git}" ;;
  esac
  printf '%s\n' "${common##*/}"
}

# Awk JSON scanner. WM_MODE=val: print "s<raw string>" or "l<literal>" for the
# value at dotted path WM_K (exit 1 if absent). WM_MODE=keys: print each key of
# the object at path WM_K. Strings are returned still escaped.
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
{ buf = buf $0 "\n" }
END {
  len = length(buf); i = 1; d = 0; found = 0
  mode = ENVIRON["WM_MODE"]; t = ENVIRON["WM_K"]
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
        if (mode == "keys" && path(d - 1) == t) print sval
        key[d] = sval; ek[d] = 0
      } else if (mode == "val" && path(d) == t) { print "s" sval; found = 1; exit }
      continue
    }
    j = i
    while (j <= len && index(",}] \t\r\n", substr(buf, j, 1)) == 0) j++
    lit = substr(buf, i, j - i); i = j
    if (mode == "val" && path(d) == t) { print "l" lit; found = 1; exit }
  }
  if (mode == "keys") exit 0
  exit (found ? 0 : 1)
}'

# wm_repo_tags [dir] -> sorted unique tags from package.json deps via layer tags.conf
wm_repo_tags() {
  local dir="${1:-.}" layer pkg names n line g tag tags="" t
  [ -f "$dir/package.json" ] || return 0
  layer="$(wm_layer_root)" || return 0
  [ -f "$layer/tags.conf" ] || return 0
  pkg="$(<"$dir/package.json")"
  names="$(printf '%s' "$pkg" | WM_MODE=keys WM_K=dependencies awk "$WM__AWK"
           printf '%s' "$pkg" | WM_MODE=keys WM_K=devDependencies awk "$WM__AWK")"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      case "$line" in ''|'#'*) continue ;; esac
      g="${line%%=*}"; tag="${line#*=}"
      # shellcheck disable=SC2053
      if [[ $n == $g ]]; then tags="$tags$tag"$'\n'; break; fi
    done < "$layer/tags.conf"
  done <<EOT
$names
EOT
  [ -n "$tags" ] || return 0
  tags="$(printf '%s' "$tags" | sort -u)"
  t="${tags//$'\n'/ }"
  printf '%s\n' "$t"
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

# wm__json_get <json> <dotted.key> -> WM_JT (s|l) and WM_JV (raw); rc 1 if absent
wm__json_get() {
  local out
  out="$(printf '%s' "$1" | WM_MODE=val WM_K="$2" awk "$WM__AWK")" || return 1
  [ -n "$out" ] || return 1
  WM_JT="${out:0:1}"
  WM_JV="${out:1}"
}

wm_json_str() {
  wm__json_get "$1" "$2" || return 1
  if [ "$WM_JT" = s ]; then
    wm__unescape "$WM_JV"
    printf '%s\n' "$WM_U"
  else
    case "$WM_JV" in null|true|false|-[0-9]*|[0-9]*) printf '%s\n' "$WM_JV" ;; *) return 1 ;; esac
    [ "$WM_JV" != null ] || return 1
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

# ----------------------------------------------------------------- emit ----
# Hook output goes through cat when available (EPIPE-safe), else plain printf.
wm__out() {
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
  local layer d i mt now
  layer="$(wm_layer_root)" || return 1
  mkdir -p "$layer/.locks" 2>/dev/null || return 1
  d="$layer/.locks/$1"
  for i in $(seq 1 50); do
    if mkdir "$d" 2>/dev/null; then return 0; fi
    mt="$(stat -c %Y "$d" 2>/dev/null || stat -f %m "$d" 2>/dev/null)"
    if [ -n "$mt" ]; then
      now="$(wm__epoch)"
      if [ $((now - mt)) -gt 30 ]; then rmdir "$d" 2>/dev/null || rm -rf "$d" 2>/dev/null; continue; fi
    fi
    sleep 0.1
  done
  return 1
}

wm_unlock() {
  local layer
  layer="$(wm_layer_root)" || return 1
  rmdir "$layer/.locks/$1" 2>/dev/null
  return 0
}

# --------------------------------------------------------------- commit ----
# wm_commit <message>: 0 ok/no-op, 2 scan failed, 3 git failure.
wm_commit() {
  local layer log try
  layer="$(wm_layer_root)" || return 1
  [ -n "$(git -C "$layer" status --porcelain 2>/dev/null)" ] || return 0
  log="$layer/active/.scan-failed.log"
  if [ -f "$layer/bin/waymark" ]; then
    mkdir -p "$layer/active" 2>/dev/null
    if ! (cd "$layer" && bash "$layer/bin/waymark" scan) > "$log" 2>&1; then
      return 2
    fi
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
    [ -e "$layer/.git/index.lock" ] || return 3
    [ "$try" -lt 5 ] && sleep 0.2
  done
  return 3
}

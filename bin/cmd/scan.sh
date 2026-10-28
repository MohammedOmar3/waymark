# waymark scan [--root <dir>]  (sourced by bin/waymark; uses exit)
# Patterns are written with single-character classes ([s]k-) so this file
# does not match its own rules. POSIX ERE only; bash 3.2 compatible.
# Findings never echo the matched value: it is replaced by [REDACTED].

wm_scan_root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) wm_scan_root="${2:-}"; shift 2 || shift ;;
    --root=*) wm_scan_root="${1#--root=}"; shift ;;
    *) printf 'waymark scan: unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done
if [ -z "$wm_scan_root" ]; then
  wm_scan_root="$(wm_layer_root)" || { printf 'waymark scan: no layer found\n' >&2; exit 2; }
fi
case "$wm_scan_root" in *'\'*|[A-Za-z]:*) wm_scan_root="$(wm_path "$wm_scan_root")" ;; esac
[ -d "$wm_scan_root" ] || { printf 'waymark scan: not a directory: %s\n' "$wm_scan_root" >&2; exit 2; }
cd "$wm_scan_root" || exit 2

wm_scan_found=0
wm_cur_key=""; wm_cur_name=""; wm_cur_file=""; wm_cur_line=""
wm_cur_vals=()

wm_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Emit the pending finding with every collected value redacted.
wm_scan_flush() {
  [ -n "$wm_cur_key" ] || return 0
  local t v
  t="$(sed -n "${wm_cur_line}p" "$wm_cur_file")"
  t="${t%$'\r'}"
  for v in ${wm_cur_vals[@]+"${wm_cur_vals[@]}"}; do
    [ -n "$v" ] && t="${t//"$v"/[REDACTED]}"
  done
  t="${t#"${t%%[![:space:]]*}"}"
  [ "${#t}" -gt 120 ] && t="${t:0:120}..."
  printf '%s:%s  [%s]  %s\n' "$wm_cur_file" "$wm_cur_line" "$wm_cur_name" "$t"
  wm_scan_found=1
  wm_cur_key=""; wm_cur_vals=()
}

# wm_scan_hit <file> <line> <name> <secret-text-to-redact>
wm_scan_hit() {
  local key="$1:$2:$3"
  if [ "$key" != "$wm_cur_key" ]; then
    wm_scan_flush
    wm_cur_key="$key"; wm_cur_file="$1"; wm_cur_line="$2"; wm_cur_name="$3"
    wm_cur_vals=()
  fi
  wm_cur_vals+=("$4")
}

# File list: *.md *.conf *.tsv anywhere, plus everything under bin/.
wm_scan_files=()
while IFS= read -r wm_f; do
  wm_scan_files+=("${wm_f#./}")
done < <(find . \( -name .git -o -name inbox -o -name .view \) -prune -o -type f \
  \( -name '*.md' -o -name '*.conf' -o -name '*.tsv' -o -path './bin/*' \) \
  ! -name '*.log' -print 2>/dev/null | sort)

if [ "${#wm_scan_files[@]}" -gt 0 ]; then
  # name|regex  (matched text is redacted)
  wm_scan_rules=(
    'sk key|(^|[^A-Za-z0-9_])[s]k-[A-Za-z0-9_-]{20,}'
    'sk_live key|[s]k_live_[A-Za-z0-9]{16,}'
    'github token|[g]h[pousr]_[A-Za-z0-9]{36}'
    'github pat|[g]ithub_pat_[A-Za-z0-9_]{40,}'
    'aws access key|(^|[^A-Za-z0-9])(A[K]IA|A[S]IA)[A-Z0-9]{16}([^A-Za-z0-9]|$)'
    'private key block|-----BEGIN [A-Z ]*PRIVATE[ ]KEY-----'
    'jwt|e[y]J[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}'
    'slack token|[x]ox[abeoprs]-[A-Za-z0-9-]{10,}'
    'url credentials|[a-z][a-z0-9+.-]*[:]//[^/[:space:]:@]+:[^/[:space:]@]+@'
  )
  for wm_rule in "${wm_scan_rules[@]}"; do
    wm_name="${wm_rule%%|*}"; wm_re="${wm_rule#*|}"
    while IFS= read -r wm_hit; do
      [ -n "$wm_hit" ] || continue
      wm_hr="${wm_hit#*:}"
      wm_scan_hit "${wm_hit%%:*}" "${wm_hr%%:*}" "$wm_name" "${wm_hr#*:}"
    done < <(grep -HnIoE -e "$wm_re" -- "${wm_scan_files[@]}" 2>/dev/null)
    wm_scan_flush
  done

  # Credential assignment: whole-word key, then a quoted literal (>=6 chars)
  # or an unquoted value (>=8 chars, letter and digit, not followed by ( [ .).
  wm_key_re='(^|[^A-Za-z0-9])([p]assword|[p]asswd|[p]wd|[s]ecret|[t]oken|[a]pi[_-]?[k]ey|[a]ccess[_-]?[k]ey|[c]lient[_-]?[s]ecret)[[:space:]]*[:=][[:space:]]*.*'
  while IFS= read -r wm_hit; do
    [ -n "$wm_hit" ] || continue
    wm_hr="${wm_hit#*:}"
    wm_hf="${wm_hit%%:*}"; wm_hl="${wm_hr%%:*}"; wm_rest="${wm_hr#*:}"
    wm_rest="${wm_rest#*[:=]}"
    wm_rest="${wm_rest#"${wm_rest%%[![:space:]]*}"}"
    wm_val=""
    case "$wm_rest" in
      \"*|\'*)
        wm_q="${wm_rest:0:1}"; wm_body="${wm_rest:1}"
        wm_in="${wm_body%%"$wm_q"*}"
        if [ "$wm_in" != "$wm_body" ] && [ "${#wm_in}" -ge 6 ]; then wm_val="$wm_in"; fi
        ;;
      *)
        wm_v="$(printf '%s' "$wm_rest" | sed 's/^\([A-Za-z0-9_+\/=~-]*\).*/\1/')"
        wm_next="${wm_rest:${#wm_v}:1}"
        if [ "${#wm_v}" -ge 8 ]; then
          case "$wm_v" in *[0-9]*) case "$wm_v" in *[A-Za-z]*)
            case "$wm_next" in '('|'['|'.') ;; *) wm_val="$wm_v" ;; esac
          ;; esac ;; esac
        fi
        ;;
    esac
    [ -n "$wm_val" ] && wm_scan_hit "$wm_hf" "$wm_hl" "secret assignment" "$wm_val"
  done < <(grep -HnIiE -e "$wm_key_re" -- "${wm_scan_files[@]}" 2>/dev/null)
  wm_scan_flush

  # Email: addresses at the owner's domain other than owner / allowlist.
  wm_owner="$(wm_lower "$(wm_conf_get layer.conf owner_email)")"
  case "$wm_owner" in
    *@*)
      wm_dom="${wm_owner#*@}"
      wm_dom_re="$(printf '%s' "$wm_dom" | sed 's/[][\.*^$+?(){}|/-]/\\&/g')"
      wm_al="$(wm_lower "$(wm_conf_get layer.conf email_allowlist)")"
      wm_allow=",${wm_owner},${wm_al// /},"
      while IFS= read -r wm_hit; do
        [ -n "$wm_hit" ] || continue
        wm_hf="${wm_hit%%:*}"; wm_hr="${wm_hit#*:}"
        wm_hl="${wm_hr%%:*}"; wm_hm="$(wm_lower "${wm_hr#*:}")"
        wm_hm="${wm_hm%@*}@$wm_dom"
        case "$wm_allow" in *",$wm_hm,"*) continue ;; esac
        wm_scan_hit "$wm_hf" "$wm_hl" "email at owner domain" "$wm_hm"
      done < <(grep -HnIoiE -e "[A-Za-z0-9._%+-]+@${wm_dom_re}([^A-Za-z0-9-]|$)" -- "${wm_scan_files[@]}" 2>/dev/null)
      wm_scan_flush
      ;;
  esac
fi

if [ "$wm_scan_found" = 0 ]; then
  printf 'No secrets/identifiers found.\n'
  exit 0
fi
exit 1

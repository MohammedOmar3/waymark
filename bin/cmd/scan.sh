# waymark scan [--root <dir>]  (sourced by bin/waymark; uses exit)
# Patterns are written with single-character classes ([s]k-) so this file
# does not match its own rules.

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

wm_scan_report() { # <file> <line> <name> <text>
  local t="$4"
  t="${t#"${t%%[![:space:]]*}"}"
  [ "${#t}" -gt 120 ] && t="${t:0:120}..."
  printf '%s:%s  [%s]  %s\n' "$1" "$2" "$3" "$t"
  wm_scan_found=1
}

# File list: *.md *.conf *.tsv anywhere, plus everything under bin/.
wm_scan_files=()
while IFS= read -r wm_f; do
  wm_scan_files+=("${wm_f#./}")
done < <(find . \( -name .git -o -name inbox -o -name .view \) -prune -o -type f \
  \( -name '*.md' -o -name '*.conf' -o -name '*.tsv' -o -path './bin/*' \) \
  ! -name '*.log' -print 2>/dev/null | sort)

if [ "${#wm_scan_files[@]}" -gt 0 ]; then
  # name|flags|regex
  wm_scan_rules=(
    'secret assignment|-iE|([p]assword|[p]asswd|[s]ecret|[t]oken|[a]pi[_-]?[k]ey)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*["'"'"'`]?[^][:space:]<>{}()$"'"'"'`,;]{8,}'
    'sk key|-E|(^|[^A-Za-z0-9_])[s]k-[A-Za-z0-9_-]{20,}'
    'sk_live key|-E|[s]k_live_[A-Za-z0-9]{16,}'
    'github token|-E|[g]h[pousr]_[A-Za-z0-9]{36}'
    'github pat|-E|[g]ithub_pat_[A-Za-z0-9_]{40,}'
    'aws access key|-E|(^|[^A-Za-z0-9])(A[K]IA|A[S]IA)[A-Z0-9]{16}([^A-Za-z0-9]|$)'
    'private key block|-E|-----BEGIN [A-Z ]*PRIVATE[ ]KEY-----'
    'jwt|-E|e[y]J[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}'
    'slack token|-E|[x]ox[abeoprs]-[A-Za-z0-9-]{10,}'
    'url credentials|-E|[a-z][a-z0-9+.-]*[:]//[^/[:space:]:@]+:[^/[:space:]@]+@'
  )
  for wm_rule in "${wm_scan_rules[@]}"; do
    wm_name="${wm_rule%%|*}"; wm_rest="${wm_rule#*|}"
    wm_flag="${wm_rest%%|*}"; wm_re="${wm_rest#*|}"
    while IFS= read -r wm_hit; do
      [ -n "$wm_hit" ] || continue
      wm_hf="${wm_hit%%:*}"; wm_hr="${wm_hit#*:}"
      wm_hl="${wm_hr%%:*}"; wm_ht="${wm_hr#*:}"
      wm_scan_report "$wm_hf" "$wm_hl" "$wm_name" "$wm_ht"
    done < <(grep -HnI "$wm_flag" -e "$wm_re" -- "${wm_scan_files[@]}" 2>/dev/null)
  done

  # Email: addresses at the owner's domain other than owner / allowlist.
  wm_owner="$(wm_conf_get layer.conf owner_email)"
  wm_owner="${wm_owner,,}"
  case "$wm_owner" in
    *@*)
      wm_dom="${wm_owner#*@}"
      wm_dom_re="$(printf '%s' "$wm_dom" | sed 's/[][\.*^$+?(){}|/-]/\\&/g')"
      wm_allow=",${wm_owner},"
      wm_al="$(wm_conf_get layer.conf email_allowlist)"
      wm_al="${wm_al,,}"; wm_al="${wm_al// /}"
      wm_allow="$wm_allow$wm_al,"
      while IFS= read -r wm_hit; do
        [ -n "$wm_hit" ] || continue
        wm_hf="${wm_hit%%:*}"; wm_hr="${wm_hit#*:}"
        wm_hl="${wm_hr%%:*}"; wm_hm="${wm_hr#*:}"
        wm_hm_l="${wm_hm,,}"
        case "$wm_allow" in *",$wm_hm_l,"*) continue ;; esac
        wm_ht="$(sed -n "${wm_hl}p" "$wm_hf")"
        wm_scan_report "$wm_hf" "$wm_hl" "email at owner domain" "$wm_ht"
      done < <(grep -HnIoiE -e "[A-Za-z0-9._%+-]+@${wm_dom_re}\\b" -- "${wm_scan_files[@]}" 2>/dev/null)
      ;;
  esac
fi

if [ "$wm_scan_found" = 0 ]; then
  printf 'No secrets/identifiers found.\n'
  exit 0
fi
exit 1

# waymark scan [--root <dir>] [--staged]  (sourced by bin/waymark; uses exit)
# Patterns are written with single-character classes ([s]k-) so this file
# does not match its own rules. POSIX ERE only; bash 3.2 compatible.
# Findings never echo the matched value: it is replaced by [REDACTED].

wm_scan_root=""
wm_scan_staged=0
while [ $# -gt 0 ]; do
  case "$1" in
    --staged) wm_scan_staged=1; shift ;;
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
wm_h_file=(); wm_h_line=(); wm_h_name=(); wm_h_val=()

wm_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# wm_scan_hit <file> <line> <name> <matched-value-to-redact>
wm_scan_hit() {
  wm_h_file+=("$1"); wm_h_line+=("$2"); wm_h_name+=("$3"); wm_h_val+=("$4")
}

# Print one finding per distinct file:line:pattern. Every value matched on a
# line, by any rule, is redacted in every finding for that line.
wm_scan_flush() {
  local i j t v seen=$'\n' k n=${#wm_h_file[@]}
  for ((i = 0; i < n; i++)); do
    k="${wm_h_file[i]}:${wm_h_line[i]}:${wm_h_name[i]}"
    case "$seen" in *$'\n'"$k"$'\n'*) continue ;; esac
    seen="$seen$k"$'\n'
    t="$(sed -n "${wm_h_line[i]}p" "${wm_h_file[i]}")"
    t="${t%$'\r'}"
    for ((j = 0; j < n; j++)); do
      [ "${wm_h_file[j]}:${wm_h_line[j]}" = "${wm_h_file[i]}:${wm_h_line[i]}" ] || continue
      v="${wm_h_val[j]}"
      [ -n "$v" ] && t="${t//"$v"/[REDACTED]}"
    done
    t="${t#"${t%%[![:space:]]*}"}"
    [ "${#t}" -gt 120 ] && t="${t:0:120}..."
    printf '%s:%s  [%s]  %s\n' "${wm_h_file[i]}" "${wm_h_line[i]}" "${wm_h_name[i]}" "$t"
    wm_scan_found=1
  done
}

# File list: exactly what git would commit. In a git root that is every
# tracked or untracked-but-not-ignored file (--staged: the staged set, for the
# pre-commit hook); gitignored files (active/, inbox/, .view/, logs) are never
# scanned. Outside git: every file except the layer's runtime directories.
# Binary files are skipped by grep -I below.
wm_scan_files=()
if [ -e .git ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r -d '' wm_f; do
    [ -f "$wm_f" ] && wm_scan_files+=("$wm_f")
  done < <(if [ "$wm_scan_staged" = 1 ]; then
             git diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null
           else
             git ls-files -z -co --exclude-standard 2>/dev/null
           fi)
else
  while IFS= read -r wm_f; do
    wm_scan_files+=("${wm_f#./}")
  done < <(find . \( -name .git -o -name inbox -o -name .view -o -name .locks -o -path ./active \) -prune -o -type f \
    ! -name '*.log' ! -name '*.tmp' ! -name '*.bak' -print 2>/dev/null | sort)
fi

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
  done

  # Credential assignment: whole-word key, then a quoted literal (>=6 chars)
  # or an unquoted value (>=8 chars, letter and digit, not followed by ( [ .).
  # Every key occurrence on a line is evaluated.
  wm_keys='([p]assword|[p]asswd|[s]ecret|[t]oken|[a]pi[_-]?[k]ey|[a]ccess[_-]?[k]ey|[c]lient[_-]?[s]ecret)'
  wm_key_re="(^|[^A-Za-z0-9])${wm_keys}[[:space:]]*[:=][[:space:]]*"
  while IFS= read -r wm_hit; do
    [ -n "$wm_hit" ] || continue
    wm_hr="${wm_hit#*:}"
    wm_hf="${wm_hit%%:*}"; wm_hl="${wm_hr%%:*}"; wm_text="${wm_hr#*:}"
    while :; do
      wm_m="$(printf '%s\n' "$wm_text" | grep -oiE -e "$wm_key_re" | head -n 1)"
      [ -n "$wm_m" ] || break
      wm_rest="${wm_text#*"$wm_m"}"
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
      wm_text="$wm_rest"
    done
  done < <(grep -HnIiE -e "$wm_key_re" -- "${wm_scan_files[@]}" 2>/dev/null)

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
        # redact the address as written (original case, trailing delimiter cut)
        wm_ho="${wm_hr#*:}"; wm_hd="${wm_ho##*@}"
        wm_ho="${wm_ho%@*}@${wm_hd:0:${#wm_dom}}"
        wm_scan_hit "$wm_hf" "$wm_hl" "email at owner domain" "$wm_ho"
      done < <(grep -HnIoiE -e "[A-Za-z0-9._%+-]+@${wm_dom_re}([^A-Za-z0-9-]|$)" -- "${wm_scan_files[@]}" 2>/dev/null)
      ;;
  esac
fi

wm_scan_flush
if [ "$wm_scan_found" = 0 ]; then
  printf 'No secrets/identifiers found.\n'
  exit 0
fi
exit 1

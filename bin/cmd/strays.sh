# waymark strays [--roots <dirs>]  (sourced by bin/waymark; uses exit)
# Report-only (source B.5): untracked .md files in repo working trees. Never
# modifies anything. Roots: --roots (comma separated) or repo_roots in layer.conf.

wm_sy_roots=""
while [ $# -gt 0 ]; do
  case "$1" in
    --roots) wm_sy_roots="${2:-}"; shift 2 || shift ;;
    --roots=*) wm_sy_roots="${1#--roots=}"; shift ;;
    *) printf 'waymark strays: unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done
if [ -z "$wm_sy_roots" ]; then
  wm_sy_layer="$(wm_layer_root)" || { printf 'waymark strays: no layer found (use --roots)\n' >&2; exit 2; }
  wm_sy_roots="$(wm_conf_get "$wm_sy_layer/layer.conf" repo_roots)"
fi
if [ -z "$wm_sy_roots" ]; then
  printf 'waymark strays: no repo_roots configured (use --roots)\n' >&2
  exit 2
fi

# Input lines: "T <tracked path>", "F <./found path>"; paths with .git as the
# last segment are nested-repo markers. Output: one stray path per line.
wm_sy_filter='
function lc(s) { return tolower(s) }
BEGIN {
  split("readme.md changelog.md claude.md contributing.md copilot-instructions.md license.md package.md code_of_conduct.md security.md", ex, " ")
  for (i in ex) exc[ex[i]] = 1
}
{ sub(/\r$/, "") }
substr($0, 1, 2) == "T " { tr[substr($0, 3)] = 1; next }
substr($0, 1, 2) == "F " {
  p = substr($0, 3); sub(/^\.\//, "", p)
  if (p ~ /(^|\/)\.git$/) { if (p != ".git") { d = p; sub(/\.git$/, "", d); nest[++nn] = d } ; next }
  f[++nf] = p
}
END {
  for (i = 1; i <= nf; i++) {
    p = f[i]; b = p; sub(/.*\//, "", b)
    if (lc(b) in exc) continue
    if (p in tr) continue
    skip = 0
    for (j = 1; j <= nn; j++) if (substr(p, 1, length(nest[j])) == nest[j]) { skip = 1; break }
    if (!skip) print p
  }
}'

wm_sy_found=""
wm_sy_list="$(printf '%s\n' "$wm_sy_roots" | tr ',' '\n')"
while IFS= read -r wm_sy_r; do
  [ -n "$wm_sy_r" ] || continue
  case "$wm_sy_r" in *'\'*|[A-Za-z]:*) wm_sy_r="$(wm_path "$wm_sy_r")" ;; esac
  wm_sy_r="${wm_sy_r%/}"
  [ -d "$wm_sy_r" ] || continue
  # repos: .git (dir or file) up to depth 4 below the root; the first repo on a
  # path wins, so nested repos/submodules are never treated as separate repos.
  wm_sy_gits="$(find "$wm_sy_r" -maxdepth 5 -name node_modules -prune -o -name .git -print -prune 2>/dev/null | LC_ALL=C sort)"
  wm_sy_prev=""
  while IFS= read -r wm_sy_g; do
    [ -n "$wm_sy_g" ] || continue
    wm_sy_dir="${wm_sy_g%/.git}"
    if [ -n "$wm_sy_prev" ]; then
      case "$wm_sy_dir/" in "$wm_sy_prev/"*) continue ;; esac
    fi
    wm_sy_prev="$wm_sy_dir"
    wm_sy_name="${wm_sy_dir##*/}"
    wm_sy_rel="$( {
        git -C "$wm_sy_dir" -c core.quotepath=off ls-files 2>/dev/null | sed 's/^/T /'
        ( cd "$wm_sy_dir" && find . \( \( -name node_modules -o -name .expo -o -name dist -o -name build -o -name .next -o -name vendor -o -name .venv -o -name venv -o -name site-packages -o -name target \) -o -path '*/ios/Pods' \) -type d -prune -o -name .git -print -prune -o -type f -name '*.md' -print 2>/dev/null | sed 's/^/F /' )
      } | LC_ALL=C awk "$wm_sy_filter" )"
    while IFS= read -r wm_sy_p; do
      [ -n "$wm_sy_p" ] || continue
      wm_sy_abs="$wm_sy_dir/$wm_sy_p"
      wm_sy_size="$(wc -c < "$wm_sy_abs" 2>/dev/null | tr -d ' ')"
      wm_sy_kb="$(LC_ALL=C awk -v s="${wm_sy_size:-0}" 'BEGIN { printf "%.1f", s / 1024 }')"
      wm_sy_head=""
      while IFS= read -r wm_sy_l || [ -n "$wm_sy_l" ]; do
        wm_sy_l="${wm_sy_l%$'\r'}"
        wm_sy_t="${wm_sy_l#"${wm_sy_l%%[![:space:]]*}"}"
        case "$wm_sy_t" in
          '#'*)
            wm_sy_t="${wm_sy_t#"${wm_sy_t%%[!#]*}"}"
            wm_sy_head="${wm_sy_t#"${wm_sy_t%%[![:space:]]*}"}"
            break ;;
        esac
      done < "$wm_sy_abs"
      wm_sy_found="$wm_sy_found$wm_sy_name  $wm_sy_kb  $wm_sy_head  $wm_sy_abs"$'\n'
    done <<< "$wm_sy_rel"
  done <<< "$wm_sy_gits"
done <<< "$wm_sy_list"

if [ -z "$wm_sy_found" ]; then
  printf 'No stray docs found.\n'
else
  printf '%s' "$wm_sy_found"
fi
exit 0

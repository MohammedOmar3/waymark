# waymark brief <term...> [--repo <r>]  (sourced by bin/waymark; uses exit)
# Prior-art search: case-insensitive AND of all terms over gotcha/decision/
# convention blocks, playbook rule lines and docs/INDEX.md rows. Read-only.

wm_br_repo=""; wm_br_terms=""; wm_br_disp=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) wm_br_repo="${2:-}"; shift 2 || shift ;;
    --repo=*) wm_br_repo="${1#--repo=}"; shift ;;
    -*) printf 'waymark brief: unknown argument: %s\n' "$1" >&2; exit 64 ;;
    *)
      if [ -n "$wm_br_terms" ]; then wm_br_terms="$wm_br_terms"$'\n'"$1"; wm_br_disp="$wm_br_disp $1"
      else wm_br_terms="$1"; wm_br_disp="$1"; fi
      shift ;;
  esac
done
if [ -z "$wm_br_terms" ]; then
  printf 'usage: waymark brief <term...> [--repo <r>]\n' >&2
  exit 64
fi
wm_br_layer="$(wm_layer_root)" || { printf 'waymark brief: no layer found\n' >&2; exit 2; }

# Entry blocks: column-0 "## X-NNNN" headings only (indented format examples
# inside HTML comments never match). Obsolete gotchas are dropped.
wm_br_entries='
function flush(   low, i, ok, s) {
  if (id == "") return
  low = tolower(block); ok = 1
  for (i = 1; i <= nt; i++) if (index(low, T[i]) == 0) { ok = 0; break }
  if (ok && substr(id, 1, 1) == "G" && tolower(F["Status"]) == "obsolete") ok = 0
  if (ok && rp != "" && F["Repo"] != "" && tolower(F["Repo"]) != rp && tolower(F["Repo"]) != "all") ok = 0
  if (ok && n < 10) {
    if (substr(id, 1, 1) == "G") s = F["Status"]
    else if (substr(id, 1, 1) == "D") s = (F["Chose"] != "" ? F["Chose"] : (F["Kind"] != "" ? F["Kind"] : "decision"))
    else s = "repo: " F["Repo"]
    n++; print id "  " title " — " s
  }
  id = ""; block = ""
}
BEGIN { nt = split(tolower(ENVIRON["WM_TERMS"]), T, "\n"); rp = tolower(ENVIRON["WM_REPO"]) }
{ sub(/\r$/, "") }
/^## [A-Z]-[0-9]+/ {
  flush(); split("", F)
  h = substr($0, 4); id = h; sub(/ .*/, "", id)
  title = h; sub(/^[^ ]+ +— */, "", title)
  block = $0; next
}
/^## / { flush(); next }
id != "" {
  block = block "\n" $0
  if ($0 ~ /^- \*\*[^*]+:\*\*/) {
    nm = $0; sub(/^- \*\*/, "", nm); sub(/:\*\*.*/, "", nm)
    v = $0; sub(/^- \*\*[^*]+:\*\* ?/, "", v); F[nm] = v
  }
}
END { flush() }'

wm_br_playbooks='
BEGIN { nt = split(tolower(ENVIRON["WM_TERMS"]), T, "\n") }
FNR == 1 { fm = 0; sec = ""; tag = FILENAME; sub(/.*\//, "", tag); sub(/\.md$/, "", tag); fmdone = 0; rel = "playbooks/" tag ".md" }
{ sub(/\r$/, "") }
FNR == 1 && $0 == "---" { fm = 1; next }
fm { if ($0 == "---") { fm = 0; fmdone = 1 } else if ($0 ~ /^tag:/) { t = $0; sub(/^tag:[ \t]*/, "", t); if (t != "") tag = t }; next }
/^## / { sec = $0; next }
sec == "## Rules" && /^- / {
  low = tolower($0); ok = 1
  for (i = 1; i <= nt; i++) if (index(low, T[i]) == 0) { ok = 0; break }
  if (ok && n < 10) { r = $0; sub(/^- +/, "", r); n++; print rel "  " tag " — " r }
}'

wm_br_docs='
BEGIN { nt = split(tolower(ENVIRON["WM_TERMS"]), T, "\n"); rp = tolower(ENVIRON["WM_REPO"]) }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
{ sub(/\r$/, "") }
/^## / { sec = tolower(substr($0, 4)); next }
/^\| / {
  row = $0; gsub(/\\\|/, "\001", row)
  nf = split(row, c, "|")
  if (nf != 7) next
  if (trim(c[2]) == "Title" || c[2] ~ /^-+$/) next
  low = tolower(row); ok = 1
  for (i = 1; i <= nt; i++) if (index(low, T[i]) == 0) { ok = 0; break }
  if (ok && rp != "" && sec != rp && sec != "cross-repo" && sec != "all") ok = 0
  if (ok && n < 10) {
    lk = trim(c[6]); p = lk; sub(/^\[/, "", p); sub(/\]\(.*$/, "", p)
    ti = trim(c[2]); su = trim(c[5])
    gsub(/\001/, "|", p); gsub(/\001/, "|", ti); gsub(/\001/, "|", su)
    n++; print p "  " ti " — " su
  }
}'

wm_br_out=""
wm_br_section() { # <title> <hits>
  [ -n "$2" ] || return 0
  wm_br_out="$wm_br_out$1"$'\n'"$2"$'\n'
}

wm_br_run() { LC_ALL=C WM_TERMS="$wm_br_terms" WM_REPO="$wm_br_repo" awk "$@"; }

wm_br_g=""; wm_br_d=""; wm_br_c=""; wm_br_p=""; wm_br_x=""
[ -f "$wm_br_layer/gotchas.md" ] && wm_br_g="$(wm_br_run "$wm_br_entries" "$wm_br_layer/gotchas.md")"
[ -f "$wm_br_layer/decisions.md" ] && wm_br_d="$(wm_br_run "$wm_br_entries" "$wm_br_layer/decisions.md")"
[ -f "$wm_br_layer/conventions.md" ] && wm_br_c="$(wm_br_run "$wm_br_entries" "$wm_br_layer/conventions.md")"
set -- "$wm_br_layer"/playbooks/*.md
[ -f "$1" ] && wm_br_p="$(wm_br_run "$wm_br_playbooks" "$@")"
[ -f "$wm_br_layer/docs/INDEX.md" ] && wm_br_x="$(wm_br_run "$wm_br_docs" "$wm_br_layer/docs/INDEX.md")"

wm_br_section Gotchas "$wm_br_g"
wm_br_section Decisions "$wm_br_d"
wm_br_section Conventions "$wm_br_c"
wm_br_section Playbooks "$wm_br_p"
wm_br_section Docs "$wm_br_x"

if [ -z "$wm_br_out" ]; then
  printf 'No prior art for: %s\n' "$wm_br_disp"
else
  printf '%s' "$wm_br_out"
fi
exit 0

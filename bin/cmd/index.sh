# waymark index [--root <dir>]  (sourced by bin/waymark; uses exit)
# Regenerates <layer>/docs/INDEX.md from doc frontmatter. Deterministic:
# LC_ALL=C ordering, no timestamps, LF endings. POSIX awk/sort; bash 3.2 ok.

wm_ix_root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) wm_ix_root="${2:-}"; shift 2 || shift ;;
    --root=*) wm_ix_root="${1#--root=}"; shift ;;
    *) printf 'waymark index: unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done
if [ -z "$wm_ix_root" ]; then
  wm_ix_root="$(wm_layer_root)" || { printf 'waymark index: no layer found\n' >&2; exit 2; }
fi
case "$wm_ix_root" in *'\'*|[A-Za-z]:*) wm_ix_root="$(wm_path "$wm_ix_root")" ;; esac
[ -d "$wm_ix_root" ] || { printf 'waymark index: not a directory: %s\n' "$wm_ix_root" >&2; exit 2; }
mkdir -p "$wm_ix_root/docs" || exit 2
cd "$wm_ix_root/docs" || exit 2

# Pass 1: one tab-separated record per doc (file list on stdin).
#   C repo rank status created title kind summary expired link
#   I path missing-fields
wm_ix_scan='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function clean(s,   q) {
  s = trim(s)
  if (substr(s, 1, 1) == "#") return ""
  q = substr(s, 1, 1)
  if (length(s) >= 2 && (q == "\"" || q == "\047") && substr(s, length(s), 1) == q) s = substr(s, 2, length(s) - 2)
  gsub(/\t/, " ", s)
  return s
}
function absent(k) { return !(k in fm) || fm[k] == "" || substr(fm[k], 1, 5) == "TODO:" }
function addm(k) { missing = missing (missing == "" ? "" : ", ") k }
BEGIN {
  today = ENVIRON["WM_TODAY"]
  nreq = split("title repo kind created status", req, " ")
  ns = split("current draft done abandoned superseded unknown", so, " ")
}
{
  f = $0
  split("", fm)
  ok = 0; n = 0
  while ((getline line < f) > 0) {
    sub(/\r$/, "", line)
    n++
    if (n == 1) { if (line == "---") continue; else break }
    if (line == "---") { ok = 1; break }
    if (match(line, /^[A-Za-z_]+:/)) {
      k = substr(line, 1, RLENGTH - 1)
      if (!(k in fm)) fm[k] = clean(substr(line, RLENGTH + 1))
    }
  }
  close(f)
  if (!ok) split("", fm)
  missing = ""
  for (i = 1; i <= nreq; i++) if (absent(req[i])) addm(req[i])
  if ((fm["kind"] == "analysis" || fm["kind"] == "research") && absent("valid_until")) addm("valid_until")
  if (missing != "") { print "I\t" f "\t" missing; next }
  rank = 99
  for (i = 1; i <= ns; i++) if (so[i] == fm["status"]) { rank = i - 1; break }
  expired = ""
  v = fm["valid_until"]
  if (v ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && v < today) expired = "1"
  t = fm["title"]; s = fm["summary"]; kd = fm["kind"]
  gsub(/\|/, "\\|", t); gsub(/\|/, "\\|", s); gsub(/\|/, "\\|", kd)
  printf "C\t%s\t%02d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", fm["repo"], rank, fm["status"], fm["created"], t, kd, s, expired, f
}'

# Pass 2: render the sorted records.
wm_ix_render='
function esc(s) { gsub(/\|/, "\\|", s); return s }
function enc(s) { gsub(/ /, "%20", s); return s }
BEGIN {
  FS = "\t"
  print "---"; print "title: Docs Index"; print "status: generated"; print "---"; print ""
  print "<!-- GENERATED FILE. Do not hand-edit. Produced by waymark index. -->"; print ""
  print "# Docs Index"
}
$1 == "C" {
  nc++
  if (nc == 1 || $2 != repo) { print ""; print "## " $2; repo = $2; status = "\001" }
  if ($4 != status) {
    print ""; print "### " $4; print ""
    print "| Title | Kind | Date | Summary | Link |"; print "|---|---|---|---|---|"
    status = $4
  }
  print "| " $6 ($9 == "1" ? " (expired)" : "") " | " $7 " | " $5 " | " $8 " | [" esc($10) "](" enc($10) ") |"
  next
}
$1 == "I" { ni++; inc[ni] = "| " esc($2) " | TODO: " $3 " |" }
END {
  if (nc == 0 && ni == 0) { print ""; print "No docs yet." }
  if (ni > 0) {
    print ""; print "## Needs frontmatter"; print ""
    print "| Path | Missing fields |"; print "|---|---|"
    for (i = 1; i <= ni; i++) print inc[i]
  }
}'

wm_ix_recs="$(find . \( -path ./archive -o -path ./INDEX.md \) -prune -o -type f -name '*.md' -print 2>/dev/null |
  LC_ALL=C sort | sed 's|^\./||' |
  LC_ALL=C WM_TODAY="$(wm_today)" awk "$wm_ix_scan" |
  LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 -k4,4 -k5,5r -k6,6 -k10,10)"

wm_ix_out="INDEX.md.tmp.$$"
printf '%s\n' "$wm_ix_recs" | LC_ALL=C awk "$wm_ix_render" > "$wm_ix_out" &&
  mv -f "$wm_ix_out" INDEX.md || { rm -f "$wm_ix_out"; printf 'waymark index: cannot write INDEX.md\n' >&2; exit 2; }

wm_ix_counts="$(printf '%s\n' "$wm_ix_recs" | awk -F '\t' '$1=="C"{c++; if($9=="1")x++} $1=="I"{i++} END{print c+0, i+0, x+0}')"
set -- $wm_ix_counts
printf 'Regenerated %s (%s indexed, %s incomplete, %s expired).\n' "$wm_ix_root/docs/INDEX.md" "$1" "$2" "$3"
exit 0

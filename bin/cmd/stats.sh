# waymark stats [--last <n>]  (sourced by bin/waymark; uses exit)
# Capture/recall statistics from worklog.md (last n entries, default 30) and
# stats/recall.tsv. Read-only.

wm_st_last=30
while [ $# -gt 0 ]; do
  case "$1" in
    --last) wm_st_last="${2:-}"; shift 2 || shift ;;
    --last=*) wm_st_last="${1#--last=}"; shift ;;
    *) printf 'waymark stats: unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done
case "$wm_st_last" in ''|*[!0-9]*) printf 'waymark stats: --last needs a number\n' >&2; exit 64 ;; esac
wm_st_layer="$(wm_layer_root)" || { printf 'waymark stats: no layer found\n' >&2; exit 2; }

wm_st_work='
function num(line, word,   t) {
  # number immediately before <word> in line, else 0
  if (match(line, "[0-9]+ " word)) { t = substr(line, RSTART, RLENGTH); sub(/ .*/, "", t); return t + 0 }
  return 0
}
{ sub(/\r$/, "") }
/^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { n++; cand[n] = 0; rec[n] = 0; dis[n] = 0; def[n] = 0; hit[n] = 0; next }
n > 0 && /^- \*\*Capture:\*\*/ {
  cand[n] = num($0, "candidates"); rec[n] = num($0, "recorded")
  dis[n] = num($0, "dismissed"); def[n] = num($0, "deferred"); next
}
n > 0 && /^- \*\*Recall hits:\*\*/ { v = $0; sub(/^- \*\*Recall hits:\*\* */, "", v); hit[n] = v + 0 }
END {
  last = ENVIRON["WM_LAST"] + 0
  from = n - last + 1; if (from < 1) from = 1
  for (i = from; i <= n; i++) { C += cand[i]; R += rec[i]; D += dis[i]; F += def[i]; H += hit[i]; k++ }
  printf "Worklog entries: %d\n", k
  printf "Candidates: %d\nRecorded: %d\nDismissed: %d\nDeferred: %d\n", C, R, D, F
  if (C > 0) printf "Capture rate: %d%% (recorded+dismissed of candidates)\n", int((R + D) * 100 / C + 0.5)
  else print "Capture rate: n/a (no candidates)"
  printf "Recall hits: %d\n", H
}'

if [ -f "$wm_st_layer/worklog.md" ]; then
  LC_ALL=C WM_LAST="$wm_st_last" awk "$wm_st_work" "$wm_st_layer/worklog.md"
else
  LC_ALL=C WM_LAST="$wm_st_last" awk "$wm_st_work" /dev/null
fi

wm_st_top=""
if [ -f "$wm_st_layer/stats/recall.tsv" ]; then
  wm_st_top="$(LC_ALL=C awk -F '\t' '
    { sub(/\r$/, "") }
    NR == 1 && $1 == "date" { next }
    $3 != "" { c[$3]++ }
    END { for (k in c) printf "%d\t%s\n", c[k], k }' "$wm_st_layer/stats/recall.tsv" |
    LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k2,2 | head -n 5)"
fi
if [ -z "$wm_st_top" ]; then
  printf 'Top recalled: none\n'
else
  printf 'Top recalled:\n'
  printf '%s\n' "$wm_st_top" | while IFS="$(printf '\t')" read -r wm_st_n wm_st_id; do
    printf '  %s  %s\n' "$wm_st_id" "$wm_st_n"
  done
fi
exit 0

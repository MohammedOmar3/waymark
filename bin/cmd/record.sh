# waymark record gotcha|decision|retro|convention [flags]  (sourced by bin/waymark; uses exit)
# Appends a spec section 7 entry with the next ID, under lock "ids", then commits.
# Required field missing -> exit 2 naming it, nothing written. Scan failure at
# commit -> entry stays written (uncommitted), exit 2.

wm_tri_cmd=__lib
wm_rec_dir="$(dirname "${BASH_SOURCE[0]}")"
. "$wm_rec_dir/triage.sh"
wm_tri_cmd=record

wm_rec_kind="${1:-}"
[ $# -gt 0 ] && shift
case "$wm_rec_kind" in
  gotcha|decision|retro|convention) ;;
  *) wm_tri_die "usage: waymark record gotcha|decision|retro|convention [--flag value ...]" 64 ;;
esac

wm_rec_symptom=""; wm_rec_cause=""; wm_rec_fix=""; wm_rec_match=""; wm_rec_status="fixed"
wm_rec_decision=""; wm_rec_chose=""; wm_rec_because=""; wm_rec_constraint=""; wm_rec_revisit=""
wm_rec_doc=""; wm_rec_worked=""; wm_rec_surprised=""; wm_rec_change=""; wm_rec_rule=""; wm_rec_why=""
wm_rec_repo=""; wm_rec_tags=""; wm_rec_tags_set=0; wm_rec_from=""
while [ $# -gt 0 ]; do
  case "$1" in
    --*=*) wm_rec_k="${1%%=*}"; wm_rec_v="${1#*=}"; shift ;;
    --*) wm_rec_k="$1"; [ $# -ge 2 ] || wm_tri_die "missing value for $1"; wm_rec_v="$2"; shift 2 ;;
    *) wm_tri_die "unknown argument: $1" ;;
  esac
  wm_tri_oneline "$wm_rec_v"; wm_rec_v="$WM_L"
  case "$wm_rec_k" in
    --symptom) wm_rec_symptom="$wm_rec_v" ;;
    --cause) wm_rec_cause="$wm_rec_v" ;;
    --fix) wm_rec_fix="$wm_rec_v" ;;
    --match) wm_rec_match="$wm_rec_v" ;;
    --status) wm_rec_status="$wm_rec_v" ;;
    --decision) wm_rec_decision="$wm_rec_v" ;;
    --chose) wm_rec_chose="$wm_rec_v" ;;
    --because) wm_rec_because="$wm_rec_v" ;;
    --constraint) wm_rec_constraint="$wm_rec_v" ;;
    --revisit) wm_rec_revisit="$wm_rec_v" ;;
    --doc) wm_rec_doc="$wm_rec_v" ;;
    --worked) wm_rec_worked="$wm_rec_v" ;;
    --surprised) wm_rec_surprised="$wm_rec_v" ;;
    --change) wm_rec_change="$wm_rec_v" ;;
    --rule) wm_rec_rule="$wm_rec_v" ;;
    --why) wm_rec_why="$wm_rec_v" ;;
    --repo) wm_rec_repo="$wm_rec_v" ;;
    --tags) wm_rec_tags="$wm_rec_v"; wm_rec_tags_set=1 ;;
    --from) wm_rec_from="$wm_rec_v" ;;
    *) wm_tri_die "unknown flag: $wm_rec_k" ;;
  esac
done

wm_rec_layer="$(wm_layer_root)" || wm_tri_die "no layer found"

# --from: resolve candidate (default --match from its first output line)
if [ -n "$wm_rec_from" ]; then
  wm_tri_cand_file "$wm_rec_layer" "$wm_rec_from"
  wm_rec_row="$(wm_tri_list_raw "$WM_CF" | awk -F'\t' -v id="$wm_rec_from" '$1 == id { print; exit }')"
  # a candidate already answered is not recorded again (a retried call would duplicate the entry)
  if [ -n "$wm_rec_row" ]; then
    wm_rec_st="${wm_rec_row#*$'\t'}"; wm_rec_st="${wm_rec_st%%$'\t'*}"; wm_rec_st="${wm_rec_st%$'\r'}"
    case "${wm_rec_st%% *}" in
      recorded|dismissed) wm_tri_die "candidate $wm_rec_from is already $wm_rec_st; nothing recorded" ;;
    esac
  fi
  if [ -z "$wm_rec_match" ]; then
    wm_rec_first="$(printf '%s' "$wm_rec_row" | cut -f4-)"
    wm_rec_first="${wm_rec_first%$'\r'}"
    wm_rec_match="$wm_rec_first"
  fi
fi

# required fields (checked before anything is written)
case "$wm_rec_kind" in
  gotcha) wm_rec_req="symptom cause fix match" ;;
  decision) wm_rec_req="decision chose because constraint revisit" ;;
  retro) wm_rec_req="doc worked surprised change" ;;
  convention) wm_rec_req="rule" ;;
esac
for wm_rec_f in $wm_rec_req; do
  wm_rec_ref="wm_rec_$wm_rec_f"
  [ -n "${!wm_rec_ref}" ] || wm_tri_die "missing required field: --$wm_rec_f"
done
case "$wm_rec_kind:$wm_rec_status" in
  gotcha:open|gotcha:fixed|gotcha:obsolete) ;;
  gotcha:*) wm_tri_die "bad --status: $wm_rec_status (open|fixed|obsolete)" ;;
esac

# defaults
[ -n "$wm_rec_repo" ] || wm_rec_repo="$(wm_repo_name "$PWD")"
if [ "$wm_rec_tags_set" = 0 ]; then
  wm_rec_tags="$(wm_repo_tags "$PWD")"
  wm_rec_tags="${wm_rec_tags// /, }"
else
  wm_rec_tags="${wm_rec_tags// /}"
  wm_rec_tags="${wm_rec_tags//,/, }"
fi

# wm_rec_field <label> <value> : "- **Label:** value" (no trailing space when empty)
wm_rec_field() {
  if [ -n "$2" ]; then printf -- '- **%s:** %s\n' "$1" "$2"; else printf -- '- **%s:**\n' "$1"; fi
}
wm_rec_short() { # <text> -> WM_S (<= 70 bytes, never ends inside a UTF-8 character)
  local LC_ALL=C s="$1" n=67
  if [ "${#s}" -le 70 ]; then WM_S="$s"; return 0; fi
  while [ "$n" -gt 0 ]; do
    case "${s:n:1}" in
      [$'\200'-$'\277']) n=$((n - 1)) ;;
      *) break ;;
    esac
  done
  WM_S="${s:0:n}..."
}

case "$wm_rec_kind" in
  gotcha) wm_rec_file="$wm_rec_layer/gotchas.md"; wm_rec_pfx=G ;;
  convention) wm_rec_file="$wm_rec_layer/conventions.md"; wm_rec_pfx=C ;;
  *) wm_rec_file="$wm_rec_layer/decisions.md"; wm_rec_pfx=D ;;
esac

wm_lock ids || wm_tri_die "could not take ids lock" 3
[ -f "$wm_rec_file" ] || : > "$wm_rec_file"
wm_rec_n="$(awk -v p="## $wm_rec_pfx-" '
  { sub(/\r$/, "") }
  substr($0, 1, length(p)) == p && $0 ~ /^## [A-Z]-[0-9]+/ { r = substr($0, 4); sub(/^[A-Z]-/, "", r); n = r + 0; if (n > m) m = n }
  END { print m + 0 }' "$wm_rec_file")"
[ -z "${WAYMARK_TEST_ID_DELAY:-}" ] || sleep "$WAYMARK_TEST_ID_DELAY"   # test hook: widen the race window
wm_rec_id="$(printf '%s-%04d' "$wm_rec_pfx" $((wm_rec_n + 1)))"
case "$wm_rec_kind" in
  gotcha) wm_rec_short "$wm_rec_symptom"; wm_rec_head="## $wm_rec_id — $WM_S" ;;
  convention) wm_rec_short "$wm_rec_rule"; wm_rec_head="## $wm_rec_id — $WM_S" ;;
  decision) wm_rec_short "$wm_rec_decision"; wm_rec_head="## $wm_rec_id — $(wm_today) — $WM_S" ;;
  retro) wm_rec_short "Retro: $wm_rec_doc"; wm_rec_head="## $wm_rec_id — $(wm_today) — $WM_S" ;;
esac
{
  [ -s "$wm_rec_file" ] && [ -n "$(tail -c1 "$wm_rec_file")" ] && printf '\n'
  printf '\n%s\n' "$wm_rec_head"
  case "$wm_rec_kind" in
    gotcha)
      wm_rec_field Status "$wm_rec_status"
      wm_rec_field Repo "$wm_rec_repo"
      wm_rec_field Tags "$wm_rec_tags"
      wm_rec_field Match "$wm_rec_match"
      wm_rec_field Symptom "$wm_rec_symptom"
      wm_rec_field Cause "$wm_rec_cause"
      wm_rec_field Fix "$wm_rec_fix"
      wm_rec_field "First hit" "$(wm_today)" ;;
    decision)
      wm_rec_field Repo "$wm_rec_repo"
      wm_rec_field Tags "$wm_rec_tags"
      wm_rec_field Doc "${wm_rec_doc:-none}"
      wm_rec_field Chose "$wm_rec_chose"
      wm_rec_field Because "$wm_rec_because"
      wm_rec_field "Constraint that forced it" "$wm_rec_constraint"
      wm_rec_field "Revisit if" "$wm_rec_revisit" ;;
    retro)
      wm_rec_field Repo "$wm_rec_repo"
      wm_rec_field Tags "$wm_rec_tags"
      wm_rec_field Kind retro
      wm_rec_field Doc "$wm_rec_doc"
      wm_rec_field "What worked" "$wm_rec_worked"
      wm_rec_field "What surprised us" "$wm_rec_surprised"
      wm_rec_field "Change next time" "$wm_rec_change" ;;
    convention)
      wm_rec_field Repo "$wm_rec_repo"
      wm_rec_field Tags "$wm_rec_tags"
      wm_rec_field Rule "$wm_rec_rule"
      wm_rec_field Because "$wm_rec_why" ;;
  esac
} >> "$wm_rec_file"
wm_rec_wrc=$?
wm_unlock ids
[ $wm_rec_wrc -eq 0 ] || wm_tri_die "could not write $wm_rec_file" 3

printf '%s\n' "$wm_rec_id"
if [ -n "$wm_rec_from" ]; then
  wm_tri_set_state "$wm_rec_layer" "$wm_rec_from" "recorded $wm_rec_id" \
    || printf 'waymark record: warning: could not update %s\n' "$wm_rec_from" >&2
fi
case "$wm_rec_kind" in
  gotcha) wm_rec_sub="$wm_rec_symptom" ;;
  convention) wm_rec_sub="$wm_rec_rule" ;;
  decision) wm_rec_sub="$wm_rec_decision" ;;
  retro) wm_rec_sub="retro $wm_rec_doc" ;;
esac
wm_rec_short "$wm_rec_sub"
wm_commit "memory: $wm_rec_id $WM_S"
wm_rec_crc=$?
case $wm_rec_crc in
  0) exit 0 ;;
  2) printf 'waymark record: %s written but scan failed; left uncommitted (see active/.scan-failed.log)\n' "$wm_rec_id" >&2; exit 2 ;;
  *) printf 'waymark record: %s written but commit failed (%s)\n' "$wm_rec_id" "$wm_rec_crc" >&2; exit "$wm_rec_crc" ;;
esac

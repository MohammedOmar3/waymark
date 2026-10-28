#!/usr/bin/env bash
# Tests for hooks/session-start and hooks/run-hook.cmd

. "$WM_REPO_ROOT/bin/lib.sh"

# t_ss_setup: bare layer in $L (WAYMARK_ROOT), fake repo "alpha" in $R
t_ss_setup() {
  L="$WM_SANDBOX_DIR/${WM_LAYER_SUB:-layer}"; R="$WM_SANDBOX_DIR/alpha"
  mkdir -p "$L/playbooks" "$L/repos" "$L/stats" "$L/active" "$L/inbox"
  printf 'repo_roots=\n' > "$L/layer.conf"
  printf 'expo*=expo\nreact=react\n' > "$L/tags.conf"
  printf 'date\tsession\tid\trepo\n' > "$L/stats/recall.tsv"
  : > "$L/gotchas.md"
  export WAYMARK_ROOT="$L"
  t_fake_repo "$R" '{"dependencies":{"expo":"1","react":"2"}}'
}

# t_ss_run <hook json args...> -> raw hook stdout
t_ss_run() { t_hook_json SessionStart "$@" | bash "$WM_PLUGIN/hooks/session-start"; }

# t_ss_ctx [source] [session] -> decoded additionalContext in $CTX, raw output in $RAW
t_ss_ctx() {
  RAW="$(t_ss_run session_id="${2:-abcdef1234}" cwd="${CWD:-$R}" source="${1:-startup}")"
  CTX="$(wm_json_str "$RAW" hookSpecificOutput.additionalContext)"
}

t_ss_gotcha() { # id status repo tags symptom
  printf '## %s — %s\n- **Status:** %s\n- **Repo:** %s\n- **Tags:** %s\n- **Match:** m\n- **Symptom:** s\n\n' \
    "$1" "$5" "$2" "$3" "$4" >> "$L/gotchas.md"
}

test_not_set_up() {
  local raw ctx
  export WAYMARK_ROOT="$WM_SANDBOX_DIR/nolayer"
  t_fake_repo "$WM_SANDBOX_DIR/r1"
  raw="$(t_hook_json SessionStart session_id=abcdef1234 cwd="$WM_SANDBOX_DIR/r1" source=startup | bash "$WM_PLUGIN/hooks/session-start")"
  ctx="$(wm_json_str "$raw" hookSpecificOutput.additionalContext)"
  t_eq 'waymark is installed but not set up; run `/waymark:setup`.' "$ctx" "not set up sentence"
  t_contains "$raw" '"hookEventName":"SessionStart"' "event name"
}

test_injects_protocol_and_repo() {
  t_ss_setup
  printf -- '---\ntitle: x\n---\n\n# Your protocol additions\n\nAlways say ahoy.\n' > "$L/PROTOCOL.md"
  t_ss_ctx
  t_contains "$CTX" "# Waymark protocol" "core protocol first line"
  t_contains "$CTX" "Always say ahoy." "layer additions"
  t_not_contains "$CTX" "title: x" "frontmatter stripped"
  t_contains "$CTX" "$L" "layer path"
  t_contains "$CTX" "$L/bin/waymark" "cli path"
  t_contains "$CTX" "repo: alpha" "repo"
  t_contains "$CTX" "tags: expo react" "tags"
  t_contains "$CTX" "session: abcdef12" "session id8"
  t_contains "$CTX" "$L/active/alpha--abcdef12.md" "own active file"
  case "$CTX" in "# Waymark protocol"*) t__pass "protocol is first" ;; *) t__fail "protocol is first" "$CTX" ;; esac
}

test_resume_line() {
  t_ss_setup
  printf '# alpha\n\n**Status:** active\n**Handoff:** fix login loop\n' > "$L/repos/alpha.md"
  t_ss_ctx
  t_contains "$CTX" "Resume: fix login loop" "resume"
  printf '**Handoff:** (written by `waymark handoff`: where things stand)\n' > "$L/repos/alpha.md"
  t_ss_ctx
  t_not_contains "$CTX" "Resume:" "placeholder handoff skipped"
}

test_gotcha_selection() {
  t_ss_setup
  t_ss_gotcha G-0001 open alpha "" "alpha own"
  t_ss_gotcha G-0002 fixed beta "expo" "beta tag match"
  t_ss_gotcha G-0003 open beta "" "beta no tags"
  t_ss_gotcha G-0004 obsolete alpha "" "alpha obsolete"
  t_ss_gotcha G-0005 open all "" "global"
  t_ss_ctx
  t_contains "$CTX" "G-0001  alpha own" "own repo"
  t_contains "$CTX" "G-0002  beta tag match" "tag intersect"
  t_contains "$CTX" "G-0005  global" "repo all"
  t_not_contains "$CTX" "G-0003" "other repo no tags"
  t_not_contains "$CTX" "G-0004" "obsolete"
}

test_gotcha_rank_by_hits() {
  local a b
  t_ss_setup
  t_ss_gotcha G-0001 open alpha "" "older"
  t_ss_gotcha G-0005 open alpha "" "newer"
  t_ss_gotcha G-0006 open alpha "" "newest"
  printf '2026-10-01\ts1\tG-0001\talpha\n2026-10-02\ts2\tG-0001\talpha\n' >> "$L/stats/recall.tsv"
  t_ss_ctx
  a="${CTX%%G-0001*}"; b="${CTX%%G-0005*}"
  [ "${#a}" -lt "${#b}" ] && t__pass "hits first" || t__fail "hits first" "$CTX"
  a="${CTX%%G-0006*}"; b="${CTX%%G-0005*}"
  [ "${#a}" -lt "${#b}" ] && t__pass "then recency" || t__fail "then recency" "$CTX"
}

test_playbook_rules_by_tag() {
  t_ss_setup
  printf '%s\n' '---' 'tag: expo' 'triggers:' '  - eas build' '---' '## Rules' '- Pin the SDK (G-0001)' '- Clear cache' \
    '## Before running a trigger command' '- [ ] check whoami' > "$L/playbooks/expo.md"
  printf '%s\n' '## Rules' '- vite rule' > "$L/playbooks/vite.md"
  t_ss_ctx
  t_contains "$CTX" "- Pin the SDK (G-0001)" "rule present"
  t_contains "$CTX" "- Clear cache" "second rule"
  t_not_contains "$CTX" "check whoami" "checklist absent"
  t_not_contains "$CTX" "vite rule" "other tag absent"
}

test_active_file_created_and_reused() {
  local f="$WM_SANDBOX_DIR/layer/active/alpha--abcdef12.md" s1 s2 n
  t_ss_setup
  t_ss_ctx startup
  t_file_exists "$f" "active file created"
  s1="$(grep '^started:' "$f")"
  t_contains "$(<"$f")" "repo: alpha" "repo field"
  t_contains "$(<"$f")" "status: working" "status field"
  t_contains "$(<"$f")" "session: abcdef12" "session field"
  printf 'handoff: kept\n' >> "$f"
  sleep 1
  t_ss_ctx compact
  s2="$(grep '^started:' "$f")"
  n="$(ls "$L/active" | grep -c '^alpha--')"
  t_eq "1" "$n" "still one file"
  t_eq "$s1" "$s2" "started unchanged"
  t_contains "$(<"$f")" "handoff: kept" "content preserved"
}

test_same_repo_sessions_flagged() {
  t_ss_setup
  printf 'repo: alpha\nsession: bbbb2222\nstatus: working\n' > "$L/active/alpha--bbbb2222.md"
  printf 'repo: beta\nsession: cccc3333\nstatus: waiting\n' > "$L/active/beta--cccc3333.md"
  t_ss_ctx
  t_contains "$CTX" "alpha--bbbb2222 working (same repo)" "same repo flagged"
  t_contains "$CTX" "beta--cccc3333 waiting" "other listed"
  t_not_contains "$CTX" "beta--cccc3333 waiting (same repo)" "other not flagged"
}

test_stale_cleanup() {
  t_ss_setup
  printf 'repo: x\nstatus: working\n' > "$L/active/x--old00000.md"
  printf 'repo: y\nstatus: working\n' > "$L/active/y--new00000.md"
  touch -d '25 hours ago' "$L/active/x--old00000.md"
  touch -d '23 hours ago' "$L/active/y--new00000.md"
  t_ss_ctx
  [ ! -e "$L/active/x--old00000.md" ] && t__pass "25h removed" || t__fail "25h removed"
  t_file_exists "$L/active/y--new00000.md" "23h kept"
  t_contains "$(<"$L/active/.cleanup.log")" "x--old00000.md" "logged"
}

test_notices() {
  t_ss_setup
  printf 'scanner missing\n' > "$L/active/.scan-failed.log"
  printf '%s\n' '## I-zzzz9999-1 — new' '- kind: failure' '- repo: alpha' '' '```' 'x' '```' \
    '## I-zzzz9999-2 — dismissed' '- repo: alpha' '## I-zzzz9999-3 — deferred' '- repo: beta' > "$L/inbox/zzzz9999.md"
  printf '%s\n' '## I-abcdef12-1 — new' '- repo: alpha' > "$L/inbox/abcdef12.md"
  t_ss_ctx
  t_contains "$CTX" ".scan-failed.log" "scan failure notice"
  t_contains "$CTX" "1 untriaged from last session" "untriaged count"
}

test_compact_pending() {
  t_ss_setup
  printf 'x\n' > "$L/active/.compact-pending-abcdef12"
  t_ss_ctx compact
  t_contains "$CTX" "waymark handoff" "handoff instruction"
  t_contains "$CTX" "--session abcdef12" "session flag"
  t_contains "$CTX" "waymark inbox --session abcdef12" "triage instruction"
  [ ! -e "$L/active/.compact-pending-abcdef12" ] && t__pass "marker removed" || t__fail "marker removed"
  printf 'x\n' > "$L/active/.compact-pending-abcdef12"
  t_ss_ctx startup
  t_file_exists "$L/active/.compact-pending-abcdef12" "startup leaves marker"
  t_not_contains "$CTX" "just compacted" "no instruction on startup"
}

# t_ss_budget_check [strict]: every section at its cap; strict also expects them all to survive
t_ss_budget_check() {
  local i n pk=""
  t_ss_setup
  for i in $(seq 1 20); do
    pk="$pk\"d$i\":\"1\","
    printf 'd%s=t%s\n' "$i" "$i" >> "$L/tags.conf"
    printf '%s\n' '## Rules' "- rule for tag $i: $(printf 'r%.0s' $(seq 1 120))" > "$L/playbooks/t$i.md"
  done
  printf '{"dependencies":{%s"expo":"1"}}\n' "${pk%,}" > "$R/package.json"
  printf '**Handoff:** %s\n' "$(printf 'ünï%.0s' $(seq 1 300))" > "$L/repos/alpha.md"
  for i in $(seq 1 3000); do printf 'filler line %s of a big repo file\n' "$i" >> "$L/repos/alpha.md"; done
  for i in $(seq 1 100); do t_ss_gotcha "G-$(printf %04d "$i")" open alpha "" "symptom number $i with some padding text to take space"; done
  printf 'x%.0s' $(seq 1 3000) > "$L/PROTOCOL.md"
  # every section at its cap: compact instruction, many parallel sessions, notices
  printf 'x\n' > "$L/active/.compact-pending-abcdef12"
  for i in $(seq 1 30); do printf 'repo: alpha\nstatus: working\n' > "$L/active/alpha--sess$(printf %04d "$i").md"; done
  printf 'scan\n' > "$L/active/.scan-failed.log"
  printf '## I-zzzz9999-1 — new\n- repo: alpha\n' > "$L/inbox/zzzz9999.md"
  t_ss_ctx compact
  n="$(printf '%s' "$CTX" | LC_ALL=C wc -c)"
  [ "$n" -le 6000 ] && t__pass "context <= 6000 bytes ($n)" || t__fail "context <= 6000 bytes ($n)"
  t_contains "$CTX" "waymark layer: '$L'" "layer identity survives"
  t_contains "$CTX" "waymark CLI: bash '$L/bin/waymark'" "cli identity survives"
  t_contains "$CTX" "active file: '$L/active/alpha--abcdef12.md'" "active file survives"
  [ "${1:-}" = strict ] && t_contains "$CTX" "waymark handoff" "compact instruction survives"
  [ "${1:-}" = strict ] && t_contains "$CTX" "untriaged from last session" "notices survive"
  case "$RAW" in '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"'*'"}}') t__pass "json envelope" ;; *) t__fail "json envelope" "$RAW" ;; esac
  case "$RAW" in *$'\n'*$'\n'*) t__fail "single line" ;; *) t__pass "single line" ;; esac
  [ "${1:-}" = strict ] && t_contains "$CTX" "(truncated; see" "truncation marker"
  t_contains "$CTX" "session: abcdef12" "identity survives"
}

test_outside_repo() {
  CWD="$WM_SANDBOX_DIR/plain"; mkdir -p "$CWD"
  t_ss_setup
  t_ss_gotcha G-0001 open alpha "" "alpha only"
  printf '**Handoff:** nope\n' > "$L/repos/none.md"
  t_ss_ctx
  t_contains "$CTX" "repo: none" "repo none"
  t_not_contains "$CTX" "Resume:" "no resume"
  t_not_contains "$CTX" "tags:" "no tags"
  t_not_contains "$CTX" "G-0001" "no repo gotchas"
  t_file_exists "$L/active/none--abcdef12.md" "active file"
  unset CWD
}

test_broken_path() {
  local raw
  t_ss_setup
  raw="$(t_hook_json SessionStart session_id=abcdef1234 cwd="$R" source=startup | PATH= "$BASH" "$WM_PLUGIN/hooks/session-start")"
  case "$raw" in '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"'*'"}}') t__pass "json with empty PATH" ;; *) t__fail "json with empty PATH" "$raw" ;; esac
  t_contains "$raw" "session: abcdef12" "has injection"
}

test_garbage_stdin() {
  local raw
  t_ss_setup
  raw="$(printf 'not json at all' | (cd "$R" && bash "$WM_PLUGIN/hooks/session-start"))"
  case "$raw" in '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"'*'"}}') t__pass "json on garbage" ;; *) t__fail "json on garbage" "$raw" ;; esac
}

test_launcher() {
  local out rc
  t_ss_setup
  out="$(printf '{}' | bash "$WM_PLUGIN/hooks/run-hook.cmd" no-such-hook)"; rc=$?
  t_eq "0" "$rc" "missing script exit 0"
  t_eq "" "$out" "missing script silent"
  out="$(t_hook_json SessionStart session_id=abcdef1234 cwd="$R" source=startup | bash "$WM_PLUGIN/hooks/run-hook.cmd" session-start)"
  t_contains "$out" "session: abcdef12" "dispatches with stdin"
  t_contains "$(<"$WM_PLUGIN/hooks/hooks.json")" '"matcher": "Bash"' "failure event registered"
}

test_untriaged_skips_live_sessions() {
  t_ss_setup
  printf 'repo: alpha\nstatus: working\n' > "$L/active/alpha--bbbb2222.md"
  printf '%s\n' '## I-bbbb2222-1 — new' '- repo: alpha' > "$L/inbox/bbbb2222.md"
  t_ss_ctx
  t_not_contains "$CTX" "untriaged" "live session's candidates not counted"
  printf '%s\n' '## I-cccc3333-1 — new' '- repo: alpha' '## I-cccc3333-2 — gated' '- repo: alpha' > "$L/inbox/cccc3333.md"
  t_ss_ctx
  t_contains "$CTX" "2 untriaged from last session" "ended session's candidates counted"
}

test_cwd_backslashes_and_space() {
  local win="$WM_SANDBOX_DIR/my repo"
  t_ss_setup
  t_fake_repo "$win"
  if command -v cygpath >/dev/null 2>&1; then win="$(cygpath -w "$win")"; fi
  CWD="$win"
  t_ss_ctx
  t_contains "$CTX" "repo: my repo" "repo from windows-style cwd with space"
  t_file_exists "$L/active/my repo--abcdef12.md" "active file for spaced repo"
  unset CWD
}

test_budget() { t_ss_budget_check strict; }

test_budget_long_layer_path() {
  local i sub="layer"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do sub="segment-number-$i-padding/$sub"; done
  WM_LAYER_SUB="$sub"
  t_ss_budget_check
  t_eq "1" "$([ "${#L}" -gt 300 ] && echo 1 || echo 0)" "layer path is long (${#L})"
  case "$CTX" in *"waymark CLI: bash '"*) ;; *) t__fail "cli line present" ;; esac
}

test_apostrophe_layer_path() {
  local line q
  WM_LAYER_SUB="O'Brien/my layer"
  t_ss_setup
  t_ss_ctx
  line="${CTX#*waymark CLI: bash }"; q="${line%% (the *}"
  t_eq "$L/bin/waymark" "$(eval "printf %s $q")" "quoted cli path round-trips"
  line="${CTX#*active file: }"; q="${line%%$'\n'*}"
  t_eq "$L/active/alpha--abcdef12.md" "$(eval "printf %s $q")" "quoted active file round-trips"
}

test_layer_lib_copy_ignored() {
  local raw ref
  t_ss_setup
  ref="$(t_ss_run session_id=abcdef1234 cwd="$R" source=startup)"
  mkdir -p "$L/bin"
  printf '%s\n' 'echo stale-debug' 'wm_layer_root() { return 1; }' 'exit 3' > "$L/bin/lib.sh"
  raw="$(t_ss_run session_id=abcdef1234 cwd="$R" source=startup)"
  t_eq "$ref" "$raw" "garbage layer bin/lib.sh has no effect"
}

test_guard_internal_failure() {
  local raw rc P="$WM_SANDBOX_DIR/plugincopy"
  t_ss_setup
  mkdir -p "$P"
  cp -r "$WM_PLUGIN/hooks" "$WM_PLUGIN/bin" "$WM_PLUGIN/templates" "$P/"
  sed -i 's|^  layer="\$WM_LAYER"$|&; set -e; false; exit 7|' "$P/hooks/session-start"
  raw="$(t_hook_json SessionStart session_id=abcdef1234 cwd="$R" source=startup | bash "$P/hooks/session-start")"; rc=$?
  t_eq "0" "$rc" "exit 0 on internal failure"
  case "$raw" in '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"'*'"}}') t__pass "valid json on internal failure" ;; *) t__fail "valid json on internal failure" "$raw" ;; esac
  t_contains "$raw" "session: abcdef12" "names the session"
}

#!/usr/bin/env bash
# Tests for hooks/stop and hooks/pre-compact (triage gates)

. "$WM_REPO_ROOT/bin/lib.sh"

wm() { bash "$WM_PLUGIN/bin/waymark" "$@"; }

# t_gate_setup: layer in $L; session abcdef12 owns inbox $INBOX
t_gate_setup() {
  L="$WM_SANDBOX_DIR/layer"; R="$WM_SANDBOX_DIR/alpha"
  mkdir -p "$L/active" "$L/inbox" "$L/stats" "$L/playbooks" "$L/repos"
  printf 'repo_roots=\n' > "$L/layer.conf"
  : > "$L/gotchas.md"
  export WAYMARK_ROOT="$L"
  t_fake_repo "$R"
  INBOX="$L/inbox/abcdef12.md"
}

# t_gate_cand <file> <id8> <n> <state>
t_gate_cand() {
  printf '## I-%s-%s — %s\n- kind: failure\n- repo: alpha\n- time: x\n- command: make\n- exit: 1\n\n```\nboom %s\n```\n\n' \
    "$2" "$3" "$4" "$3" >> "$1"
}

t_stop() { # [session_id] [stop_hook_active]
  t_hook_json Stop session_id="${1:-abcdef1234}" cwd="$R" stop_hook_active:="${2:-false}" last_assistant_message="done" | bash "$WM_PLUGIN/hooks/stop"
}
t_precompact() { t_hook_json PreCompact session_id=abcdef1234 cwd="$R" trigger=auto custom_instructions:=null | bash "$WM_PLUGIN/hooks/pre-compact"; }

test_stop_no_candidates_silent() {
  local out
  t_gate_setup
  out="$(t_stop)"; t_eq "" "$out" "no inbox file"
  : > "$INBOX"
  out="$(t_stop)"; t_eq "" "$out" "empty inbox"
  t_gate_cand "$INBOX" abcdef12 1 dismissed
  t_gate_cand "$INBOX" abcdef12 2 "recorded G-0001"
  out="$(t_stop)"; t_eq "" "$out" "terminal states only"
}

test_stop_blocks_once() {
  local out reason
  t_gate_setup
  t_gate_cand "$INBOX" abcdef12 1 new
  t_gate_cand "$INBOX" abcdef12 2 new
  t_gate_cand "$INBOX" abcdef12 3 deferred
  out="$(t_stop)"
  t_eq block "$(wm_json_str "$out" decision)" "decision"
  reason="$(wm_json_str "$out" reason)"
  t_eq 'Triage 2 waymark candidate(s) before finishing: I-abcdef12-1 I-abcdef12-2. For each run `waymark record … --from <ID>`, `waymark dismiss <ID>`, or `waymark defer <ID>` if still investigating.' "$reason" "exact message"
  t_contains "$(<"$INBOX")" '## I-abcdef12-1 — gated' "first flipped"
  t_contains "$(<"$INBOX")" '## I-abcdef12-2 — gated' "second flipped"
  t_contains "$(<"$INBOX")" '## I-abcdef12-3 — deferred' "deferred untouched"
  t_contains "$(wm inbox --session abcdef12)" 'I-abcdef12-1  gated  alpha  boom 1' "inbox still parses"
  out="$(t_stop)"; t_eq "" "$out" "second stop silent"
  t_gate_cand "$INBOX" abcdef12 4 new
  out="$(t_stop)"
  t_contains "$(wm_json_str "$out" reason)" 'Triage 1 waymark candidate(s) before finishing: I-abcdef12-4.' "new arrival blocks again"
}

test_stop_hook_active_never_blocks() {
  local out
  t_gate_setup
  t_gate_cand "$INBOX" abcdef12 1 new
  t_gate_cand "$INBOX" abcdef12 2 mandatory
  out="$(t_stop abcdef1234 true)"; t_eq "" "$out" "silent when active"
  t_contains "$(<"$INBOX")" '## I-abcdef12-1 — new' "state untouched"
  out="$(t_stop)"
  t_eq block "$(wm_json_str "$out" decision)" "blocks when not active"
}

test_stop_mandatory_repeats_until_recorded() {
  local out
  t_gate_setup
  t_gate_cand "$INBOX" abcdef12 1 mandatory
  t_gate_cand "$INBOX" abcdef12 2 new
  out="$(t_stop)"
  t_contains "$(wm_json_str "$out" reason)" 'Triage 2 waymark candidate(s) before finishing: I-abcdef12-1 I-abcdef12-2.' "lists both in inbox order"
  t_contains "$(<"$INBOX")" '## I-abcdef12-1 — mandatory' "mandatory stays"
  t_contains "$(<"$INBOX")" '## I-abcdef12-2 — gated' "new gated"
  out="$(t_stop)"
  t_contains "$(wm_json_str "$out" reason)" 'Triage 1 waymark candidate(s) before finishing: I-abcdef12-1.' "mandatory blocks again"
  out="$(t_stop)"
  t_contains "$(wm_json_str "$out" reason)" 'I-abcdef12-1.' "and again"
  wm dismiss I-abcdef12-1 >/dev/null
  out="$(t_stop)"; t_eq "" "$out" "silent once dismissed"
}

test_stop_other_session_ignored() {
  local out
  t_gate_setup
  t_gate_cand "$L/inbox/zzzz9999.md" zzzz9999 1 new
  t_gate_cand "$L/inbox/zzzz9999.md" zzzz9999 2 mandatory
  out="$(t_stop)"; t_eq "" "$out" "other session silent"
  t_contains "$(<"$L/inbox/zzzz9999.md")" '## I-zzzz9999-1 — new' "other session untouched"
}

test_precompact_lists_deferred() {
  local out raw ctx m
  t_gate_setup
  m="$L/active/.compact-pending-abcdef12"
  t_gate_cand "$INBOX" abcdef12 1 deferred
  t_gate_cand "$INBOX" abcdef12 2 gated
  t_gate_cand "$INBOX" abcdef12 3 dismissed
  t_gate_cand "$L/inbox/zzzz9999.md" zzzz9999 1 new
  out="$(t_precompact)"
  t_eq "" "$out" "never blocks, no output"
  t_file_exists "$m" "marker written"
  t_eq $'I-abcdef12-1\nI-abcdef12-2' "$(<"$m")" "marker lists open ids only"
  ls "$L/active" | grep -q 'tmp' && t__fail "no temp left" || t__pass "no temp left"
  raw="$(t_hook_json SessionStart session_id=abcdef1234 cwd="$R" source=compact | bash "$WM_PLUGIN/hooks/session-start")"
  ctx="$(wm_json_str "$raw" hookSpecificOutput.additionalContext)"
  t_contains "$ctx" 'waymark inbox --session abcdef12' "instruction injected"
  t_contains "$ctx" 'waymark handoff' "handoff instruction"
  [ ! -e "$m" ] && t__pass "marker removed" || t__fail "marker removed"
}

test_precompact_marker_without_candidates() {
  t_gate_setup
  t_eq "" "$(t_precompact)" "silent"
  t_file_exists "$L/active/.compact-pending-abcdef12" "marker even with zero candidates"
  t_eq "0" "$(wc -c < "$L/active/.compact-pending-abcdef12" | tr -d ' ')" "empty marker"
}

test_gates_no_layer_silent() {
  local out
  t_gate_setup
  export WAYMARK_ROOT="$WM_SANDBOX_DIR/nolayer"
  out="$(t_stop)"; t_eq "" "$out" "stop silent"
  out="$(t_precompact)"; t_eq "" "$out" "pre-compact silent"
  [ ! -e "$WM_SANDBOX_DIR/nolayer" ] && t__pass "nothing created" || t__fail "nothing created"
}

test_gates_wiring() {
  t_contains "$(<"$WM_PLUGIN/hooks/hooks.json")" 'run-hook.cmd\" stop' "stop wired"
  t_contains "$(<"$WM_PLUGIN/hooks/hooks.json")" 'run-hook.cmd\" pre-compact' "pre-compact wired"
}

#!/usr/bin/env bash
# Tests for hooks/user-prompt, hooks/pre-tool, hooks/post-tool (capture and recall)

. "$WM_REPO_ROOT/bin/lib.sh"

wm() { bash "$WM_PLUGIN/bin/waymark" "$@"; }

# t_cap_setup: layer in $L, fake repo "alpha" in $R, active file for session abcdef12
t_cap_setup() {
  L="$WM_SANDBOX_DIR/layer"; R="$WM_SANDBOX_DIR/alpha"
  mkdir -p "$L/playbooks" "$L/stats" "$L/active" "$L/inbox"
  printf 'repo_roots=\nreplace_auto_memory=no\n' > "$L/layer.conf"
  printf 'date\tsession\tid\trepo\n' > "$L/stats/recall.tsv"
  : > "$L/gotchas.md"
  printf 'repo: alpha\nsession: abcdef12\nstarted: x\ntask:\nstatus: working\nfiles touched:\nhandoff:\n' > "$L/active/alpha--abcdef12.md"
  export WAYMARK_ROOT="$L"
  t_fake_repo "$R"
  INBOX="$L/inbox/abcdef12.md"
  ACT="$L/active/alpha--abcdef12.md"
}

t_cap_gotcha() { # id status match [cause] [fix]
  printf '## %s — sym %s\n- **Status:** %s\n- **Repo:** all\n- **Match:** %s\n- **Cause:** %s\n- **Fix:** %s\n\n' \
    "$1" "$1" "$2" "$3" "${4:-the cause}" "${5:-the fix}" >> "$L/gotchas.md"
}

t_prompt() { t_hook_json UserPromptSubmit session_id=abcdef1234 cwd="$R" prompt="$1" | bash "$WM_PLUGIN/hooks/user-prompt"; }
t_pre_bash() { t_hook_json PreToolUse session_id=abcdef1234 cwd="$R" tool_name=Bash tool_input.command="$1" | bash "$WM_PLUGIN/hooks/pre-tool"; }
t_pre_file() { t_hook_json PreToolUse session_id=abcdef1234 cwd="$R" tool_name="$1" tool_input.file_path="$2" | bash "$WM_PLUGIN/hooks/pre-tool"; }
t_post_file() { t_hook_json PostToolUse session_id=abcdef1234 cwd="$R" tool_name="$1" tool_input.file_path="$2" | bash "$WM_PLUGIN/hooks/post-tool"; }
t_post_fail() { # command error [interrupt]
  t_hook_json PostToolUseFailure session_id=abcdef1234 cwd="$R" tool_name=Bash tool_input.command="$1" error="$2" is_interrupt:="${3:-false}" | bash "$WM_PLUGIN/hooks/post-tool"
}

t_count() { # file pattern -> number of matching lines
  local n=0 line
  [ -f "$1" ] || { printf '0'; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do case "$line" in $2) n=$((n + 1)) ;; esac; done < "$1"
  printf '%s' "$n"
}

# ---------------------------------------------------------------- user-prompt

test_remember_creates_mandatory() {
  local out ctx
  t_cap_setup
  out="$(t_prompt 'Please remember that we deploy with pnpm, not npm')"
  ctx="$(wm_json_str "$out" hookSpecificOutput.additionalContext)"
  t_contains "$out" '"hookEventName":"UserPromptSubmit"' "event name"
  t_contains "$ctx" 'The user asked you to remember something. Record it with `waymark record' "context text"
  t_contains "$ctx" '--from <ID>`) before you reply.' "context text tail"
  t_contains "$(<"$INBOX")" '## I-abcdef12-1 — mandatory' "mandatory heading"
  t_contains "$(<"$INBOX")" '- kind: remember' "kind"
  t_contains "$(<"$INBOX")" '- repo: alpha' "repo"
  t_contains "$(<"$INBOX")" 'we deploy with pnpm' "prompt text kept"
  t_contains "$(wm inbox --session abcdef12)" 'I-abcdef12-1  mandatory  alpha  Please remember that we deploy' "waymark inbox parses it"
  t_prompt 'for future: use pnpm' >/dev/null
  t_contains "$(<"$INBOX")" '## I-abcdef12-2 — mandatory' "second id increments"
  t_eq "I-abcdef12-1 dismissed" "$(wm dismiss I-abcdef12-1)" "dismiss works on it"
}

test_remember_word_boundaries() {
  local out
  t_cap_setup
  out="$(t_prompt 'I remembered the keys. Also rememberance day.')"
  t_eq "" "$out" "remembered/rememberance do not trigger"
  t_eq "0" "$(t_count "$INBOX" '## I-*')" "no candidate"
  out="$(t_prompt 'Remember: use tabs')"
  t_contains "$out" "remember something" "Remember: triggers"
  out="$(t_prompt "DON'T FORGET the tests")"
  t_contains "$out" "remember something" "dont forget with apostrophe, upper case"
  out="$(t_prompt $'line one\nnote that two')"
  t_contains "$out" "remember something" "after a newline"
  out="$(t_prompt 'dont forget')"
  t_contains "$out" "remember something" "dont forget"
  out="$(t_prompt 'fine, nothing special here')"
  t_eq "" "$out" "ordinary prompt silent"
}

# ------------------------------------------------------------------- pre-tool

test_trigger_checklist() {
  local out ctx
  t_cap_setup
  printf '%s\n' '---' 'tag: eas' 'triggers:            # regexes' '  - eas (build|submit)' '---' '## Rules' '- a rule' \
    '## Before running a trigger command' '- [ ] check whoami (G-0012)' '- [ ] bump version' '## Other' '- [ ] not this' > "$L/playbooks/eas.md"
  out="$(t_pre_bash 'eas build --platform ios')"
  ctx="$(wm_json_str "$out" hookSpecificOutput.additionalContext)"
  t_contains "$out" '"hookEventName":"PreToolUse"' "event name"
  t_contains "$ctx" 'Checklist before `eas build --platform ios` (playbooks/eas.md):' "header"
  t_contains "$ctx" '- [ ] check whoami (G-0012)' "item 1"
  t_contains "$ctx" '- [ ] bump version' "item 2"
  t_not_contains "$ctx" 'not this' "other sections excluded"
  t_not_contains "$ctx" 'a rule' "rules excluded"
  t_contains "$(t_pre_bash 'cd x && eas submit')" 'check whoami' "second alternative inside a chain"
}

test_no_trigger_no_output() {
  local out
  t_cap_setup
  printf '%s\n' '---' 'tag: eas' 'triggers:' '  - eas (build|submit)' '---' '## Before running a trigger command' '- [ ] x' > "$L/playbooks/eas.md"
  out="$(t_pre_bash 'ls -la')"
  t_eq "" "$out" "non-matching command"
  out="$(t_pre_bash 'easy build')"
  t_eq "" "$out" "near miss"
  rm -f "$L/playbooks/eas.md"
  out="$(t_pre_bash 'eas build')"
  t_eq "" "$out" "no playbooks"
  out="$(t_pre_file Write "$R/a.txt")"
  t_eq "" "$out" "plain Write"
}

test_memory_write_denied_only_when_on() {
  local out mem="$HOME/.claude/projects/p/memory/MEMORY.md"
  t_cap_setup
  out="$(t_pre_file Write "$mem")"
  t_eq "" "$out" "replace_auto_memory=no: no output"
  printf 'repo_roots=\nreplace_auto_memory=yes\n' > "$L/layer.conf"
  out="$(t_pre_file Write "$mem")"
  t_contains "$out" '"permissionDecision":"deny"' "on: deny"
  t_contains "$(wm_json_str "$out" hookSpecificOutput.permissionDecisionReason)" 'waymark replaces built-in auto-memory here. Use `waymark record' "reason"
  out="$(t_pre_file Edit 'C:\Users\x\.claude\projects\p\memory\MEMORY.md')"
  t_contains "$out" '"permissionDecision":"deny"' "backslash path denied"
  out="$(t_pre_file Write "$R/src/memory/notes.md")"
  t_eq "" "$out" "other memory dir untouched"
  out="$(t_pre_file Write "$HOME/.claude/projects/p/other.md")"
  t_eq "" "$out" "projects but not memory"
  out="$(t_pre_file Write "$CLAUDE_CONFIG_DIR/projects/p/memory/MEMORY.md")"
  t_contains "$out" '"permissionDecision":"deny"' "CLAUDE_CONFIG_DIR store denied"
  out="$(t_pre_file Write "$CLAUDE_CONFIG_DIR/projects/p/other.md")"
  t_eq "" "$out" "CLAUDE_CONFIG_DIR, non-memory path under projects allowed"
  out="$(CLAUDE_CONFIG_DIR='C:\Users\Me\cfg' t_pre_file Write 'c:\users\me\CFG\Projects\p\Memory\MEMORY.md')"
  t_contains "$out" '"permissionDecision":"deny"' "config dir: backslashes, drive letter and case"
  out="$(CLAUDE_CONFIG_DIR='C:\Users\Me\cfg' t_pre_file Write '/c/Users/Me/cfg/projects/p/memory/MEMORY.md')"
  t_contains "$out" '"permissionDecision":"deny"' "config dir C:/ vs /c/ form"
  out="$(t_pre_file Write 'C:\Users\x\.Claude\projects\p\MEMORY\MEMORY.md')"
  t_contains "$out" '"permissionDecision":"deny"' ".Claude / MEMORY case variants denied"
  out="$(t_pre_file Write 'C:\Users\x\.claude\projects\p\notes.md')"
  t_eq "" "$out" "non-memory path under .claude/projects allowed"
  out="$(t_pre_bash 'ls')"
  t_eq "" "$out" "Bash with no playbooks while replacing memory: silent"
}

# ------------------------------------------------------------------ post-tool

test_files_touched_dedup() {
  t_cap_setup
  mkdir -p "$R/src"
  t_post_file Write "$R/src/a.ts"
  t_post_file Edit "$R/src/a.ts"
  t_post_file Edit "$R/src/b.ts"
  t_post_file Write 'C:\other\place\c.txt'
  t_eq "files touched: src/a.ts, src/b.ts, C:/other/place/c.txt" "$(grep '^files touched:' "$ACT")" "deduplicated, repo-relative"
  # another repo's file is not the session repo's: it stays absolute
  t_fake_repo "$WM_SANDBOX_DIR/beta"
  mkdir -p "$WM_SANDBOX_DIR/beta/src"
  t_post_file Edit "$WM_SANDBOX_DIR/beta/src/a.ts"
  t_contains "$(grep '^files touched:' "$ACT")" ", $WM_SANDBOX_DIR/beta/src/a.ts" "file in another repo stays absolute"
  t_contains "$(grep '^files touched:' "$ACT")" "files touched: src/a.ts, " "session repo file still relative"
  t_eq "1" "$(t_count "$ACT" 'repo: alpha')" "rest of file kept"
  t_eq "1" "$(t_count "$ACT" 'handoff:')" "handoff line kept"
  rm -f "$ACT"
  t_eq "" "$(t_post_file Write "$R/src/a.ts")" "missing active file: silent"
  t_eq "0" "$(ls "$L/active" | wc -l | tr -d ' ')" "and not created"
}

test_failure_captured() {
  local out
  t_cap_setup
  out="$(t_post_fail 'npm test' $'Exit code 2\nline one\nline two')"
  t_eq "" "$out" "no gotcha: no output"
  t_contains "$(<"$INBOX")" '## I-abcdef12-1 — new' "heading"
  t_contains "$(<"$INBOX")" '- kind: failure' "kind"
  t_contains "$(<"$INBOX")" '- repo: alpha' "repo"
  t_contains "$(<"$INBOX")" '- command: npm test' "command"
  t_contains "$(<"$INBOX")" '- exit: 2' "exit code"
  t_contains "$(<"$INBOX")" $'line one\nline two' "output lines"
  t_not_contains "$(<"$INBOX")" 'Exit code' "prefix stripped from output"
  t_contains "$(wm inbox --session abcdef12)" 'I-abcdef12-1  new  alpha  line one' "waymark inbox parses it"
  t_eq "I-abcdef12-1 deferred" "$(wm defer I-abcdef12-1)" "defer works"
  out="$(t_post_fail 'sleep 100' 'Exit code 130' true)"
  t_eq "1" "$(t_count "$INBOX" '## I-*')" "interrupt not captured"
}

test_failure_dedup_same_command() {
  t_cap_setup
  t_post_fail 'make all' $'Exit code 1\nboom'
  t_post_fail 'make all' $'Exit code 1\nboom again'
  t_eq "1" "$(t_count "$INBOX" '## I-*')" "same command once"
  t_post_fail 'make other' $'Exit code 1\nboom'
  t_eq "2" "$(t_count "$INBOX" '## I-*')" "different command added"
  t_contains "$(<"$INBOX")" '## I-abcdef12-2 — new' "id increments"
  wm dismiss I-abcdef12-1 >/dev/null
  t_post_fail 'make all' $'Exit code 1\nboom'
  t_eq "2" "$(t_count "$INBOX" '## I-*')" "still deduplicated after dismiss"
}

test_success_ignored() {
  local out
  t_cap_setup
  out="$(t_hook_json PostToolUse session_id=abcdef1234 cwd="$R" tool_name=Bash tool_input.command='echo hi' tool_response.stdout=hi tool_response.interrupted:=false | bash "$WM_PLUGIN/hooks/post-tool")"
  t_eq "" "$out" "no output"
  t_eq "0" "$(t_count "$INBOX" '*')" "no inbox"
  out="$(printf '%s\n' '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"abcdef1234","tool_response":{"stdout":"Exit code 1"}}' | bash "$WM_PLUGIN/hooks/post-tool")"
  t_eq "" "$out" "field order does not matter"
  t_eq "0" "$(t_count "$INBOX" '*')" "still no inbox"
}

test_bash_failed_helper() {
  local j
  j='{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"Exit code 127\ncommand not found","is_interrupt":false}'
  t_eq "127" "$(wm_bash_failed "$j")" "failure prints the code"
  wm_bash_failed "$j" >/dev/null; t_eq "0" "$?" "failure rc 0"
  j='{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"Exit code 1","is_interrupt":true}'
  wm_bash_failed "$j" >/dev/null; t_eq "1" "$?" "interrupt is not a failure"
  j='{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":{"stdout":"ok"}}'
  wm_bash_failed "$j" >/dev/null; t_eq "1" "$?" "success is not a failure"
  j='{"hook_event_name":"PostToolUseFailure","tool_name":"Write","error":"Exit code 1"}'
  wm_bash_failed "$j" >/dev/null; t_eq "1" "$?" "other tools are not Bash failures"
}

test_recall_by_match() {
  local out ctx
  t_cap_setup
  t_cap_gotcha G-0001 open 'Unable to resolve module' 'metro cache is stale' 'run expo start -c'
  t_cap_gotcha G-0002 open 'something else entirely'
  out="$(t_post_fail 'npx expo start' $'Exit code 1\nError: Unable to resolve module react-native')"
  ctx="$(wm_json_str "$out" hookSpecificOutput.additionalContext)"
  t_contains "$out" '"hookEventName":"PostToolUseFailure"' "event name"
  t_contains "$ctx" 'Known gotcha matches this failure:' "intro"
  t_contains "$ctx" '## G-0001 — sym G-0001' "heading"
  t_contains "$ctx" 'metro cache is stale' "cause"
  t_contains "$ctx" 'run expo start -c' "fix"
  t_not_contains "$ctx" 'G-0002' "non-matching excluded"
  t_eq "2" "$(t_count "$L/stats/recall.tsv" '*')" "recall.tsv header + 1 line"
  t_contains "$(<"$L/stats/recall.tsv")" $'\tabcdef12\tG-0001\talpha' "recall line fields"
  t_eq "1" "$(t_count "$INBOX" '## I-*')" "still captured"
}

test_recall_max_three() {
  local out i
  t_cap_setup
  for i in 1 2 3 4 5; do t_cap_gotcha "G-000$i" open 'common failure text'; done
  out="$(t_post_fail 'x' $'Exit code 1\ncommon failure text')"
  t_contains "$out" 'G-0003' "third hit"
  t_not_contains "$out" 'G-0004' "fourth not included"
  t_eq "4" "$(t_count "$L/stats/recall.tsv" '*')" "header + 3 lines"
}

test_recall_skips_obsolete() {
  local out
  t_cap_setup
  t_cap_gotcha G-0001 obsolete 'Unable to resolve module'
  t_cap_gotcha G-0002 fixed 'Unable to resolve module'
  out="$(t_post_fail 'x' $'Exit code 1\nUnable to resolve module a')"
  t_not_contains "$out" 'G-0001' "obsolete skipped"
  t_contains "$out" 'G-0002' "fixed still recalled"
  printf '<!--\n## G-0099 — example\n- **Status:** open\n- **Match:** in a comment\n-->\n' >> "$L/gotchas.md"
  out="$(t_post_fail 'y' $'Exit code 1\nin a comment')"
  t_not_contains "$out" 'G-0099' "format examples in comments ignored"
}

test_recall_crlf_output() {
  local out
  t_cap_setup
  printf '## G-0001 — sym\r\n- **Status:** open\r\n- **Match:** Unable to resolve module\r\n- **Cause:** c1\r\n- **Fix:** f1\r\n\r\n' > "$L/gotchas.md"
  out="$(t_post_fail 'x' $'Exit code 1\r\nerror: Unable to resolve module\r\nnext\r\n')"
  t_contains "$out" 'G-0001' "CRLF gotchas and output"
  t_not_contains "$out" '\r' "no CR in context"
  t_not_contains "$(<"$INBOX")" $'\r' "no CR in inbox"
}

test_huge_output() {
  local f="$WM_SANDBOX_DIR/big.json" t0 t1 size
  t_cap_setup
  t_cap_gotcha G-0001 open 'Unable to resolve module'
  awk 'BEGIN { printf "{\"session_id\":\"abcdef1234\",\"cwd\":\"x\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"big\"},\"error\":\"Exit code 1\\nUnable to resolve module\\n"; for (i = 0; i < 61000; i++) printf "%s\\n", sprintf("%80s", "x"); printf "\",\"is_interrupt\":false,\"duration_ms\":5}\n" }' > "$f"
  awk -v r="$R" '{ sub(/"cwd":"x"/, "\"cwd\":\"" r "\""); print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  size="$(wc -c < "$f" | tr -d ' ')"
  [ "$size" -gt 4900000 ] && t__pass "payload is ~5 MB" || t__fail "payload is ~5 MB" "$size"
  t0="$(date +%s%N 2>/dev/null)"
  bash "$WM_PLUGIN/hooks/post-tool" < "$f" > "$WM_SANDBOX_DIR/out.txt"
  t1="$(date +%s%N 2>/dev/null)"
  case "$t0$t1" in
    *[!0-9]*) t__pass "no ns clock; timing skipped" ;;
    *) [ $(( (t1 - t0) / 1000000 )) -lt 1500 ] && t__pass "hook fast on 5 MB (~0.5 s idle; 1.5 s bound for loaded CI)" || t__fail "hook fast on 5 MB" "$(( (t1 - t0) / 1000000 )) ms" ;;
  esac
  size="$(wc -c < "$INBOX" | tr -d ' ')"
  [ "$size" -le 4600 ] && t__pass "candidate bounded ($size bytes)" || t__fail "candidate bounded" "$size bytes"
  t_contains "$(<"$WM_SANDBOX_DIR/out.txt")" 'G-0001' "recall still works"
  t_eq "1" "$(t_count "$INBOX" '## I-*')" "one candidate"
}

test_binary_output() {
  local out rc
  t_cap_setup
  t_cap_gotcha G-0001 open 'Unable to resolve module'
  out="$(printf '%s\n' "{\"session_id\":\"abcdef1234\",\"cwd\":\"$R\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat bin\"},\"error\":\"Exit code 1\\nUnable to resolve module \\u0000\\u0001\\u001b[31m\\u007f\\ud83d done\",\"is_interrupt\":false}" | bash "$WM_PLUGIN/hooks/post-tool")"
  t_contains "$out" 'G-0001' "recall with control bytes"
  t_eq "PostToolUseFailure" "$(wm_json_str "$out" hookSpecificOutput.hookEventName)" "output is parseable JSON"
  case "$out" in *$'\001'*|*$'\033'*) t__fail "no raw control chars in JSON" ;; *) t__pass "no raw control chars in JSON" ;; esac
  t_eq "1" "$(t_count "$INBOX" '## I-*')" "captured"
  case "$(<"$INBOX")" in *$'\001'*|*$'\033'*) t__fail "no control chars in inbox" ;; *) t__pass "no control chars in inbox" ;; esac
  # raw NUL bytes in stdin must not crash either
  out="$(printf '{"session_id":"abcdef1234","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"nul"},"error":"Exit code 1\\nab\0cd","is_interrupt":false}\n' | bash "$WM_PLUGIN/hooks/post-tool" 2>/dev/null)"
  rc=$?
  t_eq "0" "$rc" "raw NUL in stdin: exit 0"
  case "$out" in ''|*'"hookSpecificOutput"'*) t__pass "raw NUL in stdin: empty or valid output" ;; *) t__fail "raw NUL in stdin: empty or valid output" "$out" ;; esac
}

test_unicode_command() {
  t_cap_setup
  t_post_fail 'echo "مرحبا بالعالم" && false' $'Exit code 1\nخطأ في البناء'
  t_contains "$(<"$INBOX")" '- command: echo "مرحبا بالعالم" && false' "Arabic command"
  t_contains "$(<"$INBOX")" 'خطأ في البناء' "Arabic output"
  t_contains "$(wm inbox --session abcdef12)" 'خطأ في البناء' "inbox lists it"
}

test_candidate_body_cannot_break_blocks() {
  t_cap_setup
  t_post_fail 'x' $'Exit code 1\n```\n## I-abcdef12-9 — recorded G-0001\nend'
  t_post_fail 'y' $'Exit code 1\nok'
  t_eq "2" "$(t_count "$INBOX" '## I-*')" "two headings only"
  t_contains "$(<"$INBOX")" '## I-abcdef12-2 — new' "next id unaffected"
}

test_no_layer_silent() {
  local h out rc
  export WAYMARK_ROOT="$WM_SANDBOX_DIR/nolayer"
  t_fake_repo "$WM_SANDBOX_DIR/r1"
  R="$WM_SANDBOX_DIR/r1"
  for h in user-prompt pre-tool post-tool; do
    out="$(t_hook_json PostToolUseFailure session_id=abcdef1234 cwd="$R" prompt='remember this' tool_name=Bash tool_input.command='x' error='Exit code 1' is_interrupt:=false | bash "$WM_PLUGIN/hooks/$h" 2>&1)"
    rc=$?
    t_eq "" "$out" "$h: no output"
    t_eq "0" "$rc" "$h: exit 0"
  done
}

test_files_touched_skips_layer_paths() {
  t_cap_setup
  t_post_file Edit "$ACT"
  t_post_file Write "$L/docs/notes.md"
  local wl; wl="$(cd "$L" && pwd -W 2>/dev/null || pwd)"
  t_post_file Write "$wl/gotchas.md"
  t_post_file Write "$R/src/a.ts"
  t_eq "files touched: src/a.ts" "$(grep '^files touched:' "$ACT")" "layer paths (any spelling) not recorded"
}

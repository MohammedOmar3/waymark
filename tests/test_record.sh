#!/usr/bin/env bash
# Tests for bin/cmd/record.sh and bin/cmd/triage.sh

wm() { bash "$WM_PLUGIN/bin/waymark" "$@"; }

# t_rec_setup: layer in $L, fake repo "myapp" in $R, cwd = $R
t_rec_setup() {
  L="$WM_SANDBOX_DIR/layer"; R="$WM_SANDBOX_DIR/myapp"
  bash "$WM_PLUGIN/bin/waymark" init --owner-name "Test Owner" --owner-email "owner@example.org" \
    --root "$L" --plugin-root "$WM_PLUGIN" >/dev/null 2>&1
  t_fake_repo "$R" '{"dependencies":{"expo":"1","react-native":"2"}}'
  cd "$R" || return 1
}

t_rec_gotcha() { # [extra args]
  wm record gotcha --symptom "Build fails on eas" --cause "Stale cache" --fix "Clear it" \
    --match "ERR_CACHE" "$@"
}

# t_rec_cand <id8> : inbox file with two candidates
t_rec_cand() {
  mkdir -p "$L/inbox"
  printf '%s\n' '## I-abcd1234-1 — new' '- kind: failure' '- repo: myapp' '- time: 2026-10-28T10:00:00' \
    '- command: npm run build' '- exit: 1' '' '```' '' 'error: ENOENT missing thing' 'second line' '```' '' \
    '## I-abcd1234-2 — mandatory' '- kind: remember' '- repo: other' '- time: 2026-10-28T10:01:00' \
    '- command: ' '- exit: 0' '' '```' 'remember to bump version' '```' > "$L/inbox/abcd1234.md"
}

test_record_gotcha_format() {
  local id out want
  t_rec_setup
  id="$(t_rec_gotcha)"
  t_eq "G-0001" "$id" "first id"
  out="$(t_rec_gotcha --status open --repo all --tags "a,b")"
  t_eq "G-0002" "$out" "second id"
  want="## G-0001 — Build fails on eas
- **Status:** fixed
- **Repo:** myapp
- **Tags:** expo, react-native
- **Match:** ERR_CACHE
- **Symptom:** Build fails on eas
- **Cause:** Stale cache
- **Fix:** Clear it
- **First hit:** $(date +%Y-%m-%d)"
  t_contains "$(cat "$L/gotchas.md")" "$want" "block field order"
  t_contains "$(cat "$L/gotchas.md")" "- **Status:** open
- **Repo:** all
- **Tags:** a, b" "second block flags"
}

test_record_defaults_repo_tags() {
  t_rec_setup
  t_rec_gotcha >/dev/null
  t_contains "$(cat "$L/gotchas.md")" "- **Repo:** myapp" "repo default"
  t_contains "$(cat "$L/gotchas.md")" "- **Tags:** expo, react-native" "tags default"
  t_contains "$(cat "$L/gotchas.md")" "- **Status:** fixed" "status default"
}

test_record_missing_field() {
  local before out rc
  t_rec_setup
  before="$(cat "$L/gotchas.md")"
  out="$(wm record gotcha --symptom s --cause c --match m 2>&1)"; rc=$?
  t_eq 2 "$rc" "exit 2"
  t_contains "$out" "--fix" "names field"
  t_eq "$before" "$(cat "$L/gotchas.md")" "nothing written"
  t_exit 2 "decision missing" -- wm record decision --decision d
  t_exit 2 "convention missing" -- wm record convention
}

test_record_from_candidate() {
  local out
  t_rec_setup
  t_rec_cand
  out="$(wm record gotcha --from I-abcd1234-1 --symptom s --cause c --fix f)"
  t_eq "G-0001" "$out" "id"
  t_contains "$(cat "$L/gotchas.md")" "- **Match:** error: ENOENT missing thing" "match from first output line"
  t_contains "$(cat "$L/inbox/abcd1234.md")" "## I-abcd1234-1 — recorded G-0001" "state recorded"
  t_contains "$(cat "$L/inbox/abcd1234.md")" "## I-abcd1234-2 — mandatory" "other untouched"
  t_exit 2 "unknown candidate" -- wm record gotcha --from I-abcd1234-9 --symptom s --cause c --fix f
}

test_record_concurrent_ids() {
  local a b
  t_rec_setup
  t_rec_gotcha >/dev/null  # G-0001 baseline
  (WAYMARK_TEST_ID_DELAY=0.5 t_rec_gotcha > "$WM_SANDBOX_DIR/o1" 2>&1) &
  (WAYMARK_TEST_ID_DELAY=0.5 t_rec_gotcha > "$WM_SANDBOX_DIR/o2" 2>&1) &
  wait
  a="$(cat "$WM_SANDBOX_DIR/o1")"; b="$(cat "$WM_SANDBOX_DIR/o2")"
  t_eq "G-0002 G-0003" "$(printf '%s\n%s\n' "$a" "$b" | sort | tr '\n' ' ' | sed 's/ $//')" "distinct ids"
  t_eq 1 "$(grep -c '^## G-0002 ' "$L/gotchas.md")" "G-0002 once"
  t_eq 1 "$(grep -c '^## G-0003 ' "$L/gotchas.md")" "G-0003 once"
  t_eq "" "$(git -C "$L" status --porcelain)" "tree clean"
}

test_status_edits_one_line() {
  local d
  t_rec_setup
  t_rec_gotcha >/dev/null
  t_rec_gotcha >/dev/null
  wm status G-0002 obsolete >/dev/null
  t_eq 0 "$?" "status ok"
  d="$(git -C "$L" diff HEAD~1 HEAD -U0 -- gotchas.md | grep -E '^[+-]' | grep -v -E '^(\+\+\+|---) ')"
  t_eq "-- **Status:** fixed
+- **Status:** obsolete" "$d" "one line changed"
  t_contains "$(sed -n '/^## G-0001/,/^## G-0002/p' "$L/gotchas.md")" "Status:** fixed" "G-0001 untouched"
  t_exit 2 "unknown id" -- wm status G-0009 open
  t_exit 2 "bad status" -- wm status G-0001 weird
}

test_record_commits() {
  t_rec_setup
  t_rec_gotcha >/dev/null
  t_eq "memory: G-0001 Build fails on eas" "$(git -C "$L" log -1 --format=%s)" "commit message"
  t_eq "" "$(git -C "$L" status --porcelain)" "clean"
}

test_record_scan_failure() {
  local rc
  t_rec_setup
  wm record gotcha --symptom s --cause c --fix "password = hunter2x" --match m >/dev/null 2>&1
  rc=$?
  t_eq 2 "$rc" "exit 2"
  t_contains "$(cat "$L/gotchas.md")" "## G-0001 — s" "entry kept"
  t_contains "$(git -C "$L" status --porcelain)" "gotchas.md" "uncommitted"
  t_file_exists "$L/active/.scan-failed.log" "scan log"
}

test_record_crlf_existing_file() {
  local out
  t_rec_setup
  printf -- '---\r\ntitle: G\r\n---\r\n\r\n## G-0007 — old\r\n- **Status:** open\r\n' > "$L/gotchas.md"
  git -C "$L" add -A; git -C "$L" commit -q -m crlf
  out="$(t_rec_gotcha)"
  t_eq "G-0008" "$out" "next id after CRLF"
  wm status G-0007 fixed >/dev/null
  t_contains "$(cat "$L/gotchas.md")" "- **Status:** fixed" "crlf status edited"
}

test_inbox_dismiss_defer() {
  local out
  t_rec_setup
  t_rec_cand
  out="$(wm inbox)"
  t_contains "$out" "I-abcd1234-1  new  myapp  error: ENOENT missing thing" "row 1"
  t_contains "$out" "I-abcd1234-2  mandatory  other  remember to bump version" "row 2"
  wm dismiss I-abcd1234-1 >/dev/null
  wm defer I-abcd1234-2 >/dev/null
  out="$(wm inbox --session abcd1234)"
  t_not_contains "$out" "I-abcd1234-1" "dismissed hidden"
  t_contains "$out" "I-abcd1234-2  deferred" "deferred listed"
  t_eq "" "$(WAYMARK_SESSION=zzzz9999 wm inbox)" "other session empty"
  t_contains "$(WAYMARK_SESSION=zzzz9999 wm inbox --all)" "I-abcd1234-2" "--all"
  t_contains "$(cat "$L/inbox/abcd1234.md")" "## I-abcd1234-1 — dismissed" "file state"
  t_exit 2 "dismiss unknown" -- wm dismiss I-abcd1234-7
}

test_handoff_sets_field() {
  local f
  t_rec_setup
  f="$L/active/myapp--abcd1234.md"
  printf 'repo: myapp\nsession: abcd1234\nstarted: x\ntask: t\nstatus: working\nfiles touched:\nhandoff:\n' > "$f"
  wm handoff "stopped at step 3" --session abcd1234 >/dev/null
  t_contains "$(cat "$f")" "handoff: stopped at step 3" "set"
  t_eq 1 "$(grep -c '^handoff:' "$f")" "single line"
  WAYMARK_SESSION=abcd1234 wm handoff "next: ship" >/dev/null
  t_contains "$(cat "$f")" "handoff: next: ship" "env session"
  printf 'repo: myapp\nsession: abcd1234\n' > "$f"
  wm handoff "added" --session abcd1234 >/dev/null
  t_contains "$(cat "$f")" "handoff: added" "created when missing"
  t_exit 2 "no active file" -- wm handoff x --session ffff0000
  t_exit 2 "no session" -- wm handoff x
}

test_record_retro_and_convention() {
  local d c
  t_rec_setup
  d="$(wm record retro --doc docs/x.md --worked w --surprised s --change c)"
  t_eq "D-0001" "$d" "retro id"
  t_contains "$(cat "$L/decisions.md")" "- **Kind:** retro" "retro kind"
  t_contains "$(cat "$L/decisions.md")" "- **What surprised us:** s" "retro field"
  d="$(wm record decision --decision "Use X" --chose "X over Y" --because b --constraint k --revisit r)"
  t_eq "D-0002" "$d" "decision id"
  t_contains "$(cat "$L/decisions.md")" "- **Doc:** none" "doc none"
  t_contains "$(cat "$L/decisions.md")" "- **Constraint that forced it:** k" "constraint line"
  c="$(wm record convention --rule "Use tabs" --why "house style")"
  t_eq "C-0001" "$c" "convention id"
  t_contains "$(cat "$L/conventions.md")" "## C-0001 — Use tabs
- **Repo:** myapp
- **Tags:** expo, react-native
- **Rule:** Use tabs
- **Because:** house style" "convention block"
  t_eq "memory: C-0001 Use tabs" "$(git -C "$L" log -1 --format=%s)" "convention commit"
}

test_record_value_safety() {
  local sym fix id2
  t_rec_setup
  sym='pipe | dash — home $HOME nl \n bs \\ end \t مرحبا'
  fix='fix `x` | "q" — $(echo no) \\server\share \n مرحبا'
  wm record gotcha --symptom "$sym" --cause c --fix "$fix" --match m >/dev/null
  t_eq 0 "$?" "record ok"
  t_eq 1 "$(grep -c -x -F -e "- **Symptom:** $sym" "$L/gotchas.md")" "symptom byte-identical"
  t_eq 1 "$(grep -c -x -F -e "- **Fix:** $fix" "$L/gotchas.md")" "fix byte-identical"
  id2="$(t_rec_gotcha)"
  t_eq "G-0002" "$id2" "next id after odd values"
}

test_record_utf8_truncation() {
  local sym="" i subj
  t_rec_setup
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do sym="${sym}مرحبا"; done
  wm record gotcha --symptom "$sym" --cause c --fix f --match m >/dev/null
  t_eq 0 "$?" "record ok"
  subj="$(git -C "$L" log -1 --format=%s)"
  t_contains "$subj" "memory: G-0001 " "subject prefix"
  if command -v iconv >/dev/null 2>&1; then
    printf '%s' "$subj" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1
    t_eq 0 "$?" "subject valid utf-8"
    grep '^## G-0001 ' "$L/gotchas.md" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1
    t_eq 0 "$?" "heading valid utf-8"
  fi
}

test_handoff_preserves_crlf() {
  local f="$WM_SANDBOX_DIR/layer/active/myapp--abcd1234.md"
  t_rec_setup
  printf 'repo: myapp\r\nhandoff: old\r\nstatus: x\r\n' > "$f"
  wm handoff "new text" --session abcd1234 >/dev/null
  # grep/awk text-mode on Git Bash hides CR, so count raw bytes with tr
  t_eq 3 "$(tr -cd '\r' < "$f" | wc -c | tr -d ' ')" "crlf kept on all lines"
  t_eq "handoff: new text" "$(tr -d '\r' < "$f" | grep '^handoff:')" "text replaced"
}

test_commit_command() {
  t_rec_setup
  printf 'x\n' > "$L/playbooks/note.md"
  t_eq "ok" "$(wm commit "manual save")" "prints ok"
  t_eq "manual save" "$(git -C "$L" log -1 --format=%s)" "committed"
}

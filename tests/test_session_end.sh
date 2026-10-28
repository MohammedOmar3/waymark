#!/usr/bin/env bash
# Tests for hooks/session-end (worklog entry, handoff copy, cleanup, autosave)

. "$WM_REPO_ROOT/bin/lib.sh"

wm() { bash "$WM_PLUGIN/bin/waymark" "$@"; }

# t_se_setup: git layer in $L (scanner copied in, committed clean), repo in $R
t_se_setup() {
  L="$WM_SANDBOX_DIR/layer"; R="$WM_SANDBOX_DIR/alpha"
  mkdir -p "$L/active" "$L/inbox" "$L/stats" "$L/repos"
  printf 'repo_roots=\n' > "$L/layer.conf"
  printf 'active/\n.locks/\n' > "$L/.gitignore"
  : > "$L/gotchas.md"
  cp "$WM_PLUGIN/templates/layer/worklog.md" "$L/worklog.md"
  cp "$WM_PLUGIN/templates/layer/repos/_template.md" "$L/repos/_template.md"
  cp -R "$WM_PLUGIN/bin" "$L/bin"
  git -C "$L" init -q -b main 2>/dev/null || git -C "$L" init -q
  git -C "$L" add -A && git -C "$L" commit -q -m init
  export WAYMARK_ROOT="$L"
  GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" t_fake_repo "$R"
  STARTED="2025-01-01T00:00:00"
  SID=abcdef1234
}

# t_se_active <repo> <task> <files> <handoff> [id8]
t_se_active() {
  printf 'repo: %s\nsession: %s\nstarted: %s\ntask: %s\nstatus: working\nfiles touched: %s\nhandoff: %s\n' \
    "$1" "${5:-abcdef12}" "$STARTED" "$2" "$3" "$4" > "$L/active/$1--${5:-abcdef12}.md"
}

# t_se_run [cwd]: fire the hook synchronously (autosave in the foreground)
t_se_run() {
  t_hook_json SessionEnd session_id="$SID" cwd="${1:-$R}" reason=other | WAYMARK_SESSION_END_SYNC=1 bash "$WM_PLUGIN/hooks/session-end"
}

t_se_commit() { # <msg>
  printf '%s\n' "$1" >> "$R/f.txt"; git -C "$R" add -A; git -C "$R" commit -q -m "$1"
}

t_se_cand() { # <n> <state>
  printf '## I-abcdef12-%s — %s\n- kind: failure\n- repo: alpha\n- time: x\n- command: make\n- exit: 1\n\n```\nboom\n```\n\n' "$1" "$2" >> "$L/inbox/abcdef12.md"
}

test_worklog_entry_fields() {
  t_se_setup
  t_se_commit "first change"; t_se_commit "second change"
  t_se_active alpha "ship login" "src/a.ts, src/b.ts, /other/c.ts" "next: add tests"
  t_se_cand 1 recorded; t_se_cand 2 dismissed; t_se_cand 3 deferred
  printf 'date\tsession\tid\trepo\n2026-10-28\tabcdef12\tG-0001\talpha\n2026-10-28\tabcdef12\tG-0002\talpha\n2026-10-28\tzzzzzzzz\tG-0001\talpha\n' > "$L/stats/recall.tsv"
  local out; out="$(t_se_run 2>&1)"
  t_eq "" "$out" "hook prints nothing"
  local wl; wl="$(<"$L/worklog.md")"
  local subj; subj="$(git -C "$R" log -n 2 --format='%h %s' | tr '\n' '|')"
  local h2 h1; h1="${subj%%|*}"; h2="${subj#*|}"; h2="${h2%|}"
  t_contains "$wl" " — alpha — ship login" "heading has repo and task"
  case "$wl" in *"## "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "[0-9][0-9]:[0-9][0-9]" — alpha — ship login"*) t__pass "heading date format" ;; *) t__fail "heading date format" "$wl" ;; esac
  t_contains "$wl" "- **Session:** abcdef12, $STARTED to 20" "session line"
  t_contains "$wl" ", status working" "session status"
  t_contains "$wl" "- **Commits:** $h1; $h2" "commits line"
  t_contains "$wl" "- **Files touched:** 3 (src/a.ts, src/b.ts, /other/c.ts)" "files line"
  t_contains "$wl" "- **Capture:** 3 candidates, 1 recorded, 1 dismissed, 1 deferred" "capture line"
  t_contains "$wl" "- **Recall hits:** 2" "recall line"
  t_contains "$wl" "- **Handoff:** next: add tests" "handoff line"
}

test_handoff_copied_to_repo_file() {
  t_se_setup
  t_se_active alpha "t" "" "pick up at step 3"
  printf '# alpha\n\n**Status:** active\n**Handoff:** old\n**Other:** keep\n' > "$L/repos/alpha.md"
  t_se_run
  local f; f="$(<"$L/repos/alpha.md")"
  t_contains "$f" "**Handoff:** pick up at step 3" "handoff replaced"
  t_not_contains "$f" "old" "old handoff gone"
  t_contains "$f" "**Other:** keep" "other lines kept"
}

test_repo_file_created_from_template() {
  t_se_setup
  t_se_active alpha "t" "" "resume here"
  t_se_run
  local f; f="$(<"$L/repos/alpha.md")"
  t_contains "$f" "title: alpha" "template repo substituted in frontmatter"
  t_contains "$f" "# alpha" "template heading"
  t_contains "$f" "**Handoff:** resume here" "handoff line set"
  t_not_contains "$f" "<repo>" "no placeholder left"
  t_contains "$f" "**What it is:**" "template body kept"
}

test_active_file_deleted() {
  t_se_setup
  t_se_active alpha "t" "" ""
  t_se_active alpha "other" "" "" 99999999
  t_se_run
  t_eq "no" "$([ -e "$L/active/alpha--abcdef12.md" ] && echo yes || echo no)" "own active file deleted"
  t_file_exists "$L/active/alpha--99999999.md" "other session's active file kept"
  t_eq "no" "$([ -e "$L/.locks/active-abcdef12" ] && echo yes || echo no)" "lock released"
}

test_autosave_commits() {
  t_se_setup
  t_se_active alpha "t" "" "h"
  t_se_run
  t_eq "chore: autosave session abcdef12" "$(git -C "$L" log -1 --format=%s)" "autosave commit"
  t_eq "" "$(git -C "$L" status --porcelain)" "layer clean"
}

test_autosave_refuses_secret() {
  t_se_setup
  t_se_active alpha "t" "" "h"
  printf 'password = hunter2x\n' > "$L/gotchas.md"
  local before; before="$(git -C "$L" rev-list --count HEAD)"
  t_se_run; local rc=$?
  t_eq 0 "$rc" "exit 0"
  t_eq "$before" "$(git -C "$L" rev-list --count HEAD)" "no new commit"
  t_file_exists "$L/active/.scan-failed.log" "scan-failed log written"
  t_contains "$(<"$L/active/.session-end.log")" "autosave refused" "failure logged"
}

test_session_end_no_layer_silent() {
  t_se_setup
  export WAYMARK_ROOT="$WM_SANDBOX_DIR/nope"
  local out rc
  out="$(t_se_run 2>&1)"; rc=$?
  t_eq 0 "$rc" "exit 0"
  t_eq "" "$out" "silent"
}

test_session_end_outside_repo() {
  t_se_setup
  local plain="$WM_SANDBOX_DIR/plain"; mkdir -p "$plain"
  t_se_active none "scratch" "" ""
  local out; out="$(t_se_run "$plain" 2>&1)"
  t_eq "" "$out" "silent"
  local wl; wl="$(<"$L/worklog.md")"
  t_contains "$wl" " — none — scratch" "heading uses repo none"
  t_contains "$wl" "- **Commits:** none" "commits none"
  t_contains "$wl" "- **Handoff:** none" "handoff none"
  t_eq "no" "$([ -e "$L/repos/none.md" ] && echo yes || echo no)" "no repo file for none"
}

test_session_end_double_fire_once() {
  t_se_setup
  t_se_active alpha "t" "" "h"
  t_se_run; t_se_run
  local n; n="$(grep -c -F -e '- **Session:** abcdef12,' "$L/worklog.md")"
  t_eq 1 "$n" "one entry after two fires"
}

test_session_end_missing_active() {
  t_se_setup
  t_se_run; local rc=$?
  t_eq 0 "$rc" "exit 0"
  local wl; wl="$(<"$L/worklog.md")"
  t_contains "$wl" " — alpha — untitled" "untitled task"
  t_contains "$wl" "- **Session:** abcdef12, unknown to 20" "unknown started"
  t_contains "$wl" "- **Commits:** none" "no commits without started"
}

test_stats_counts_after_session_end() {
  t_se_setup
  t_se_active alpha "t" "" "h"
  t_se_cand 1 recorded; t_se_cand 2 dismissed; t_se_cand 3 deferred; t_se_cand 4 new
  printf 'date\tsession\tid\trepo\n2026-10-28\tabcdef12\tG-0001\talpha\n' > "$L/stats/recall.tsv"
  t_se_run
  local out; out="$(wm stats)"
  t_contains "$out" "Worklog entries: 1" "entry counted"
  t_contains "$out" "Candidates: 4" "candidates"
  t_contains "$out" "Recorded: 1" "recorded"
  t_contains "$out" "Dismissed: 1" "dismissed"
  t_contains "$out" "Deferred: 1" "deferred"
  t_contains "$out" "Recall hits: 1" "recall hits"
}

test_session_end_background_autosave() {
  t_se_setup
  t_se_active alpha "t" "" "h"
  local out
  out="$(t_hook_json SessionEnd session_id="$SID" cwd="$R" reason=other | bash "$WM_PLUGIN/hooks/session-end" 2>&1)"
  t_eq "" "$out" "silent"
  t_contains "$(<"$L/worklog.md")" "abcdef12" "worklog written synchronously"
  local i=0 subj=""
  while [ $i -lt 100 ]; do
    subj="$(git -C "$L" log -1 --format=%s)"
    [ "$subj" = "chore: autosave session abcdef12" ] && break
    sleep 0.1; i=$((i + 1))
  done
  t_eq "chore: autosave session abcdef12" "$subj" "background autosave landed"
}

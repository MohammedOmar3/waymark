#!/usr/bin/env bash
# Tests for bin/lib.sh

t_lib() { . "$WM_PLUGIN/bin/lib.sh"; }

t_mk_layer() { mkdir -p "$1"; printf 'version=1\n' > "$1/layer.conf"; }

test_layer_root_order() {
  t_lib
  t_exit 1 "no layer anywhere -> exit 1" -- wm_layer_root
  local def="$CLAUDE_CONFIG_DIR/waymark" conf="$WM_SANDBOX_DIR/conflayer" env="$WM_SANDBOX_DIR/envlayer"
  mkdir -p "$def"   # no layer.conf: must be skipped
  t_exit 1 "default without layer.conf skipped" -- wm_layer_root
  t_mk_layer "$def"
  t_eq "$def" "$(wm_layer_root)" "default layer used"
  t_mk_layer "$conf"
  printf 'root=%s\n' "$conf" > "$CLAUDE_CONFIG_DIR/waymark.conf"
  t_eq "$conf" "$(wm_layer_root)" "conf beats default"
  mkdir -p "$env"
  export WAYMARK_ROOT="$env"
  t_eq "$conf" "$(wm_layer_root)" "env candidate without layer.conf skipped"
  t_mk_layer "$env"
  t_eq "$env" "$(wm_layer_root)" "env beats conf"
  unset WAYMARK_ROOT
  t_eq "$CLAUDE_CONFIG_DIR" "$(wm_config_home)" "config home from CLAUDE_CONFIG_DIR"
  unset CLAUDE_CONFIG_DIR
  t_eq "$HOME/.claude" "$(wm_config_home)" "config home default"
}

test_conf_get_crlf() {
  t_lib
  local f="$WM_SANDBOX_DIR/c.conf"
  printf 'owner_email=a@b.c\r\nother=x=y\r\n' > "$f"
  t_eq "a@b.c" "$(wm_conf_get "$f" owner_email)" "crlf stripped"
  t_eq "x=y" "$(wm_conf_get "$f" other)" "value keeps ="
  t_exit 1 "absent key -> 1" -- wm_conf_get "$f" nope
  t_exit 1 "absent file -> 1" -- wm_conf_get "$WM_SANDBOX_DIR/none" owner_email
}

test_conf_set() {
  t_lib
  local f="$WM_SANDBOX_DIR/s.conf"
  wm_conf_set "$f" a 1
  wm_conf_set "$f" b "two words"
  wm_conf_set "$f" a 3
  t_eq "3" "$(wm_conf_get "$f" a)" "replace existing"
  t_eq "two words" "$(wm_conf_get "$f" b)" "append keeps value"
  t_eq "2" "$(grep -c . "$f" | tr -d ' ')" "no duplicate lines"
}

test_repo_name_worktree() {
  t_lib
  local d="$WM_SANDBOX_DIR/w"
  t_fake_repo "$d/alpha"
  git -C "$d/alpha" worktree add -q "$d/alpha-wt" 2>/dev/null
  t_eq "alpha" "$(wm_repo_name "$d/alpha")" "main worktree"
  t_eq "alpha" "$(wm_repo_name "$d/alpha-wt")" "linked worktree"
  mkdir -p "$d/alpha/sub/deep"
  t_eq "alpha" "$(wm_repo_name "$d/alpha/sub/deep")" "subdirectory"
  mkdir -p "$d/plain"
  t_eq "none" "$(wm_repo_name "$d/plain")" "non-git dir"
  t_fake_repo "$d/Engineering Roadmap"
  t_eq "Engineering Roadmap" "$(wm_repo_name "$d/Engineering Roadmap")" "spaces in name"
  ( cd "$d/alpha" && t_eq "alpha" "$(wm_repo_name)" "default dir is cwd" )
}

test_repo_tags() {
  t_lib
  local layer="$WM_SANDBOX_DIR/layer"
  t_mk_layer "$layer"
  export WAYMARK_ROOT="$layer"
  printf '# comment\nexpo*=expo\n@supabase/*=supabase\n' > "$layer/tags.conf"
  t_fake_repo "$WM_SANDBOX_DIR/app" '{
  "name": "app",
  "dependencies": { "expo": "^52", "expo-router": "^4", "@supabase/supabase-js": "^2" },
  "devDependencies": {
    "left-pad": "1.0.0"
  }
}'
  t_eq "expo supabase" "$(wm_repo_tags "$WM_SANDBOX_DIR/app")" "tags mapped, sorted, unique"
  mkdir -p "$WM_SANDBOX_DIR/nopkg"
  t_eq "" "$(wm_repo_tags "$WM_SANDBOX_DIR/nopkg")" "no package.json -> empty"
}

test_json_str_escapes() {
  t_lib
  local j='{"tool_input":{"command":"echo \"a\\b\"\nnext \u00e9"}}'
  t_eq 'echo "a\b"
next é' "$(wm_json_str "$j" tool_input.command)" "escapes decoded"
  t_exit 1 "missing key -> 1" -- wm_json_str "$j" tool_input.nope
  t_exit 1 "missing parent -> 1" -- wm_json_str "$j" nope.command
  local k='{"k":"a\tb\r\/c \u0627\u0644 \u20ac"}'
  t_eq "$(printf 'a\tb\r/c \xd8\xa7\xd9\x84 \xe2\x82\xac')" "$(wm_json_str "$k" k)" "tab cr slash and multibyte \\u"
}

test_json_pretty_and_nested() {
  t_lib
  local j='{
  "session_id": "abc-123",
  "cwd" : "C:\\Users\\x",
  "tool_input": {
    "file_path": "/a b/c.md",
    "inner": { "deep": "yes", "list": [ {"id": "first"}, {"id": "second"} ] },
    "command": "ls"
  },
  "stop_hook_active": true,
  "flag": false,
  "n": 42,
  "x": null,
  "tool_response": {"stdout":"hi, \"there\"","interrupted":false}
}'
  t_eq "abc-123" "$(wm_json_str "$j" session_id)" "top-level, pretty"
  t_eq 'C:\Users\x' "$(wm_json_str "$j" cwd)" "windows path unescaped"
  t_eq "/a b/c.md" "$(wm_json_str "$j" tool_input.file_path)" "one level"
  t_eq "yes" "$(wm_json_str "$j" tool_input.inner.deep)" "two levels"
  t_eq "second" "$(wm_json_str "$j" tool_input.inner.list.1.id)" "array index"
  t_eq "ls" "$(wm_json_str "$j" tool_input.command)" "key after nested object"
  t_eq 'hi, "there"' "$(wm_json_str "$j" tool_response.stdout)" "comma and quote inside string"
  t_eq "true" "$(wm_json_bool "$j" stop_hook_active)" "bool true"
  t_eq "false" "$(wm_json_bool "$j" flag)" "bool false"
  t_eq "false" "$(wm_json_bool "$j" tool_response.interrupted)" "nested bool"
  t_exit 1 "bool on string -> 1" -- wm_json_bool "$j" session_id
  t_eq "42" "$(wm_json_num "$j" n)" "number"
  t_exit 1 "num on string -> 1" -- wm_json_num "$j" session_id
  t_exit 1 "null str -> 1" -- wm_json_str "$j" x
  t_exit 1 "str of object -> 1" -- wm_json_str "$j" tool_input
  local k='{"a":"x","a2":"wrong","ab":{"a":"nested"}}'
  t_eq "x" "$(wm_json_str "$k" a)" "no prefix confusion"
  t_eq "nested" "$(wm_json_str "$k" ab.a)" "same key name nested"
}

test_json_escape_roundtrip() {
  t_lib
  local s
  s="$(printf 'q"uote back\\slash\ttab\nnew\rcr \x01ctl\x1f /slash مرحبا بالعالم')"
  local e; e="$(wm_json_escape "$s")"
  t_not_contains "$e" $'\n' "no raw newline in escaped"
  t_not_contains "$e" $'\t' "no raw tab in escaped"
  t_eq "$s" "$(wm_json_str "{\"k\":\"$e\"}" k)" "escape/unescape roundtrip"
  t_eq 'a\"b\\c\nd' "$(wm_json_escape "$(printf 'a"b\\c\nd')")" "basic escape shape"
}

test_emit() {
  t_lib
  t_eq '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"hi \"x\"\nz"}}' \
    "$(wm_emit_context SessionStart "$(printf 'hi "x"\nz')")" "emit_context"
  t_eq '{"decision":"block","reason":"stop"}' "$(wm_emit_block stop)" "emit_block"
  t_eq '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no"}}' \
    "$(wm_emit_deny no)" "emit_deny"
}

test_path() {
  t_lib
  t_eq "/tmp/x y/z" "$(wm_path "/tmp/x y/z")" "posix unchanged"
  t_eq "" "$(wm_path "")" "empty"
  if command -v cygpath >/dev/null 2>&1; then
    t_eq "/c/Users/x/a b/c.md" "$(wm_path 'C:\Users\x\a b\c.md')" "windows path via cygpath"
    t_eq "/c/Users/x" "$(wm_path 'C:/Users/x')" "drive with forward slashes"
  fi
  t_eq "a/b/c" "$(wm_path 'a\b\c')" "relative backslashes"
}

test_now_today() {
  t_lib
  case "$(wm_now)" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]) t_eq ok ok "wm_now format" ;; *) t_eq ok "$(wm_now)" "wm_now format" ;; esac
  case "$(wm_today)" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) t_eq ok ok "wm_today format" ;; *) t_eq ok "$(wm_today)" "wm_today format" ;; esac
}

test_lock_contention() {
  t_lib
  local layer="$WM_SANDBOX_DIR/layer" f="$WM_SANDBOX_DIR/out" ctr="$WM_SANDBOX_DIR/ctr"
  t_mk_layer "$layer"; export WAYMARK_ROOT="$layer"
  : > "$f"; printf '0' > "$ctr"
  worker() {
    local i n
    for i in $(seq 1 20); do
      wm_lock x || { echo "LOCKFAIL" >> "$f"; return 1; }
      n="$(cat "$ctr")"; printf '%s' $((n+1)) > "$ctr"
      echo "$1 $i" >> "$f"
      wm_unlock x
    done
  }
  worker a & worker b & wait
  t_eq "40" "$(wc -l < "$f" | tr -d ' ')" "40 lines"
  t_eq "40" "$(cat "$ctr")" "no lost increments"
  t_not_contains "$(cat "$f")" LOCKFAIL "no lock failures"
  t_eq "no" "$([ -d "$layer/.locks/x" ] && echo yes || echo no)" "lock released"
}

test_lock_stale_and_giveup() {
  t_lib
  local layer="$WM_SANDBOX_DIR/layer"
  t_mk_layer "$layer"; export WAYMARK_ROOT="$layer"
  mkdir -p "$layer/.locks/held"
  local t0=$SECONDS
  t_exit 1 "fresh held lock -> give up" -- wm_lock held
  local dt=$((SECONDS-t0))
  if [ "$dt" -ge 3 ]; then t_eq ok ok "gave up after retries (${dt}s)"; else t_eq ">=3s" "${dt}s" "gave up after retries"; fi
  if touch -d '2 minutes ago' "$layer/.locks/held" 2>/dev/null; then
    t_exit 0 "stale lock removed and taken" -- wm_lock held
  fi
}

t_mk_git_layer() {
  local layer="$1"
  t_mk_layer "$layer"
  git -C "$layer" init -q -b main 2>/dev/null || git -C "$layer" init -q
  printf 'active/\n.locks/\n' > "$layer/.gitignore"
  git -C "$layer" add -A && git -C "$layer" commit -q -m init
}

test_commit_basic() {
  t_lib
  local layer="$WM_SANDBOX_DIR/layer"
  t_mk_git_layer "$layer"; export WAYMARK_ROOT="$layer"
  t_exit 0 "no changes -> 0" -- wm_commit "noop"
  t_eq "1" "$(git -C "$layer" rev-list --count HEAD)" "no commit made"
  printf 'x\n' > "$layer/n.md"
  wm_commit "add n"; t_eq 0 "$?" "changes committed (scan absent = pass)"
  t_eq "add n" "$(git -C "$layer" log -1 --format=%s)" "commit message"
  t_eq "" "$(git -C "$layer" status --porcelain)" "tree clean"
}

test_commit_scan_gate() {
  t_lib
  local layer="$WM_SANDBOX_DIR/layer"
  t_mk_git_layer "$layer"; export WAYMARK_ROOT="$layer"
  mkdir -p "$layer/bin" "$layer/active"
  printf '#!/usr/bin/env bash\necho "secret found"\nexit 1\n' > "$layer/bin/waymark"
  printf 'x\n' > "$layer/n.md"
  wm_commit "blocked"; t_eq 2 "$?" "scan failure -> 2"
  t_contains "$(cat "$layer/active/.scan-failed.log")" "secret found" "findings logged"
  t_eq "1" "$(git -C "$layer" rev-list --count HEAD)" "nothing committed"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$layer/bin/waymark"
  wm_commit "ok now"; t_eq 0 "$?" "scan pass -> 0"
  t_eq "no" "$([ -e "$layer/active/.scan-failed.log" ] && echo yes || echo no)" "scan log removed"
}

test_commit_index_lock_retry() {
  t_lib
  local layer="$WM_SANDBOX_DIR/layer"
  t_mk_git_layer "$layer"; export WAYMARK_ROOT="$layer"
  printf 'x\n' > "$layer/n.md"
  : > "$layer/.git/index.lock"
  ( sleep 0.3; rm -f "$layer/.git/index.lock" ) &
  wm_commit "after lock"; t_eq 0 "$?" "lock cleared in time -> 0"
  wait
  printf 'y\n' > "$layer/m.md"
  : > "$layer/.git/index.lock"
  wm_commit "never"; t_eq 3 "$?" "lock never cleared -> 3"
  rm -f "$layer/.git/index.lock"
}

test_json_read_batch() {
  t_lib
  local j='{
  "session_id": "sid-1",
  "cwd": "C:\\Users\\x",
  "tool_input": {"command": "echo \"hi\"\nthere", "file-path": "/a b"},
  "stop_hook_active": true,
  "n": 7,
  "x": null
}'
  local J_session_id="stale" J__missing
  wm_json_read "$j" J session_id cwd tool_input.command stop_hook_active n tool_input.file-path x nope.key
  t_eq "sid-1" "$J_session_id" "read: top-level"
  t_eq 'C:\Users\x' "$J_cwd" "read: unescaped path"
  t_eq 'echo "hi"
there' "$J_tool_input_command" "read: nested string"
  t_eq "true" "$J_stop_hook_active" "read: bool"
  t_eq "7" "$J_n" "read: number"
  t_eq "/a b" "$J_tool_input_file_path" "read: hyphen sanitized"
  t_eq "" "$J_x" "read: null is empty"
  t_eq "x nope.key" "$J__missing" "read: missing list"
  # spawn count: shim awk with a counting wrapper
  local bin="$WM_SANDBOX_DIR/shim" cnt="$WM_SANDBOX_DIR/awkcount" real
  real="$(command -v awk)"
  mkdir -p "$bin"; : > "$cnt"
  printf '#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n' "$cnt" "$real" > "$bin/awk"; chmod +x "$bin/awk"
  PATH="$bin:$PATH" wm_json_read "$j" J session_id cwd tool_input.command stop_hook_active n
  t_eq "1" "$(wc -l < "$cnt" | tr -d ' ')" "read: five keys use one awk spawn"
  t_eq "" "$(wm_json_str '{"k":null}' k)" "str on null prints nothing"
}

test_json_large_input_linear() {
  t_lib
  local big j t0 t1
  big="$(head -c 1048576 /dev/zero | tr '\0' 'a')"
  j='{"session_id":"sid","tool_input":{"file_path":"/p/q.txt","content":"'"$big"'","tail":"end"},"hook_event_name":"PreToolUse"}'
  t0=$(date +%s%N 2>/dev/null || echo 0)
  wm_json_read "$j" J session_id tool_input.file_path tool_input.tail hook_event_name
  t1=$(date +%s%N 2>/dev/null || echo 0)
  t_eq "sid|/p/q.txt|end|PreToolUse" "$J_session_id|$J_tool_input_file_path|$J_tool_input_tail|$J_hook_event_name" "1MB input parsed correctly"
  local ms=$(( (t1 - t0) / 1000000 ))
  echo "  timing: 1MB wm_json_read = ${ms} ms" >&2
  if [ "$ms" -lt 1000 ]; then t_eq ok ok "1MB under 1s (${ms} ms)"; else t_eq "<1000ms" "${ms}ms" "1MB under 1s"; fi
  # multibyte content must not change cost class
  local ar; ar="$(printf 'مرحبا%.0s' $(seq 1 20000))"
  j='{"a":"'"$ar"'","b":"ok"}'
  t0=$(date +%s%N); wm_json_read "$j" K b; t1=$(date +%s%N)
  ms=$(( (t1 - t0) / 1000000 ))
  echo "  timing: ${#j}-char Arabic input = ${ms} ms" >&2
  if [ "$ms" -lt 1000 ] && [ "$K_b" = ok ]; then t_eq ok ok "multibyte input under 1s"; else t_eq "ok<1s" "$K_b ${ms}ms" "multibyte input under 1s"; fi
}

test_repo_name_fallback_toplevel() {
  t_lib
  local d="$WM_SANDBOX_DIR/f"
  mkdir -p "$d"
  git init -q --separate-git-dir="$d/sep.git" "$d/proj" 2>/dev/null
  t_eq "proj" "$(wm_repo_name "$d/proj")" "separate git dir falls back to toplevel"
  t_eq "proj" "$(CDPATH="$d" wm_repo_name "$d/proj")" "CDPATH does not matter"
}

test_lock_stale_steal_race() {
  t_lib
  local layer="$WM_SANDBOX_DIR/layer" ctr="$WM_SANDBOX_DIR/ctr" f="$WM_SANDBOX_DIR/out"
  t_mk_layer "$layer"; export WAYMARK_ROOT="$layer"
  mkdir -p "$layer/.locks/s"
  touch -d '2 minutes ago' "$layer/.locks/s" 2>/dev/null || { t_eq ok ok "touch -d unsupported; skipped"; return 0; }
  printf '0' > "$ctr"; : > "$f"
  worker() {
    local i n
    for i in 1 2 3 4 5 6 7 8 9 10; do
      wm_lock s || { echo LOCKFAIL >> "$f"; return 1; }
      n="$(cat "$ctr")"; sleep 0.02; printf '%s' $((n+1)) > "$ctr"
      wm_unlock s
    done
  }
  worker & worker & worker & wait
  t_eq "30" "$(cat "$ctr")" "no lost increments with 3 waiters on a stale lock"
  t_not_contains "$(cat "$f")" LOCKFAIL "no lock failures"
  t_eq "" "$(ls "$layer/.locks")" "no leftover lock or stale dirs"
}

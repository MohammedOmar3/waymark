#!/usr/bin/env bash
test_harness_runs() {
  t_eq 1 1 "harness runs"
}

test_sandbox_isolated() {
  local real="${WM_REAL_HOME:-}"
  if [ -n "$real" ] && [ "$HOME" != "$real" ]; then t_eq ok ok "HOME differs from real home"; else t_eq differs same "HOME differs from real home"; fi
  if [ -e "$HOME/.claude" ]; then t_eq absent present "sandbox HOME/.claude absent"; else t_eq absent absent "sandbox HOME/.claude absent"; fi
}

test_hook_json_raw_values() {
  local j; j="$(t_hook_json Stop 'stop_hook_active:=true' 'n:=3' 'x:=null' 'tool_input.command=echo "a\b"
z' 'tool_input.flag:=false' 'note=a=b')"
  local out
  out="$(printf '%s' "$j" | python -c 'import sys,json;d=json.load(sys.stdin);print(d["stop_hook_active"] is True, d["n"]==3, d["x"] is None, d["tool_input"]["flag"] is False, d["note"], repr(d["tool_input"]["command"]))' 2>&1)"
  t_eq 'True True True True a=b '"'"'echo "a\\b"\nz'"'" "$out" "hook_json raw and string values valid"
}

test_runner_fails_on_broken_or_empty() {
  local d="$HOME/fx"; mkdir -p "$d"
  printf 'test_a() {\n  if then\n}\n' > "$d/test_broken.sh"
  printf '# nothing\nhelper() { :; }\n' > "$d/test_empty.sh"
  printf 'test_ok() { t_eq 1 1 fx; }\n' > "$d/test_good.sh"
  local out rc
  out="$(WM_TEST_DIR="$d" bash "$WM_PLUGIN/tests/run.sh" broken 2>&1)"; rc=$?
  t_eq 1 "$rc" "syntax-error file fails run"
  t_contains "$out" "FAIL  test_broken: failed to load" "syntax-error FAIL row"
  out="$(WM_TEST_DIR="$d" bash "$WM_PLUGIN/tests/run.sh" empty 2>&1)"; rc=$?
  t_eq 1 "$rc" "no-test file fails run"
  t_contains "$out" "defines no test_* functions" "no-test FAIL row"
  out="$(WM_TEST_DIR="$d" bash "$WM_PLUGIN/tests/run.sh" good 2>&1)"; rc=$?
  t_eq 0 "$rc" "good file passes"
  mkdir -p "$d/none"
  out="$(WM_TEST_DIR="$d/none" bash "$WM_PLUGIN/tests/run.sh" 2>&1)"; rc=$?
  t_eq 1 "$rc" "zero tests fails run"
  t_contains "$out" "no tests were run" "zero-test FAIL row"
}

#!/usr/bin/env bash
test_harness_runs() {
  t_eq 1 1 "harness runs"
}

test_sandbox_isolated() {
  local real="${WM_REAL_HOME:-}"
  if [ -n "$real" ] && [ "$HOME" != "$real" ]; then t_eq ok ok "HOME differs from real home"; else t_eq differs same "HOME differs from real home"; fi
  if [ -e "$HOME/.claude" ]; then t_eq absent present "sandbox HOME/.claude absent"; else t_eq absent absent "sandbox HOME/.claude absent"; fi
}

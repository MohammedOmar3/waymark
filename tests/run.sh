#!/usr/bin/env bash
# Usage: bash tests/run.sh [name...]   runs test_<name>.sh from tests/ (all if none)
# WM_TEST_DIR overrides the directory holding test files (used to test the runner).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tdir="${WM_TEST_DIR:-$here}"
export WM_REAL_HOME="$HOME"
WM_RESULTS="$(mktemp)"; export WM_RESULTS
. "$here/lib.sh" || exit 2

files=()
if [ $# -eq 0 ]; then
  for f in "$tdir"/test_*.sh; do [ -e "$f" ] && files+=("$f"); done
else
  for n in "$@"; do files+=("$tdir/test_${n}.sh"); done
fi

total=0
for f in "${files[@]}"; do
  base="$(basename "$f" .sh)"
  if [ ! -f "$f" ]; then
    t__fail "$base: file missing"; continue
  fi
  decl="$(bash -c '. "$1" || exit 99; declare -F' _ "$f" 2>&1)"
  rc=$?
  if [ $rc -ne 0 ]; then
    t__fail "$base: failed to load (exit $rc)" "$decl"; continue
  fi
  fns="$(printf '%s\n' "$decl" | awk '$1=="declare" && $2=="-f"{print $3}' | grep '^test_')"
  if [ -z "$fns" ]; then
    t__fail "$base: defines no test_* functions"; continue
  fi
  for fn in $fns; do
    total=$((total+1))
    (
      t_sandbox
      . "$f"
      "$fn"
    ) || t__fail "$base:$fn exited non-zero"
  done
done

if [ "$total" -eq 0 ]; then t__fail "no tests were run"; fi
t_summary
rc=$?
rm -f "$WM_RESULTS"
exit $rc

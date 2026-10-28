#!/usr/bin/env bash
# Usage: bash tests/run.sh [name...]   runs tests/test_<name>.sh (all if none)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WM_REAL_HOME="$HOME"
. "$here/lib.sh" || exit 2
WM_RESULTS="$(mktemp)"; export WM_RESULTS

files=()
if [ $# -eq 0 ]; then
  for f in "$here"/test_*.sh; do [ -e "$f" ] && files+=("$f"); done
else
  for n in "$@"; do files+=("$here/test_${n}.sh"); done
fi

for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    t__fail "missing test file: $f"; continue
  fi
  fns="$(bash -c '. "$1"; declare -F' _ "$f" 2>/dev/null | awk '{print $3}' | grep '^test_')"
  for fn in $fns; do
    (
      t_sandbox
      . "$f"
      "$fn"
    ) || t__fail "$(basename "$f" .sh):$fn exited non-zero"
  done
done

t_summary
rc=$?
rm -f "$WM_RESULTS"
exit $rc

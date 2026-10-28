#!/usr/bin/env bash
# waymark test harness. Source this file; see tests/run.sh.
# Results are appended to $WM_RESULTS as "PASS|name" / "FAIL|name" lines so
# that each test can run in its own subshell.

WM_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${WM_RESULTS:=$(mktemp)}"
export WM_RESULTS

t_sandbox() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/home" "$d/claude" "$d/tmp"
  export HOME="$d/home"
  export CLAUDE_CONFIG_DIR="$d/claude"
  export TMPDIR="$d/tmp"
  printf '[user]\n\tname = Waymark Test\n\temail = test@waymark.invalid\n[init]\n\tdefaultBranch = main\n' > "$d/gitconfig"
  export GIT_CONFIG_GLOBAL="$d/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  export WM_PLUGIN="$WM_REPO_ROOT"
  unset WAYMARK_ROOT
  WM_SANDBOX_DIR="$d"
  trap 't_cleanup' EXIT
}

t_cleanup() {
  [ -n "${WM_SANDBOX_DIR:-}" ] && [ -d "$WM_SANDBOX_DIR" ] && rm -rf "$WM_SANDBOX_DIR"
  return 0
}

t__pass() { printf 'PASS|%s\n' "$1" >> "$WM_RESULTS"; }
t__fail() {
  printf 'FAIL|%s\n' "$1" >> "$WM_RESULTS"
  printf '  FAIL: %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '%s\n' "$2" >&2
  return 0
}

t_eq() {
  if [ "$1" = "$2" ]; then t__pass "$3"; else t__fail "$3" "    expected: [$1]
    actual:   [$2]"; fi
}

t_contains() {
  case "$1" in *"$2"*) t__pass "$3" ;; *) t__fail "$3" "    missing: [$2]
    in: [$1]" ;; esac
}

t_not_contains() {
  case "$1" in *"$2"*) t__fail "$3" "    unexpected: [$2]
    in: [$1]" ;; *) t__pass "$3" ;; esac
}

t_file_exists() {
  if [ -e "$1" ]; then t__pass "$2"; else t__fail "$2" "    no such path: $1"; fi
}

# t_exit <code> <name> -- <cmd...>
t_exit() {
  local want="$1" name="$2"
  shift 2
  [ "${1:-}" = "--" ] && shift
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then t__pass "$name"; else t__fail "$name" "    expected exit $want, got $got"; fi
}

# t_fake_repo <dir> [package.json content]
t_fake_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main 2>/dev/null || { git -C "$dir" init -q && git -C "$dir" symbolic-ref HEAD refs/heads/main; }
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" > "$dir/package.json"; fi
  printf 'fake\n' > "$dir/README.md"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "init" --allow-empty
}

t__json_escape() {
  local s="$1"
  local bs='\' dq='"'
  s="${s//"$bs"/"$bs$bs"}"
  s="${s//"$dq"/"$bs$dq"}"
  s="${s//$'\n'/"${bs}n"}"
  s="${s//$'\r'/"${bs}r"}"
  s="${s//$'\t'/"${bs}t"}"
  printf '%s' "$s"
}

# t_hook_json <event> [key=value...]  -- dotted keys become nested objects
t_hook_json() {
  local event="$1"; shift
  local -a flat=() groups=()
  local kv k v g
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      *.*) g="${k%%.*}"
           case " ${groups[*]:-} " in *" $g "*) ;; *) groups+=("$g") ;; esac ;;
    esac
  done
  local out
  out="{\"hook_event_name\":\"$(t__json_escape "$event")\""
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in *.*) continue ;; esac
    out="$out,\"$(t__json_escape "$k")\":\"$(t__json_escape "$v")\""
  done
  for g in ${groups[@]+"${groups[@]}"}; do
    out="$out,\"$(t__json_escape "$g")\":{"
    local first=1
    for kv in "$@"; do
      k="${kv%%=*}"; v="${kv#*=}"
      case "$k" in "$g".*) ;; *) continue ;; esac
      [ $first = 1 ] || out="$out,"
      first=0
      out="$out\"$(t__json_escape "${k#*.}")\":\"$(t__json_escape "$v")\""
    done
    out="$out}"
  done
  printf '%s}\n' "$out"
}

# Prints PASS/FAIL table for $WM_RESULTS; returns 1 on any FAIL.
t_summary() {
  local pass=0 fail=0 line
  while IFS= read -r line; do
    case "$line" in
      PASS\|*) pass=$((pass+1)); printf 'PASS  %s\n' "${line#PASS|}" ;;
      FAIL\|*) fail=$((fail+1)); printf 'FAIL  %s\n' "${line#FAIL|}" ;;
    esac
  done < "$WM_RESULTS"
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" = 0 ]
}

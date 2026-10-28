#!/usr/bin/env bash
# Tests for bin/waymark index

# t_idx_layer <dir>: minimal layer
t_idx_layer() {
  mkdir -p "$1/docs/archive" "$1/docs/cross-repo"
  printf 'version=1\nowner_email=me@example.org\n' > "$1/layer.conf"
}

# t_idx_doc <layer> <relpath> <crlf:0|1> <frontmatter line>...
t_idx_doc() {
  local layer="$1" rel="$2" crlf="$3" nl=$'\n' body="---" l
  shift 3
  for l in "$@"; do body="$body$nl$l"; done
  body="$body$nl---${nl}text${nl}"
  mkdir -p "$(dirname "$layer/docs/$rel")"
  if [ "$crlf" = 1 ]; then body="${body//$'\n'/$'\r\n'}"; fi
  printf '%s' "$body" > "$layer/docs/$rel"
}

t_idx_run() { bash "$WM_PLUGIN/bin/waymark" index --root "$1" 2>&1; }

test_index_lists_complete() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out idx
  t_idx_layer "$L"
  t_idx_doc "$L" a.md 0 'title: Alpha' 'repo: zed' 'kind: spec' 'created: 2026-01-01' 'status: done' 'summary: first'
  t_idx_doc "$L" b.md 0 'title: Bravo' 'repo: app' 'kind: plan' 'created: 2026-02-01' 'status: done' 'summary: second'
  t_idx_doc "$L" c.md 0 'title: Charlie' 'repo: app' 'kind: plan' 'created: 2026-03-01' 'status: current' 'summary: third'
  t_idx_doc "$L" d.md 0 'title: Delta' 'repo: app' 'kind: plan' 'created: 2026-04-01' 'status: done' 'summary: fourth'
  t_idx_doc "$L" archive/old.md 0 'title: Old' 'repo: app' 'kind: plan' 'created: 2026-04-01' 'status: done'
  out="$(t_idx_run "$L")"
  t_contains "$out" "(4 indexed, 0 incomplete, 0 expired)." "counts"
  idx="$(cat "$L/docs/INDEX.md")"
  t_contains "$idx" "| Title | Kind | Date | Summary | Link |" "columns"
  t_contains "$idx" "| Delta | plan | 2026-04-01 | fourth | [d.md](d.md) |" "row"
  t_not_contains "$idx" "Old" "archive excluded"
  local pa pb pc pd pz
  pa="${idx%%## app*}"; pa=${#pa}
  pz="${idx%%## zed*}"; pz=${#pz}
  pc="${idx%%### current*}"; pc=${#pc}
  pd="${idx%%### done*}"; pd=${#pd}
  [ "$pa" -lt "$pz" ] && t_eq 1 1 "repo order" || t_eq 1 0 "repo order"
  [ "$pc" -lt "$pd" ] && t_eq 1 1 "status order" || t_eq 1 0 "status order"
  pb="${idx%%| Delta*}"; pb=${#pb}; pd="${idx%%| Bravo*}"; pd=${#pd}
  [ "$pb" -lt "$pd" ] && t_eq 1 1 "created desc" || t_eq 1 0 "created desc"
}

test_index_needs_frontmatter() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out idx
  t_idx_layer "$L"
  t_idx_doc "$L" nostatus.md 0 'title: T' 'repo: app' 'kind: plan' 'created: 2026-01-01'
  t_idx_doc "$L" ana.md 0 'title: A' 'repo: app' 'kind: analysis' 'created: 2026-01-01' 'status: current'
  printf 'no frontmatter here\n' > "$L/docs/bare.md"
  out="$(t_idx_run "$L")"
  t_contains "$out" "(0 indexed, 3 incomplete, 0 expired)." "counts"
  idx="$(cat "$L/docs/INDEX.md")"
  t_contains "$idx" "## Needs frontmatter" "section"
  t_contains "$idx" "| nostatus.md | TODO: status |" "missing status"
  t_contains "$idx" "| ana.md | TODO: valid_until |" "missing valid_until"
  t_contains "$idx" "| bare.md | TODO: title, repo, kind, created, status |" "no frontmatter"
}

test_index_expired_flag() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out idx
  t_idx_layer "$L"
  t_idx_doc "$L" old.md 0 'title: Stale' 'repo: app' 'kind: research' 'created: 2020-01-01' 'status: current' 'valid_until: 2020-06-01'
  t_idx_doc "$L" new.md 0 'title: Fresh' 'repo: app' 'kind: research' 'created: 2020-01-01' 'status: current' 'valid_until: 2999-01-01'
  out="$(t_idx_run "$L")"
  t_contains "$out" "(2 indexed, 0 incomplete, 1 expired)." "counts"
  idx="$(cat "$L/docs/INDEX.md")"
  t_contains "$idx" "| Stale (expired) |" "expired marked"
  t_contains "$idx" "| Fresh |" "fresh not marked"
}

test_index_idempotent() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" a b
  t_idx_layer "$L"
  t_idx_doc "$L" a.md 0 'title: A' 'repo: app' 'kind: plan' 'created: 2026-01-01' 'status: done'
  t_idx_doc "$L" b.md 0 'title: B' 'repo: app' 'kind: plan' 'created: 2026-01-01' 'status: done'
  t_idx_doc "$L" c.md 0 'title: C' 'repo: app' 'kind: plan'
  t_idx_run "$L" >/dev/null; a="$(cksum < "$L/docs/INDEX.md")"
  t_idx_run "$L" >/dev/null; b="$(cksum < "$L/docs/INDEX.md")"
  t_eq "$a" "$b" "identical across runs"
}

test_index_crlf_frontmatter() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out idx
  t_idx_layer "$L"
  t_idx_doc "$L" w.md 1 'title: Windows' 'repo: app' 'kind: plan' 'created: 2026-01-01' 'status: done' 'summary: crlf ok'
  out="$(t_idx_run "$L")"
  t_contains "$out" "(1 indexed, 0 incomplete, 0 expired)." "counts"
  idx="$(cat "$L/docs/INDEX.md")"
  t_contains "$idx" "| Windows | plan | 2026-01-01 | crlf ok | [w.md](w.md) |" "row without CR"
  case "$(cat "$L/docs/INDEX.md")" in *$'\r'*) t_eq 0 1 "no CR in output" ;; *) t_eq 0 0 "no CR in output" ;; esac
}

test_index_empty() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out
  t_idx_layer "$L"
  out="$(t_idx_run "$L")"
  t_contains "$out" "0 indexed, 0 incomplete, 0 expired" "empty counts"
  t_eq "$(cat "$WM_PLUGIN/templates/layer/docs/INDEX.md")" "$(cat "$L/docs/INDEX.md")" "matches template"
}

test_index_summary_pipe_escaped() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" idx
  t_idx_layer "$L"
  t_idx_doc "$L" p.md 0 'title: Pipe' 'repo: app' 'kind: plan' 'created: 2026-01-01' 'status: done' 'summary: a | b'
  t_idx_run "$L" >/dev/null
  idx="$(cat "$L/docs/INDEX.md")"
  t_contains "$idx" '| Pipe | plan | 2026-01-01 | a \| b | [p.md](p.md) |' "pipe escaped"
}

test_index_nested_archive_excluded() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out idx
  t_idx_layer "$L"
  t_idx_doc "$L" "sub dir/archive/n.md" 0 'title: Nested' 'repo: app' 'kind: plan' 'created: 2026-01-01' 'status: done'
  t_idx_doc "$L" "sub dir/keep.md" 0 'title: Keep' 'repo: app' 'kind: plan' 'created: 2026-01-01' 'status: done'
  out="$(t_idx_run "$L")"
  t_contains "$out" "(1 indexed, 0 incomplete, 0 expired)." "counts"
  idx="$(cat "$L/docs/INDEX.md")"
  t_not_contains "$idx" "Nested" "nested archive excluded"
  t_contains "$idx" "[sub dir/keep.md](sub%20dir/keep.md)" "space encoded"
}

test_index_fence_trailing_space() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out
  t_idx_layer "$L"
  printf -- '---  \ntitle: Sp\nrepo: app\nkind: plan\ncreated: 2026-01-01\nstatus: done\n--- \nbody\n' > "$L/docs/s.md"
  out="$(t_idx_run "$L")"
  t_contains "$out" "(1 indexed, 0 incomplete, 0 expired)." "trailing space fence"
}

test_index_bom_frontmatter() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out
  t_idx_layer "$L"
  printf '\357\273\277---\ntitle: Bom\nrepo: app\nkind: plan\ncreated: 2026-01-01\nstatus: done\n---\nbody\n' > "$L/docs/b.md"
  out="$(t_idx_run "$L")"
  t_contains "$out" "(1 indexed, 0 incomplete, 0 expired)." "bom frontmatter"
}

test_index_link_paren_encoded() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" idx
  t_idx_layer "$L"
  t_idx_doc "$L" "a(b)%c.md" 0 'title: P' 'repo: app' 'kind: plan' 'created: 2026-01-01' 'status: done'
  t_idx_run "$L" >/dev/null
  idx="$(cat "$L/docs/INDEX.md")"
  t_contains "$idx" "(a%28b%29%25c.md)" "link target encoded"
}

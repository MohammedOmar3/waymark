#!/usr/bin/env bash
# Tests for bin/cmd/init.sh (waymark init)

t_init() { # t_init <root> [extra args...]
  local root="$1"; shift
  bash "$WM_PLUGIN/bin/waymark" init --owner-name "Test Owner" --owner-email "owner@example.org" \
    --root "$root" --plugin-root "$WM_PLUGIN" "$@"
}

test_init_creates_tree() {
  local r="$WM_SANDBOX_DIR/layer" p k
  t_init "$r" --repo-roots "/a,/b" --email-allowlist "x@example.org" >/dev/null 2>&1
  for p in .gitignore layer.conf tags.conf PROTOCOL.md DOCS-PROTOCOL.md INDEX.md gotchas.md \
    decisions.md conventions.md worklog.md platform.md pipelines.md playbooks/.gitkeep \
    repos/_template.md stats/recall.tsv inbox/.gitkeep active/.gitkeep docs/INDEX.md \
    docs/archive/.gitkeep docs/cross-repo/.gitkeep bin/waymark bin/lib.sh bin/cmd/scan.sh; do
    t_file_exists "$r/$p" "tree: $p"
  done
  . "$WM_PLUGIN/bin/lib.sh"
  t_eq "Test Owner" "$(wm_conf_get "$r/layer.conf" owner_name)" "conf owner_name"
  t_eq "owner@example.org" "$(wm_conf_get "$r/layer.conf" owner_email)" "conf owner_email"
  t_eq "x@example.org" "$(wm_conf_get "$r/layer.conf" email_allowlist)" "conf allowlist"
  t_eq "/a,/b" "$(wm_conf_get "$r/layer.conf" repo_roots)" "conf repo_roots"
  t_eq "no" "$(wm_conf_get "$r/layer.conf" replace_auto_memory)" "conf replace_auto_memory"
  for k in plugin_version created prior_auto_memory; do
    wm_conf_get "$r/layer.conf" "$k" >/dev/null
    t_eq 0 "$?" "conf has $k"
  done
  t_eq "$r" "$(wm_conf_get "$CLAUDE_CONFIG_DIR/waymark.conf" root)" "waymark.conf root"
  t_contains "$(cat "$r/gitignore" "$r/.gitignore" 2>/dev/null)" "inbox/" "gitignore inbox"
  t_eq "expo*=expo" "$(sed -n 1p "$r/tags.conf")" "tags.conf first"
  t_eq "$(printf 'date\tsession\tid\trepo')" "$(cat "$r/stats/recall.tsv")" "recall.tsv header"
}

test_init_no_tokens() {
  local r="$WM_SANDBOX_DIR/layer" out
  t_init "$r" >/dev/null 2>&1
  out="$(grep -r '{{' "$r" --exclude-dir=.git 2>/dev/null)"
  t_eq "" "$out" "no unsubstituted tokens"
}

test_init_git_state() {
  local r="$WM_SANDBOX_DIR/layer"
  t_init "$r" >/dev/null 2>&1
  t_eq main "$(git -C "$r" symbolic-ref --short HEAD)" "branch main"
  t_eq 1 "$(git -C "$r" rev-list --count HEAD)" "one commit"
  t_eq "chore: initialise waymark layer" "$(git -C "$r" log -1 --format=%s)" "commit subject"
  t_eq "" "$(git -C "$r" status --porcelain)" "clean tree"
  [ -x "$r/.git/hooks/pre-commit" ]; t_eq 0 "$?" "pre-commit executable"
  t_eq "Test Owner" "$(git -C "$r" config --local user.name)" "local user.name"
  t_eq "owner@example.org" "$(git -C "$r" config --local user.email)" "local user.email"
}

test_init_refuses_nonempty() {
  local r="$WM_SANDBOX_DIR/layer"
  mkdir -p "$r"; printf 'keep\n' > "$r/mine.txt"
  t_exit 2 "nonempty exit 2" -- bash "$WM_PLUGIN/bin/waymark" init --owner-name O --owner-email o@example.org --root "$r" --plugin-root "$WM_PLUGIN"
  t_eq "keep" "$(cat "$r/mine.txt")" "file untouched"
  [ ! -e "$r/layer.conf" ]; t_eq 0 "$?" "no layer.conf written"
  [ ! -e "$CLAUDE_CONFIG_DIR/waymark.conf" ]; t_eq 0 "$?" "no waymark.conf"
}

test_init_refuses_nested() {
  t_fake_repo "$WM_SANDBOX_DIR/proj"
  t_exit 2 "nested exit 2" -- bash "$WM_PLUGIN/bin/waymark" init --owner-name O --owner-email o@example.org --root "$WM_SANDBOX_DIR/proj/sub/layer" --plugin-root "$WM_PLUGIN"
  [ ! -e "$WM_SANDBOX_DIR/proj/sub" ]; t_eq 0 "$?" "nothing written"
}

test_init_refuses_bad_email() {
  t_exit 2 "bad email exit 2" -- bash "$WM_PLUGIN/bin/waymark" init --owner-name O --owner-email nope --root "$WM_SANDBOX_DIR/layer" --plugin-root "$WM_PLUGIN"
  [ ! -e "$WM_SANDBOX_DIR/layer" ]; t_eq 0 "$?" "nothing written"
}

test_init_gpgsign() {
  local r="$WM_SANDBOX_DIR/layer" out
  git config --global commit.gpgsign true
  out="$(t_init "$r" 2>&1)"
  t_eq 0 "$?" "init ok with global gpgsign"
  t_eq false "$(git -C "$r" config --local commit.gpgsign)" "local gpgsign false"
  t_contains "$out" "signing" "notice printed"
  t_eq 1 "$(git -C "$r" rev-list --count HEAD)" "committed"
}

test_init_gpgsign_sign_layer_yes() {
  local r="$WM_SANDBOX_DIR/layer"
  git config --global commit.gpgsign true
  git config --global gpg.program /bin/true
  t_init "$r" --sign-layer yes >/dev/null 2>&1
  t_eq "" "$(git -C "$r" config --local commit.gpgsign)" "local gpgsign untouched"
}

test_init_path_with_space() {
  local r="$WM_SANDBOX_DIR/my layer"
  t_init "$r" >/dev/null 2>&1
  t_eq 0 "$?" "init with space"
  t_eq 1 "$(git -C "$r" rev-list --count HEAD)" "committed"
  t_eq "$r" "$(. "$WM_PLUGIN/bin/lib.sh"; wm_conf_get "$CLAUDE_CONFIG_DIR/waymark.conf" root)" "root recorded"
}

test_init_bom_lf() {
  local r="$WM_SANDBOX_DIR/layer" f bad_bom="" bad_cr=""
  t_init "$r" >/dev/null 2>&1
  while IFS= read -r f; do
    [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" = efbbbf ] && bad_bom="$bad_bom $f"
    grep -q $'\r' "$f" && bad_cr="$bad_cr $f"
  done < <(find "$r" -path "$r/.git" -prune -o -type f -print)
  t_eq "" "$bad_bom" "no BOM"
  t_eq "" "$bad_cr" "no CR"
}

test_core_protocol_scans_clean() {
  local r="$WM_SANDBOX_DIR/layer"
  t_init "$r" >/dev/null 2>&1
  cp "$WM_PLUGIN/templates/PROTOCOL.core.md" "$r/docs/core.md"
  bash "$r/bin/waymark" scan --root "$r" >/dev/null 2>&1
  t_eq 0 "$?" "PROTOCOL.core.md scans clean"
  t_eq "true" "$([ "$(wc -l < "$WM_PLUGIN/templates/PROTOCOL.core.md")" -le 25 ] && echo true)" "core <= 25 lines"
}

#!/usr/bin/env bash
# Tests for bin/waymark scan and templates/pre-commit

# t_scan_layer <dir> [owner] [allowlist]: layer with the real scanner in bin/
t_scan_layer() {
  local layer="$1"
  mkdir -p "$layer/docs" "$layer/inbox" "$layer/active"
  printf 'version=1\nowner_email=%s\nemail_allowlist=%s\n' "${2:-me@example.org}" "${3:-}" > "$layer/layer.conf"
  cp -R "$WM_PLUGIN/bin" "$layer/bin"
}

# t_plant <layer> <line>: write one line into docs/canary.md
t_plant() { printf '%s\n' "$2" > "$1/docs/canary.md"; }

# t_expect_hit <name> <line>
t_expect_hit() {
  local layer="$WM_SANDBOX_DIR/layer-$1" out rc
  t_scan_layer "$layer"
  t_plant "$layer" "$2"
  out="$(bash "$layer/bin/waymark" scan --root "$layer" 2>&1)"; rc=$?
  t_eq 1 "$rc" "$1: exit 1"
  t_contains "$out" "canary.md" "$1: names file"
}

test_password_assignment() { t_expect_hit password 'password = hunter2x'; }
test_api_key_assignment() { t_expect_hit apikey 'api_key: abcd1234efgh'; }
test_sk_key() { t_expect_hit sk "key is sk-abcdefghijklmnopqrstuvwxyz012345 ok"; }
test_sk_live() { t_expect_hit sklive 'sk_live_abcdefghij0123456789'; }
test_github_tokens() {
  t_expect_hit ghp 'ghp_abcdefghijklmnopqrstuvwxyz0123456789'
  t_expect_hit ghpat 'github_pat_abcdefghijklmnopqrstuvwxyz0123456789ABCD'
}
test_aws_key() { t_expect_hit aws 'id AKIAABCDEFGHIJKLMNOP end'; }
test_private_key_block() { t_expect_hit pkey '-----BEGIN RSA PRIVATE KEY-----'; }
test_jwt() { t_expect_hit jwt 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF123_-xyz'; }
test_slack_token() { t_expect_hit slack 'xoxb-1234567890-abcdefghij'; }
test_url_credentials() { t_expect_hit url 'postgres://user:pass@host/db'; }

test_email_rules() {
  local layer="$WM_SANDBOX_DIR/layer-email" rc
  t_scan_layer "$layer" me@example.org bot@example.org
  t_plant "$layer" 'contact other@example.org'
  bash "$layer/bin/waymark" scan --root "$layer" >/dev/null 2>&1; t_eq 1 "$?" "other owner-domain email fails"
  t_plant "$layer" 'me@example.org'
  bash "$layer/bin/waymark" scan --root "$layer" >/dev/null 2>&1; t_eq 0 "$?" "owner email passes"
  t_plant "$layer" 'Me@Example.org and bot@example.org'
  bash "$layer/bin/waymark" scan --root "$layer" >/dev/null 2>&1; t_eq 0 "$?" "case-insens owner + allowlist pass"
  t_plant "$layer" 'noreply@anthropic.com'
  bash "$layer/bin/waymark" scan --root "$layer" >/dev/null 2>&1; t_eq 0 "$?" "other domain passes"
}

test_not_flagged() {
  local layer="$WM_SANDBOX_DIR/layer-ok"
  t_scan_layer "$layer"
  printf '%s\n' \
    'id 123e4567-e89b-12d3-a456-426614174000' \
    'number 1234567890123456' \
    'password:' \
    'Password is a word in prose; the task-management-feature-for-everyone is fine' \
    'token_budget: 1500' > "$layer/docs/canary.md"
  local out
  out="$(bash "$layer/bin/waymark" scan --root "$layer" 2>&1)"; t_eq 0 "$?" "benign lines pass"
  t_contains "$out" "No secrets/identifiers found." "clean message"
}

test_scan_self_clean() {
  local layer="$WM_SANDBOX_DIR/layer-self" out
  t_scan_layer "$layer"
  cp "$WM_PLUGIN/docs/hook-contract.md" "$layer/docs/"
  cp "$WM_PLUGIN/README.md" "$layer/docs/readme.md"
  local doc="${WM_DESIGN_DOC:-$WM_REAL_HOME/Downloads/2026-10-28-design-waymark.md}"
  [ -f "$doc" ] && cp "$doc" "$layer/docs/design.md"
  out="$(bash "$layer/bin/waymark" scan --root "$layer" 2>&1)"
  local rc=$?
  t_eq 0 "$rc" "scanner + docs scan clean"
  [ "$rc" = 0 ] || printf '%s\n' "$out" >&2
}

test_skips_inbox_and_logs() {
  local layer="$WM_SANDBOX_DIR/layer-skip"
  t_scan_layer "$layer"
  printf 'password = hunter2x\n' > "$layer/inbox/x.md"
  printf 'password = hunter2x\n' > "$layer/active/x.log"
  bash "$layer/bin/waymark" scan --root "$layer" >/dev/null 2>&1
  t_eq 0 "$?" "inbox and logs skipped"
}

test_dispatcher_usage() {
  t_exit 64 "unknown command -> 64" -- bash "$WM_PLUGIN/bin/waymark" nonesuch
  t_exit 64 "no command -> 64" -- bash "$WM_PLUGIN/bin/waymark"
}

test_scan_uses_layer_lookup() {
  local layer="$WM_SANDBOX_DIR/layer-look"
  t_scan_layer "$layer"
  t_plant "$layer" 'password = hunter2x'
  WAYMARK_ROOT="$layer" bash "$layer/bin/waymark" scan >/dev/null 2>&1
  t_eq 1 "$?" "no --root uses wm_layer_root"
}

test_precommit_blocks() {
  local layer="$WM_SANDBOX_DIR/layer-hook"
  t_scan_layer "$layer"
  git -C "$layer" init -q -b main 2>/dev/null || git -C "$layer" init -q
  cp "$WM_PLUGIN/templates/pre-commit" "$layer/.git/hooks/pre-commit"
  chmod +x "$layer/.git/hooks/pre-commit"
  t_plant "$layer" 'password = hunter2x'
  git -C "$layer" add -A
  t_exit 1 "secret commit blocked" -- git -C "$layer" commit -q -m bad
  t_eq "0" "$(git -C "$layer" rev-list --all --count 2>/dev/null)" "nothing committed"
  t_plant "$layer" 'all clear here'
  git -C "$layer" add -A
  git -C "$layer" commit -q -m good >/dev/null 2>&1
  t_eq 0 "$?" "clean commit succeeds"
}

test_assignment_false_positives() {
  local layer="$WM_SANDBOX_DIR/layer-fp" line rc n=0
  t_scan_layer "$layer"
  while IFS= read -r line; do
    n=$((n+1))
    t_plant "$layer" "$line"
    bash "$layer/bin/waymark" scan --root "$layer" >/dev/null 2>&1; rc=$?
    t_eq 0 "$rc" "not flagged: $line"
  done <<'LINES'
password = os.environ["PW"]
const token = getToken();
token: required
Secret: management
secrets = load_secrets()
the token: refresh-handling
secretKey: value
tokens: many
LINES
}

test_assignment_positives_quoted() {
  t_expect_hit quoted1 'password = "abcdef"'
  t_expect_hit quoted2 "client_secret: 'zzzzzz'"
  t_expect_hit pwd 'PWD=hunter2xyz'
}

test_findings_redacted() {
  local layer="$WM_SANDBOX_DIR/layer-red" out
  local secrets=('hunter2x9' 'abcdefghijklmnopqrstuvwxyz0123456789' 'AKIAABCDEFGHIJKLMNOP' 'user:pass9word@')
  t_scan_layer "$layer"
  printf '%s\n' 'password = hunter2x9' 'k sk-abcdefghijklmnopqrstuvwxyz0123456789 x' \
    'id AKIAABCDEFGHIJKLMNOP end' 'postgres://user:pass9word@host/db' > "$layer/docs/canary.md"
  out="$(bash "$layer/bin/waymark" scan --root "$layer" 2>&1)"
  t_contains "$out" "[REDACTED]" "output redacted"
  t_contains "$out" "canary.md:1" "location kept"
  local s
  for s in "${secrets[@]}"; do t_not_contains "$out" "$s" "stdout hides $s"; done
  # log written by wm_commit
  git -C "$layer" init -q -b main 2>/dev/null || git -C "$layer" init -q
  printf 'active/\n' > "$layer/.gitignore"
  ( . "$WM_PLUGIN/bin/lib.sh"; export WAYMARK_ROOT="$layer"; wm_commit "x" ) >/dev/null 2>&1
  local log; log="$(cat "$layer/active/.scan-failed.log" 2>/dev/null)"
  t_contains "$log" "[REDACTED]" "log redacted"
  for s in "${secrets[@]}"; do t_not_contains "$log" "$s" "log hides $s"; done
}

test_scanner_portable_regex() {
  local f="$WM_PLUGIN/bin/cmd/scan.sh" bs
  bs="$(printf '\134')"
  t_eq "0" "$(grep -c "${bs}[dwb]" "$f")" "no backslash-d/w/b in scanner"
  t_eq "0" "$(grep -c ',,}' "$f")" "no bash4 case expansion"
}

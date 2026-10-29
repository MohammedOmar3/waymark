#!/usr/bin/env bash
# Tests for bin/waymark view (build only; behaviour is checked by tests/browser/check-viewer.mjs)

# t_view_b64d: decode base64 on stdin (GNU -d, BSD -D)
t_view_b64d() { base64 -d 2>/dev/null || base64 -D; }

# t_view_layer <dir>: copy of the fixture plus files that must be excluded
t_view_layer() {
  cp -R "$WM_REPO_ROOT/tests/fixtures/viewer-layer" "$1" || return 1
  mkdir -p "$1/active" "$1/inbox" "$1/.view" "$1/.git" "$1/docs/with space" "$1/docs/vendored/.git" "$1/docs/sub/.view"
  printf '# nested git
' > "$1/docs/vendored/.git/x.md"
  printf '# nested view
' > "$1/docs/sub/.view/y.md"
  printf '# active\n' > "$1/active/s1.md"
  printf '# inbox\n' > "$1/inbox/i1.md"
  printf '# old view\n' > "$1/.view/old.md"
  printf '# git\n' > "$1/.git/g.md"
  printf '# spaced\n\nG-0002\n' > "$1/docs/with space/n o.md"
  printf -- '---\r\ntitle: Crlf\r\n---\r\n\r\n# Crlf file\r\n\r\ntext\r\n' > "$1/docs/crlf.md"
}

t_view_build() { # <layer> <out> [extra...]
  local l="$1" o="$2"
  shift 2
  WAYMARK_ROOT="$l" bash "$WM_PLUGIN/bin/waymark" view --no-open --out "$o" "$@" 2>&1
}

# t_view_blocks <html>: one line per embedded file block
t_view_blocks() { grep '^<script type="application/x-waymark" ' "$1"; }

test_view_embeds_every_file() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out="$WM_SANDBOX_DIR/v.html" want got
  t_view_layer "$L"
  t_view_build "$L" "$out" >/dev/null
  want="$(cd "$L" && find . \( -name .git -o -name .view -o -path ./inbox -o -path ./active \) -prune -o -type f -name '*.md' -print | wc -l | tr -d ' ')"
  got="$(t_view_blocks "$out" | wc -l | tr -d ' ')"
  t_eq "$want" "$got" "every md file embedded"
  t_eq "7" "$got" "fixture has seven files"
  t_not_contains "$(cat "$out")" 'data-path="active/' "no active file"
  t_not_contains "$(cat "$out")" 'data-path="inbox/' "no inbox file"
  t_not_contains "$(cat "$out")" 'data-path=".view/' "no .view file"
  t_not_contains "$(cat "$out")" 'data-path=".git/' "no .git file"
  t_contains "$(cat "$out")" 'data-path="docs/waymark/x.md"' "nested doc embedded"
  t_not_contains "$(cat "$out")" 'vendored/.git' "nested .git excluded"
  t_not_contains "$(cat "$out")" 'sub/.view' "nested .view excluded"
}

test_view_roundtrip_exact() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out="$WM_SANDBOX_DIR/v.html" line rel b64 n=0 bad=0
  t_view_layer "$L"
  t_view_build "$L" "$out" >/dev/null
  while IFS= read -r line; do
    rel="${line#*data-path=\"}"; rel="${rel%%\"*}"
    b64="${line#*>}"; b64="${b64%%</script>*}"
    printf '%s' "$b64" | t_view_b64d > "$WM_SANDBOX_DIR/dec"
    if cmp -s "$WM_SANDBOX_DIR/dec" "$L/$rel"; then n=$((n + 1)); else bad=$((bad + 1)); printf 'mismatch: %s\n' "$rel" >&2; fi
  done <<EOF
$(t_view_blocks "$out")
EOF
  t_eq "0" "$bad" "no mismatched blocks"
  t_eq "7" "$n" "seven blocks byte-identical"
}

test_view_no_external_urls() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out="$WM_SANDBOX_DIR/v.html" hits
  t_view_layer "$L"
  t_view_build "$L" "$out" >/dev/null
  hits="$(grep -E '<(script|link)[^>]*(src|href)="https?://' "$out" | head -n 3)"
  t_eq "" "$hits" "no external src/href on script/link"
}

test_view_idempotent() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" a="$WM_SANDBOX_DIR/a.html" b="$WM_SANDBOX_DIR/b.html" sa sb
  t_view_layer "$L"
  t_view_build "$L" "$a" >/dev/null
  t_view_build "$L" "$b" >/dev/null
  sa="$(grep -v 'wm-built' "$a" | cksum)"
  sb="$(grep -v 'wm-built' "$b" | cksum)"
  t_eq "$sa" "$sb" "same content ignoring build stamp"
  t_contains "$(cat "$a")" 'id="wm-built"' "build stamp present"
}

test_view_atomic() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" d="$WM_SANDBOX_DIR/o" left
  t_view_layer "$L"
  mkdir -p "$d"
  printf 'previous\n' > "$d/v.html"
  t_view_build "$L" "$d/v.html" >/dev/null
  t_eq "1" "$(ls "$d" | wc -l | tr -d ' ')" "no temp file left"
  [ -s "$d/v.html" ] && left=nonempty || left=empty
  t_eq "nonempty" "$left" "target non-empty"
  t_not_contains "$(head -c 200 "$d/v.html")" "previous" "target replaced"
}

test_view_path_with_space() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/my layer" out="$WM_SANDBOX_DIR/out dir/v w.html" rc
  t_view_layer "$L"
  mkdir -p "$WM_SANDBOX_DIR/out dir"
  t_view_build "$L" "$out" >/dev/null; rc=$?
  t_eq "0" "$rc" "exit 0 with spaces in paths"
  t_contains "$(cat "$out")" 'data-path="docs/with space/n o.md"' "spaced file embedded"
}

test_view_vendor_safe() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out="$WM_SANDBOX_DIR/v.html" open close
  t_view_layer "$L"
  t_view_build "$L" "$out" >/dev/null
  open="$(grep -o '<script' "$out" | wc -l | tr -d ' ')"
  close="$(grep -o '</script>' "$out" | wc -l | tr -d ' ')"
  t_eq "$open" "$close" "script openings equal closings"
  t_eq "0" "$(grep -c '^<!--WAYMARK:' "$out")" "no placeholders remain"
  t_eq "0" "$(grep -c 'WAYMARK:DATA\|WAYMARK:VENDOR\|WAYMARK:BUILT' "$out")" "no placeholder text remains"
  # every embedded payload is base64 only
  t_eq "0" "$(t_view_blocks "$out" | sed 's/^[^>]*>//; s/<\/script>$//' | grep -c '[^A-Za-z0-9+/=]')" "payloads are plain base64"
  t_eq "0" "$(grep '^<script type="text/plain" id="wm-' "$out" | sed 's/^[^>]*>//; s/<\/script>$//' | grep -c '[^A-Za-z0-9+/=]')" "vendor payloads are plain base64"
  t_contains "$(cat "$out")" 'id="wm-mermaid"' "mermaid source embedded"
}

test_view_unknown_flag() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" rc
  t_view_layer "$L"
  WAYMARK_ROOT="$L" bash "$WM_PLUGIN/bin/waymark" view --bogus >/dev/null 2>&1; rc=$?
  t_eq "64" "$rc" "unknown flag exits 64"
}

test_view_default_output() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out rc
  t_view_layer "$L"
  out="$(WAYMARK_ROOT="$L" bash "$WM_PLUGIN/bin/waymark" view --no-open 2>&1)"; rc=$?
  t_eq "0" "$rc" "no-open exits 0"
  t_contains "$out" ".view/index.html" "prints the path"
  t_file_exists "$L/.view/index.html" "default output written"
}

test_view_out_validation() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" rc msg
  t_view_layer "$L"
  msg="$(WAYMARK_ROOT="$L" bash "$WM_PLUGIN/bin/waymark" view --no-open --out "" 2>&1)"; rc=$?
  t_eq "64" "$rc" "empty --out exits 64"
  t_contains "$msg" "non-empty" "empty --out message"
  mkdir -p "$WM_SANDBOX_DIR/adir"
  msg="$(WAYMARK_ROOT="$L" bash "$WM_PLUGIN/bin/waymark" view --no-open --out "$WM_SANDBOX_DIR/adir" 2>&1)"; rc=$?
  t_eq "64" "$rc" "directory --out exits 64"
  t_contains "$msg" "is a directory" "directory --out message"
  t_eq "0" "$(ls "$WM_SANDBOX_DIR/adir" | wc -l | tr -d ' ')" "nothing written into the directory"
}

test_view_gitignore_guard() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l"
  t_view_layer "$L"
  printf 'active/
.locks/' > "$L/.gitignore"
  t_view_build "$L" "$WM_SANDBOX_DIR/v.html" >/dev/null
  t_eq "active/
.locks/
.view/" "$(cat "$L/.gitignore")" ".view/ appended after a missing final newline"
  t_view_build "$L" "$WM_SANDBOX_DIR/v.html" >/dev/null
  t_eq "1" "$(grep -c '^.view/$' "$L/.gitignore")" "not appended twice"
  rm -f "$L/.gitignore"
  t_view_build "$L" "$WM_SANDBOX_DIR/v.html" >/dev/null
  t_eq "no" "$([ -e "$L/.gitignore" ] && echo yes || echo no)" "no .gitignore is not created"
}

test_view_inlines_css() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out="$WM_SANDBOX_DIR/v.html" first
  t_view_layer "$L"
  t_view_build "$L" "$out" >/dev/null
  t_eq "0" "$(grep -c 'WAYMARK:CSS' "$out")" "CSS marker replaced"
  t_eq "1" "$(grep -c '^<style>$' "$out")" "one style element"
  first="$(awk '/^<style>$/ { on = 1; next } on && NF { print; exit }' "$out")"
  t_contains "$first" '/* Hallmark ' "stamp is the first line inside <style>"
  t_eq "0" "$(grep -ci '<link[^>]*rel=["'"'"']\{0,1\}stylesheet' "$out")" "no stylesheet link"
  t_eq "1" "$(awk '/^<style>$/ { on = 1; next } /^<\/style>$/ { on = 0 } on && /--color-paper:/ { n = 1 } END { print n + 0 }' "$out")" "tokens inlined inside <style>"
}

test_view_failure_keeps_previous_snapshot() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" P="$WM_SANDBOX_DIR/plugin" d="$WM_SANDBOX_DIR/o" rc
  t_view_layer "$L"
  mkdir -p "$P" "$d"
  cp -R "$WM_PLUGIN/bin" "$WM_PLUGIN/viewer" "$P/"
  rm -f "$P/viewer/vendor/mermaid.min.js"
  printf 'previous\n' > "$d/v.html"
  WAYMARK_ROOT="$L" bash "$P/bin/waymark" view --no-open --out "$d/v.html" >/dev/null 2>&1; rc=$?
  t_eq "2" "$rc" "missing vendor file exits 2"
  t_eq "previous" "$(cat "$d/v.html")" "previous snapshot untouched"
  t_eq "1" "$(ls "$d" | wc -l | tr -d ' ')" "no temp file left on failure"
}

test_view_from_layer_bin() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" d="$WM_SANDBOX_DIR/o" out rc
  t_view_layer "$L"
  mkdir -p "$d"
  cp -R "$WM_PLUGIN/bin" "$L/"
  out="$(WAYMARK_ROOT="$L" bash "$L/bin/waymark" view --no-open --out "$d/n.html" 2>&1)"; rc=$?
  t_eq "2" "$rc" "layer bin without plugin_root exits 2"
  t_contains "$out" "plugin_root" "error names plugin_root"
  printf 'plugin_root=%s\n' "$WM_PLUGIN" >> "$L/layer.conf"
  WAYMARK_ROOT="$L" bash "$L/bin/waymark" view --no-open --out "$d/c.html" >/dev/null 2>&1; rc=$?
  t_eq "0" "$rc" "layer bin uses plugin_root from layer.conf"
  t_file_exists "$d/c.html" "snapshot built via plugin_root"
  sed -i.bak '/^plugin_root=/d' "$L/layer.conf"
  CLAUDE_PLUGIN_ROOT="$WM_PLUGIN" WAYMARK_ROOT="$L" bash "$L/bin/waymark" view --no-open --out "$d/e.html" >/dev/null 2>&1; rc=$?
  t_eq "0" "$rc" "layer bin uses CLAUDE_PLUGIN_ROOT"
  t_file_exists "$d/e.html" "snapshot built via CLAUDE_PLUGIN_ROOT"
}

test_view_no_heredoc() {
  t_eq "0" "$(grep -c '<<' "$WM_PLUGIN/bin/cmd/view.sh")" "view.sh has no heredoc"
}

test_view_csp_blocks_network() {
  t_sandbox
  local L="$WM_SANDBOX_DIR/l" out="$WM_SANDBOX_DIR/v.html"
  t_view_layer "$L"
  t_view_build "$L" "$out" >/dev/null
  t_contains "$(cat "$out")" "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' blob:; style-src 'unsafe-inline'; img-src data: blob:; font-src data:\">" "CSP meta present"
}

test_view_noscript_hides_nav() {
  t_contains "$(cat "$WM_PLUGIN/viewer/viewer.css")" "html:not(.js) #wm-nav," "nav hidden without scripting"
  t_contains "$(cat "$WM_PLUGIN/viewer/viewer.css")" "html:not(.js) #wm-layout { grid-template-columns: minmax(0, 1fr); }" "single column without scripting"
  t_eq "1" "$(grep -c '^#wm-search {' "$WM_PLUGIN/viewer/viewer.css")" "one #wm-search rule"
}

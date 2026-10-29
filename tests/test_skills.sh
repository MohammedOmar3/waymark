#!/usr/bin/env bash
# Skills: frontmatter, real CLI references, plugin validation.

t_sk_names="setup remember end-session review uninstall"

test_skills_frontmatter() {
  local n f first name desc
  for n in $t_sk_names; do
    f="$WM_PLUGIN/skills/$n/SKILL.md"
    if [ ! -f "$f" ]; then t__fail "skill $n: SKILL.md missing"; continue; fi
    first="$(head -n 1 "$f" | tr -d '\r')"
    t_eq '---' "$first" "skill $n opens with frontmatter"
    name="$(awk '/^---/{c++; next} c==1 && /^name:/{sub(/^name:[ \t]*/,""); sub(/\r$/,""); print; exit}' "$f")"
    desc="$(awk '/^---/{c++; next} c==1 && /^description:/{sub(/^description:[ \t]*/,""); sub(/\r$/,""); print; exit}' "$f")"
    t_eq "$n" "$name" "skill $n name matches directory"
    if [ -n "$desc" ]; then t__pass "skill $n has description"; else t__fail "skill $n has description"; fi
  done
}

test_skills_reference_real_commands() {
  local n f w seen=0
  # prose words that legitimately follow "waymark " in skill text
  local allow=" layer plugin memory skills uninstall setup "
  for n in $t_sk_names; do
    f="$WM_PLUGIN/skills/$n/SKILL.md"
    [ -f "$f" ] || { t__fail "skill $n: SKILL.md missing"; continue; }
    for w in $(grep -oE 'bin/waymark"? +[a-z][a-z-]*' "$f" | awk '{print $2}'); do
      seen=$((seen + 1))
      if [ -f "$WM_PLUGIN/bin/cmd/$w.sh" ]; then t__pass "skill $n: bin/waymark $w exists"; else t__fail "skill $n: bin/waymark $w has no bin/cmd/$w.sh"; fi
    done
    for w in $(grep -oE '`waymark +[a-z][a-z-]*' "$f" | awk '{print $2}'); do
      case "$allow" in *" $w "*) continue ;; esac
      seen=$((seen + 1))
      if [ -f "$WM_PLUGIN/bin/cmd/$w.sh" ]; then t__pass "skill $n: waymark $w exists"; else t__fail "skill $n: waymark $w has no bin/cmd/$w.sh"; fi
    done
  done
  if [ "$seen" -gt 0 ]; then t__pass "skills reference commands"; else t__fail "skills reference no commands"; fi
}

test_skills_pinned_specifics() {
  local f
  f="$WM_PLUGIN/skills/setup/SKILL.md"
  t_contains "$(cat "$f" 2>/dev/null)" "gmail.com outlook.com hotmail.com live.com icloud.com yahoo.com proton.me protonmail.com" "setup lists public providers"
  t_contains "$(cat "$f" 2>/dev/null)" "prior_auto_memory=" "setup records prior_auto_memory"
  t_contains "$(cat "$f" 2>/dev/null)" "autoMemoryEnabled" "setup names the settings key"
  t_contains "$(cat "$WM_PLUGIN/skills/uninstall/SKILL.md" 2>/dev/null)" "archive" "uninstall offers archive"
  t_contains "$(cat "$WM_PLUGIN/skills/review/SKILL.md" 2>/dev/null)" "hooks/session-start" "review measures session-start"
  t_contains "$(cat "$WM_PLUGIN/skills/review/SKILL.md" 2>/dev/null)" "projects/*/memory/" "review checks leftover auto-memory"
  if grep -qE 'git +push|remote add' "$WM_PLUGIN"/skills/*/SKILL.md 2>/dev/null \
     && ! grep -qiE 'never[^.]*(push|remote)' "$WM_PLUGIN"/skills/*/SKILL.md; then
    t__fail "skills must not push or add remotes"
  else t__pass "skills do not push or add remotes"; fi
}

test_plugin_validates() {
  local claude out rc
  claude="$(command -v claude 2>/dev/null)"
  [ -n "$claude" ] || [ ! -x "$HOME/.local/bin/claude" ] || claude="$HOME/.local/bin/claude"
  [ -n "$claude" ] || [ ! -x "${WM_REAL_HOME:-/nonexistent}/.local/bin/claude" ] || claude="$WM_REAL_HOME/.local/bin/claude"
  if [ -z "$claude" ]; then
    printf 'NOTICE: claude not found; skipping plugin validate\n'
    t__pass "plugin validate skipped (claude absent)"
    return 0
  fi
  out="$(cd "$WM_PLUGIN" && "$claude" plugin validate . 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then t__pass "claude plugin validate exits 0"; else t__fail "claude plugin validate exits 0" "$out"; fi
}

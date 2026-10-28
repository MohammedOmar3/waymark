#!/usr/bin/env bash
# Tests for bin/cmd/brief.sh, bin/cmd/stats.sh and bin/cmd/strays.sh

wm() { bash "$WM_PLUGIN/bin/waymark" "$@"; }

# t_br_setup: minimal layer in $L (no git needed), WAYMARK_ROOT pointing at it
t_br_setup() {
  L="$WM_SANDBOX_DIR/layer"
  mkdir -p "$L/playbooks" "$L/docs" "$L/stats"
  printf 'repo_roots=\n' > "$L/layer.conf"
  export WAYMARK_ROOT="$L"
}

t_br_rec() { # kind args... (explicit repo/tags so no git repo is needed)
  wm record "$@" >/dev/null
}

test_brief_by_tag() {
  local out
  t_br_setup
  t_br_rec gotcha --symptom "Build fails on eas" --cause "Stale cache" --fix "Clear it" --match "ERR_CACHE" --repo myapp --tags "expo,eas"
  t_br_rec gotcha --symptom "Sentry upload broken" --cause "Token" --fix "Rotate" --match "401" --repo myapp --tags "sentry"
  out="$(wm brief expo)"
  t_contains "$out" "Gotchas" "gotchas section"
  t_contains "$out" "G-0001  Build fails on eas — fixed" "hit line format"
  t_not_contains "$out" "G-0002" "other tag not listed"
  t_not_contains "$out" "Decisions" "empty sections omitted"
}

test_brief_and_terms() {
  local out
  t_br_setup
  t_br_rec gotcha --symptom "Build fails on eas" --cause "Stale cache" --fix "Clear it" --match "ERR_CACHE" --repo myapp --tags "expo,eas"
  t_br_rec gotcha --symptom "Other eas thing" --cause "Nope" --fix "Fix" --match "X" --repo other --tags "eas"
  t_br_rec decision --decision "Use EAS Update for OTA" --chose "EAS Update over CodePush" --because "supported" --constraint "none" --revisit "never" --repo myapp --tags "eas"
  t_br_rec convention --rule "Always pin eas-cli" --why "reproducible" --repo myapp --tags "eas"
  printf '%s\n' '---' 'tag: eas' 'triggers:' '  - eas (build|submit)' '---' '## Rules' '- Run eas build with a clean tree (G-0001)' '- Unrelated rule' '## Before running a trigger command' '- [ ] check eas whoami' > "$L/playbooks/eas.md"
  out="$(wm brief EAS cache)"
  t_contains "$out" "G-0001" "AND: both terms in block"
  t_not_contains "$out" "G-0002" "AND: second term missing"
  t_not_contains "$out" "Decisions" "AND excludes decision without cache"
  out="$(wm brief eas)"
  t_contains "$out" "Decisions
D-0001  " "decision hit"
  t_contains "$out" "— EAS Update over CodePush" "decision summary is Chose"
  t_contains "$out" "Conventions
C-0001  Always pin eas-cli" "convention hit"
  t_contains "$out" "Playbooks
playbooks/eas.md  eas — Run eas build with a clean tree (G-0001)" "playbook rule line"
  t_not_contains "$out" "Unrelated rule" "non-matching rule excluded"
  t_not_contains "$out" "check eas whoami" "checklist lines not searched"
  out="$(wm brief eas --repo myapp)"
  t_contains "$out" "G-0001" "repo filter keeps matching repo"
  t_not_contains "$out" "G-0002" "repo filter drops other repo"
}

test_brief_excludes_obsolete() {
  local out i
  t_br_setup
  t_br_rec gotcha --symptom "Old zebra problem" --cause "c" --fix "f" --match "m" --repo myapp --tags "zebra" --status obsolete
  t_br_rec gotcha --symptom "Live zebra problem" --cause "c" --fix "f" --match "m" --repo myapp --tags "zebra"
  out="$(wm brief zebra)"
  t_contains "$out" "G-0002" "live gotcha listed"
  t_not_contains "$out" "G-0001" "obsolete gotcha excluded"
  # cap: 12 matching entries -> 10 lines; format examples in comments are ignored
  : > "$L/decisions.md"
  printf '  ## D-9999 — 2026-01-01 — indented example giraffe\n' >> "$L/decisions.md"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    printf '\n## D-%04d — 2026-10-28 — giraffe %s\n- **Repo:** myapp\n- **Chose:** x\n' "$i" "$i" >> "$L/decisions.md"
  done
  out="$(wm brief giraffe | grep -c '^D-')"
  t_eq 10 "$out" "max 10 per section"
  t_not_contains "$(wm brief giraffe)" "D-9999" "indented example not an entry"
}

test_brief_docs_summary() {
  local out
  t_br_setup
  mkdir -p "$L/docs/myapp"
  printf '%s\n' '---' 'title: Auth redesign' 'repo: myapp' 'kind: design' 'created: 2026-10-28' 'status: current' 'summary: Moves login to magic links | no passwords' '---' '# Auth' > "$L/docs/myapp/2026-10-28-design-auth.md"
  wm index >/dev/null
  out="$(wm brief magic)"
  t_contains "$out" "Docs
myapp/2026-10-28-design-auth.md  Auth redesign — Moves login to magic links | no passwords" "docs row by summary"
  out="$(wm brief auth --repo other)"
  t_contains "$out" "No prior art for: auth" "repo filter applies to docs"
}

test_brief_none() {
  local out
  t_br_setup
  out="$(wm brief zzz qqq)"
  t_eq "No prior art for: zzz qqq" "$out" "nothing found message"
  t_exit 64 "no terms" -- wm brief
}

test_stats_totals() {
  local out
  t_br_setup
  printf '%s\n' '# Worklog' '' \
    '## 2026-10-26 09:00 — myapp — one' '- **Session:** a' '- **Commits:** 1' '- **Files touched:** 2' '- **Capture:** 4 candidates, 2 recorded, 1 dismissed, 1 deferred' '- **Recall hits:** 2' '- **Handoff:** none' '' \
    '## 2026-10-27 09:00 — myapp — two' '- **Session:** b' '- **Capture:** 3 candidates, 1 recorded, 1 dismissed, 1 deferred' '- **Recall hits:** 1' '' \
    '## 2026-10-28 09:00 — myapp — three' '- **Session:** c' '- **Capture:** 3 candidates, 3 recorded, 0 dismissed, 0 deferred' '- **Recall hits:** 0' > "$L/worklog.md"
  printf 'date\tsession\tid\trepo\n' > "$L/stats/recall.tsv"
  for i in 1 2 3; do printf '2026-10-28\ts%s\tG-0001\tmyapp\n' "$i" >> "$L/stats/recall.tsv"; done
  for i in 1 2; do printf '2026-10-28\ts%s\tD-0002\tmyapp\n' "$i" >> "$L/stats/recall.tsv"; done
  printf '2026-10-28\ts1\t%s\tmyapp\n' C-0001 G-0002 G-0003 G-0004 >> "$L/stats/recall.tsv"
  out="$(wm stats)"
  t_contains "$out" "Worklog entries: 3" "entries"
  t_contains "$out" "Candidates: 10" "candidates"
  t_contains "$out" "Recorded: 6" "recorded"
  t_contains "$out" "Dismissed: 2" "dismissed"
  t_contains "$out" "Deferred: 2" "deferred"
  t_contains "$out" "Capture rate: 80%" "capture rate"
  t_contains "$out" "Recall hits: 3" "recall hits"
  t_contains "$out" "  G-0001  3
  D-0002  2
  C-0001  1
  G-0002  1
  G-0003  1" "top 5 recalled"
  t_not_contains "$out" "G-0004" "only top 5"
  out="$(wm stats --last 2)"
  t_contains "$out" "Worklog entries: 2" "last 2 entries"
  t_contains "$out" "Candidates: 6" "last 2 candidates"
  t_contains "$out" "Capture rate: 83%" "last 2 rate"
  t_contains "$out" "Recall hits: 1" "last 2 hits"
  t_exit 64 "bad --last" -- wm stats --last x
}

# ---------------------------------------------------------------- strays ----
# t_sy_repo <dir> : repo with a tracked README.md and docs/tracked.md
t_sy_repo() {
  mkdir -p "$1/docs"
  printf '# tracked\n' > "$1/docs/tracked.md"
  t_fake_repo "$1"
}

test_strays_reports_untracked() {
  local out W
  W="$WM_SANDBOX_DIR/work"
  t_sy_repo "$W/app"
  printf '# My Notes\nbody\n' > "$W/app/notes.md"
  printf '# x\n' > "$W/app/CHANGELOG.md"
  printf '# x\n' > "$W/app/SECURITY.md"
  printf '# x\n' > "$W/app/CODE_OF_CONDUCT.md"
  printf '# x\n' > "$W/app/claude.md"
  out="$(wm strays --roots "$W")"
  t_contains "$out" "app  0.0  My Notes  $W/app/notes.md" "report line"
  t_not_contains "$out" "tracked.md" "tracked files not reported"
  t_not_contains "$out" "CHANGELOG" "exception name"
  t_not_contains "$out" "SECURITY" "SECURITY exception"
  t_not_contains "$out" "CODE_OF_CONDUCT" "CODE_OF_CONDUCT exception"
  t_not_contains "$out" "claude.md" "exception names case-insensitive"
  t_eq 5 "$(git -C "$W/app" status --porcelain | grep -c '^??')" "repo untouched (still untracked)"
  # layer.conf repo_roots + empty case
  t_br_setup
  printf 'repo_roots=%s\n' "$W" > "$L/layer.conf"
  t_contains "$(wm strays)" "notes.md" "roots from layer.conf"
  t_eq "No stray docs found." "$(wm strays --roots "$WM_SANDBOX_DIR/empty")" "none found"
}

test_strays_ignores_vendor() {
  local out W d
  W="$WM_SANDBOX_DIR/work"
  t_sy_repo "$W/app"
  for d in node_modules/pkg .expo ios/Pods/Foo android/build dist build .next vendor/x .venv/lib target/doc; do
    mkdir -p "$W/app/$d"
    printf '# vendor\n' > "$W/app/$d/V.md"
  done
  printf '# real\n' > "$W/app/real.md"
  out="$(wm strays --roots "$W")"
  t_contains "$out" "real.md" "real stray found"
  t_not_contains "$out" "V.md" "vendor dirs skipped"
}

test_strays_skips_nested_repo() {
  local out W
  W="$WM_SANDBOX_DIR/work"
  t_sy_repo "$W/app"
  mkdir -p "$W/app/libs/inner"
  git -C "$W/app/libs/inner" init -q
  printf '# inner\n' > "$W/app/libs/inner/inner-notes.md"
  printf '# real\n' > "$W/app/real.md"
  out="$(wm strays --roots "$W")"
  t_contains "$out" "real.md" "outer stray found"
  t_not_contains "$out" "inner-notes" "nested repo files skipped"
  t_eq 1 "$(printf '%s\n' "$out" | grep -c .)" "nested repo not reported as own repo"
}

test_strays_keeps_github_dir() {
  local out W
  W="$WM_SANDBOX_DIR/work"
  t_sy_repo "$W/app"
  mkdir -p "$W/app/.github"
  printf '# gh notes\n' > "$W/app/.github/notes.md"
  out="$(wm strays --roots "$W")"
  t_contains "$out" ".github/notes.md" ".github not hidden"
  t_contains "$out" "gh notes" "heading shown"
}

test_strays_repo_with_space() {
  local out W
  W="$WM_SANDBOX_DIR/work dir"
  t_sy_repo "$W/my app"
  printf '#   Spaced   Heading\n' > "$W/my app/some notes.md"
  out="$(wm strays --roots "$W")"
  t_contains "$out" "my app  0.0  Spaced   Heading  $W/my app/some notes.md" "space-safe line"
}

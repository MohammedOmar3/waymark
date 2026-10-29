---
name: review
description: Use for periodic waymark upkeep (/waymark:review), or when the user asks to review, clean up or prune memory. Distils gotchas into playbook rules, flags expired docs and revisit conditions, checks injection size and stats.
---

# waymark review

Gather first, propose second, apply each change only on approval, then commit once with `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" commit "memory: review"`. Layer = the path in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/waymark.conf` (`root=`). Never push.

## Gather
Run and keep the output:
- `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" stats` (capture score and recall-hit trend)
- `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" inbox --all` (leftovers)
- `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" index` (regenerates `docs/INDEX.md`)
- `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" strays` (stray docs outside the layer; report only)

## Analyse
1. Distillation: in `gotchas.md`, group non-obsolete gotchas by tag. For each tag with 3 or more not cited (by ID) in `playbooks/<tag>.md`, propose 1-3 short rules, each citing its gotcha IDs, to append under `## Rules` in that playbook (create it with frontmatter `tag: <tag>` if missing). Where a command pattern recurs across those gotchas, also propose a `triggers:` regex in the frontmatter and a `- [ ]` item under `## Before running a trigger command`.
2. Gotchas that look obsolete (fixed upstream, tool removed): propose `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" status <G-####> obsolete`.
3. Docs marked `(expired)` in `docs/INDEX.md`: list them; propose refresh, supersede or archive.
4. List every `Revisit if:` in `decisions.md` with its D-#### and ask which now hold.
5. Session-start size: run for the current repo, then delete the throwaway active file it creates (`<layer>/active/*--wmreview.md`):
   `printf '{"hook_event_name":"SessionStart","session_id":"wmreview","cwd":"%s","source":"startup"}' "$PWD" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start" | wc -c`
   Report bytes against the 6,000-byte cap; over ~5,000 means propose trimming playbook rules, `repos/<repo>.md` or long gotchas.
6. Worklog: if `worklog.md` has more than 30 entries, propose pruning to the newest 30 (show how many go).
7. Version: compare `plugin_version=` in `<layer>/layer.conf` with `version` in `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. If the plugin is newer, show the exact copy (`${CLAUDE_PLUGIN_ROOT}/bin/` over `<layer>/bin/`, then update `plugin_version=`) and ask approval before touching `<layer>/bin/`.

## Apply
Present one numbered proposal list with exact diffs. Apply only the numbers the user approves, using Edit on the specific lines. Then run `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" index` and `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" commit "memory: review"`. On scan failure show the findings and stop.

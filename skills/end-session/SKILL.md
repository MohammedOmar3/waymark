---
name: end-session
description: Use when the user is wrapping up a session or says "end session", "wrap up", "hand off" (/waymark:end-session). Updates doc status, records a retro for finished plans, writes the handoff and commits memory.
---

# waymark end-session

Session id: the `session:` line in the injected waymark context (pass it as `--session <id8>`).

1. Docs touched this session: for each, confirm its `status` (draft | current | superseded | done | abandoned) and update the frontmatter if it changed. Gotchas fixed or no longer true: `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" status <G-####> open|fixed|obsolete`.
2. If a plan or spec moved to `done`, ask the three retro questions, one line each: what worked, what surprised you, what would you change. Then:
   `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" record retro --doc "<doc path>" --worked "..." --surprised "..." --change "..."`
3. Open inbox candidates: `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" inbox --session <id8>`. For each, record it (see `/waymark:remember`), `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" dismiss <I-id8-n>`, or `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" defer <I-id8-n>`.
4. `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" index`
5. Write one line for the next session (what is done, what is next, any blocker):
   `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" handoff "<text>" --session <id8>`
6. `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" commit "memory: end session"`

If the commit reports a scan failure, show the findings, help remove the secret, and rerun. Never bypass the scan. Do not push anything.

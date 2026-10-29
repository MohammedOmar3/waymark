---
name: remember
description: Use when the user asks to remember, record or save something for future sessions (a gotcha, a decision, or a convention), e.g. "remember that...", /waymark:remember.
---

# waymark remember

Record what the user said, not what you infer. Do not invent field values.

1. Classify the text:
   - gotcha: something broke or surprised and there is a cause and fix.
   - decision: a choice between options with reasons.
   - convention: a standing rule for how work is done.
2. Collect the required fields, asking one short question only for those still missing:
   - gotcha: `--symptom`, `--cause`, `--fix`, `--match` (exact error substring used for automatic recall; a distinctive fragment of the error text). Optional: `--status open|fixed|obsolete` (default fixed).
   - decision: `--decision`, `--chose`, `--because`, `--constraint`, `--revisit` (the condition that should reopen it).
   - convention: `--rule`. Optional `--why`.
   Optional for any kind: `--repo`, `--tags` (default: current repo and its tags).
3. Show the entry in one or two lines and run it (single-line values):

```
"${CLAUDE_PLUGIN_ROOT}/bin/waymark" record gotcha --symptom "..." --cause "..." --fix "..." --match "..."
"${CLAUDE_PLUGIN_ROOT}/bin/waymark" record decision --decision "..." --chose "..." --because "..." --constraint "..." --revisit "..."
"${CLAUDE_PLUGIN_ROOT}/bin/waymark" record convention --rule "..."
```

4. Report the new ID (G-####, D-####, C-####). Exit 2 naming a field means it was missing: ask for it and rerun. If the commit scan failed, the entry is written but uncommitted: show the findings, ask the user to fix them, then run `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" commit "memory: remember"`.
5. If the text matches an open inbox candidate, resolve it with `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" dismiss <I-id8-n>` only after the record succeeded.

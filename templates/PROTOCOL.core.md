# Waymark protocol

- The waymark layer is your memory system. Never use `~/.claude/projects/*/memory/`.
- On start, fill in the `task` field of your active file.
- Before writing any spec, plan or analysis, run `waymark brief <terms>` and add a "Known pitfalls" section that cites the IDs it returns.
- Record only through `waymark record ...`. Never hand-edit `gotchas.md`, `decisions.md` or `conventions.md`.
- When asked to triage candidates, answer each with `record`, `dismiss` or `defer`.
- When a memory informs your work, cite its ID (for example `G-0007`), including in commit messages.
- Before debugging an error, run `grep -n "<error text>" gotchas.md` in the layer.
- Specs, plans and other generated docs go to `<layer>/docs/<repo>/`, named and framed per `DOCS-PROTOCOL.md`. This overrides any skill's default location. "Commit the spec" means `waymark commit`.
- Before a long pause, write a handoff with `waymark handoff`.
- Never edit another session's active file.

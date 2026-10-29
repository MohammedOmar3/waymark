# Changelog

## 0.1.0 - 2026-10-29

Initial release.

- CLI (`waymark record|status|inbox|dismiss|defer|handoff|brief|scan|index|commit|stats|strays|view|init`) written in bash, with locked ID allocation and a secrets scan on every commit.
- Hooks: session-start injection (6,000-byte cap), prompt capture, playbook triggers, failure recall and capture, stop and pre-compact gates, session-end worklog and autosave.
- Skills: `setup`, `remember`, `end-session`, `review`, `uninstall`.
- Offline snapshot viewer (`waymark view`) bundling marked, DOMPurify and mermaid.
- Test suite covering the library, CLI, hooks, skills and viewer.

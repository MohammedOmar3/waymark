# waymark

A waymark is a trail marker left for whoever comes next. Each Claude Code session leaves them for the next one.

Waymark is a git-native engineering notebook for Claude Code with zero runtime dependencies: bash and git only. It captures gotchas, decisions and retros as you work, recalls them in later sessions, and distills them into playbooks. Everything is plain markdown in a git repository you own, so you can read it, diff it, blame it and revert it.

Other memory tools for Claude Code tend to be automatic recall engines that need Node, Python, Docker, vector stores, background workers or extra LLM calls. Waymark takes a different route:

- Plain markdown in git, with long-form docs (specs, plans, analyses) alongside short facts.
- A secrets scan on every commit.
- Awareness of parallel sessions, including several in one repository.
- Deterministic hooks with a fixed context budget (session-start context capped at 6,000 bytes, about 1,500 tokens).
- Capture that does not depend on the model remembering: hooks record raw signal mechanically, and gates make Claude triage it at specific moments.

## Install

From the marketplace:

```
/plugin marketplace add MohammedOmar3/waymark
/plugin install waymark@waymark
```

From a local checkout:

```
/plugin marketplace add /path/to/waymark
/plugin install waymark@waymark
```

Then run the setup skill once:

```
/waymark:setup
```

Setup asks for your name and email, where the memory layer should live (default `~/.claude/waymark`), whether waymark should replace Claude Code's built-in auto-memory, and optional `repo_roots` for stray-doc reports. It shows you the plan, waits for a yes, creates the layer as a git repository, installs a pre-commit scan hook, makes the first commit, and writes the pointer file `~/.claude/waymark.conf`. Until setup has run, sessions only see a one-line note telling you to run it.

## How the loop works

**Capture.** Hooks watch for signal and do not block normal exits.

- A failed Bash command becomes an inbox candidate (command, exit code, the first lines of output, repo), deduplicated per session.
- A prompt containing "remember", "note that", "don't forget" or "for future" creates a mandatory candidate and tells Claude to record it before replying.
- Files written or edited are tracked in the session's active file.
- When Claude tries to stop with untriaged candidates, a gate blocks and asks it to record, dismiss or defer each one. An ordinary candidate gates at most once; a mandatory candidate keeps blocking until it is recorded, dismissed or deferred. After a compaction, the session-start hook that follows it asks Claude to triage and to write a handoff note. The pre-compaction hook only saves state and never blocks.
- When a session ends, a worklog entry is written from facts (commits made, files touched, capture score, recall hits), the handoff is saved, and the layer is autosaved as `chore: autosave session <id8>`.

**Recall.** At session start, waymark injects a capped briefing: the protocol, the repo and its tags, the previous handoff, playbook rules, up to 15 gotcha headings, other active sessions, and one-line warnings. The injection is limited to 6,000 bytes. When a Bash command fails and its output matches a recorded gotcha's `Match:` text, that gotcha (cause and fix) is injected immediately. When a command matches a playbook trigger, the playbook checklist is injected before it runs.

**Distill.** `/waymark:review` proposes turning clusters of gotchas into playbook rules, flags obsolete gotchas and expired docs, and tracks capture and recall trends.

## Commands

Entries are only ever written through the CLI, so IDs and formats stay valid. IDs are `G-####` for gotchas, `D-####` for decisions and retros, `C-####` for conventions, and `I-<id8>-<n>` for inbox candidates.

| Command | Purpose |
|---|---|
| `waymark record gotcha\|decision\|retro\|convention [--from I-n] --field value ...` | Validate, allocate an ID under a lock, append, scan, commit |
| `waymark status G-0007 fixed\|obsolete` | Change an entry's status |
| `waymark inbox` / `dismiss I-n` / `defer I-n` | List and triage candidates |
| `waymark handoff "<text>"` | Write the handoff into the session's active file |
| `waymark brief <terms...>` | Prior-art brief across gotchas, decisions, conventions, playbooks and docs |
| `waymark scan` | Secrets scan of the layer |
| `waymark index` | Regenerate `docs/INDEX.md` |
| `waymark commit "<message>"` | Scan, then commit the layer |
| `waymark stats` | Capture score and recall-hit totals |
| `waymark strays` | Report stray docs in your repositories |
| `waymark view [--no-open]` | Build and open the snapshot viewer |

Skills:

| Skill | Purpose |
|---|---|
| `/waymark:setup` | First-time setup |
| `/waymark:remember` | Record something explicitly |
| `/waymark:end-session` | Update doc statuses, record retros, write the handoff, commit |
| `/waymark:review` | Periodic upkeep and distillation |
| `/waymark:uninstall` | Guided undo |

## The viewer

`waymark view` builds a single self-contained HTML snapshot of your layer and opens it in the browser. It works offline: the renderer and its libraries are bundled with the plugin. The snapshot is rebuilt automatically at the end of each session.

## Privacy

- The raw inbox (`inbox/`) is gitignored, so unreviewed command output never reaches git history.
- Every commit to the layer passes `waymark scan`, via the pre-commit hook and through `waymark commit`. It checks every text file git would commit (the pre-commit hook checks the staged files) for credential-like patterns. Gitignored files such as `active/` and `inbox/` are never committed, so they are not scanned. A failing autosave commits nothing and writes its findings to `active/.scan-failed.log`, which is surfaced at the next session start.
- Hooks never bypass verification or signing.
- Nothing is sent anywhere. There is no network access at runtime. The viewer snapshot carries a Content-Security-Policy that blocks every network request, so a remote image linked in a note is not fetched.

## Limitations

- Repositories with the same directory name share one memory, because the repo name is the key.
- Search is grep only: `Match:` substrings and `waymark brief` terms. There is no semantic or vector search.
- Claude Code only.
- Capture of failures covers Bash commands. Judging what is worth keeping still relies on Claude, which the gates enforce at stop and compaction time but cannot make perfect.

## Uninstall

Run `/waymark:uninstall`. It confirms each step: restores any setting that setup changed to its recorded value, deletes `~/.claude/waymark.conf`, and points you to `/plugin uninstall waymark`. The layer is deleted only on explicit confirmation, and you can keep it (it is an ordinary git repository of markdown that works without the plugin) or zip it first. Waymark never writes to your global `CLAUDE.md` or to any repository.

## Credits

- The hook launcher pattern follows the [superpowers](https://github.com/obra/superpowers) plugin.
- The viewer bundles [marked](https://github.com/markedjs/marked), [DOMPurify](https://github.com/cure53/DOMPurify) and [mermaid](https://github.com/mermaid-js/mermaid). See `viewer/vendor/LICENSES.md`.

## License

MIT. See `LICENSE`.

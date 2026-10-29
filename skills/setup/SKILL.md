---
name: setup
description: Use when the user wants to install, initialise or configure waymark memory for the first time (/waymark:setup), or says waymark is "not set up". Creates the memory layer and optionally replaces Claude's built-in auto-memory.
---

# waymark setup

Interactive, one question group at a time. Nothing outside the layer changes without an explicit yes. Never run `git push` or add a git remote.

## 1. Gather
Ask for each; show the default and accept it on a bare Enter.
1. Owner name (default `git config --global user.name`) and email (default `git config --global user.email`).
2. Layer path (default `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/waymark`). It must not be inside a git repo and must be absent or empty.
3. Replace Claude's built-in auto-memory with waymark? yes/no (default no).
4. `repo_roots` (optional): comma-separated parent folders of the owner's repos, used to find stray docs.
5. Only if `git config --global commit.gpgsign` is `true`: sign layer commits? yes/no. Signing needs a key available non-interactively; if unsure, recommend no for the layer.

Warn if the email domain is a public provider (gmail.com outlook.com hotmail.com live.com icloud.com yahoo.com proton.me protonmail.com): the secrets scan only flags other addresses at the owner's own domain, so other private addresses on a public domain will not be caught. Offer `--email-allowlist` for addresses that are fine to store.

## 2. Play back
Show a table: owner name, email, layer path, replace auto-memory, repo_roots, sign layer. Also list what the yes will do: create the layer (git repo of markdown), copy `bin/` into `<layer>/bin/`, install the pre-commit hook, write `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/waymark.conf`, make the first commit. Ask: "Proceed?" Stop on anything but yes.

## 3. Init
On yes run (omit flags the user left empty):

```
"${CLAUDE_PLUGIN_ROOT}/bin/waymark" init --owner-name "<name>" --owner-email "<email>" --root "<layer>" --repo-roots "<a,b>" --replace-auto-memory yes|no --sign-layer yes|no --email-allowlist "<a,b>" --plugin-root "${CLAUDE_PLUGIN_ROOT}"
```

`init` never touches Claude settings. If it fails, show its message and stop; do not retry with `--force`-style workarounds or delete anything.

## 4. Auto-memory (only if replace = yes)
The setting is `autoMemoryEnabled` (boolean) in the user settings file `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json` (see `docs/hook-contract.md`, "Auto-memory setting"; env alternative `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`).
1. Read the file. Prior value = the current `autoMemoryEnabled` (`true`/`false`) or empty if the key is absent (file missing counts as absent).
2. Record it: edit `<layer>/layer.conf`, setting the line `prior_auto_memory=<value>` (and `replace_auto_memory=yes` if init left it `no`). Commit with `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" commit "memory: record prior auto-memory setting"`.
3. Show the exact one-key change: `"autoMemoryEnabled": false` added to or updated in `settings.json`, nothing else. Ask for approval.
4. On yes, apply it with the Edit tool on that one key. Never rewrite the whole file; preserve all other keys and formatting. If the file does not exist, say so and ask before creating it with just that key.
5. List existing files under `~/.claude/projects/*/memory/` (names and sizes). Do not migrate, move or delete them; tell the user they can ask to have items recorded with `/waymark:remember`.

## 5. Finish
Print the verification table `init` produced. Tell the user: start a fresh session (memory is injected at session start), and run `/waymark:uninstall` to undo.

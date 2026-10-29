---
name: uninstall
description: Use when the user wants to remove waymark or undo its setup (/waymark:uninstall). Restores changed settings, removes the pointer file, and deletes the memory layer only on explicit confirmation.
---

# waymark uninstall

Confirm each step separately; skip a step the user declines. Show the exact change before each. Never run `git push` or touch a remote. Only the steps below touch anything.

Read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/waymark.conf` (`root=` is the layer) and `<layer>/layer.conf` first.

1. Settings: if `replace_auto_memory=yes`, restore `autoMemoryEnabled` in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json` to `prior_auto_memory` with the Edit tool on that key only. If `prior_auto_memory=` is empty, remove the `autoMemoryEnabled` key (and any trailing comma it leaves). Change nothing else. If the layer or `layer.conf` is already gone, say so and ask what value to restore.
2. Delete `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/waymark.conf`.
3. Tell the user to run `/plugin uninstall waymark` themselves (hooks go with the plugin). Nothing was written to global `CLAUDE.md` or any repo.
4. The layer is a plain git repo of markdown and works without the plugin. Offer three choices: keep it (default), zip it first, or delete it.
   - Zip: after approval run `git -C "<layer>" archive --format=zip -o "<zip path>" HEAD` (ask for the path; default `<layer>-backup.zip`, outside the layer). Warn it contains committed files only; uncommitted work is not included, so run `"${CLAUDE_PLUGIN_ROOT}/bin/waymark" commit "memory: before uninstall"` first if the layer is dirty and the user agrees.
   - Delete: only after the user types an explicit yes to deleting `<layer>`, naming the full path and that this cannot be undone. Never delete on a vague answer, and never delete anything but that path.
5. Summarise what was changed and what was left.

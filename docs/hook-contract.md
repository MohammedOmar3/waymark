# Claude Code hook contract (verified for waymark)

Verified on Windows 11, Git Bash, Claude Code 2.1.312, via headless `claude -p ... --settings <tmp>` runs with a dump hook that wrote stdin to files (scratch dir under `$TEMP`, never the real `~/.claude`).
Legend: **[local]** = observed on this machine. **[docs]** = from https://code.claude.com/docs/en/hooks (not exercised locally). Paths below are redacted to `~`.
Note: on Windows, `transcript_path` and `cwd` arrive with backslashes (`~\\.claude\\projects\\...`); hook scripts must normalise (`cygpath -u`) before use.

## Common stdin fields
[local] Every event delivers one single-line JSON object on stdin with: `session_id`, `transcript_path`, `cwd`, `hook_event_name`. Most events also carry `prompt_id`, `permission_mode` (`"default"`), and (tool events and Stop) `effort: {"level":"medium"}`. SessionStart and SessionEnd had no `permission_mode`.
[docs] Also possible: `scratchpad_dir`, `agent_id`/`agent_type` (inside subagents); `model` on SessionStart only. `transcript_path` may lag the live conversation; use `last_assistant_message` on Stop.
Hooks must tolerate unknown/missing fields.
Exit codes [docs]: 0 = success (stdout JSON parsed); 2 = block (on events that can block), stderr is the reason; other non-zero = non-blocking error.

## SessionStart
[local] Sample:
```json
{"session_id":"691978ee-...","transcript_path":"~\\.claude\\projects\\...\\691978ee-....jsonl","cwd":"~\\AppData\\Local\\Temp\\wm-exp\\work","hook_event_name":"SessionStart","source":"startup"}
```
`source` values: `startup`, `resume`, `clear`, `compact`, `fork` [docs]; `startup` and `compact` seen [local] (`/compact` fires a SessionStart with `source:"compact"` and `model`). `model` is optional.
Context injection [docs]: stdout JSON `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}`; plain stdout text also becomes context. Strings over 10,000 chars are written to a file with a 2,000 char preview, so keep injected context small. Cannot block.

## UserPromptSubmit
[local] Sample:
```json
{"session_id":"...","transcript_path":"...","cwd":"...","prompt_id":"66d82fcb-...","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"Run the bash command 'false' ..."}
```
Field `prompt` holds the text. Output [docs]: `hookSpecificOutput.additionalContext` (with `hookEventName":"UserPromptSubmit"`) injects context; `{"decision":"block","reason":"..."}` or exit 2 blocks the prompt.

## PreToolUse deny
[local] Sample stdin:
```json
{"session_id":"...","transcript_path":"...","cwd":"...","prompt_id":"...","permission_mode":"default","effort":{"level":"medium"},"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"false","description":"Run false command"},"tool_use_id":"toolu_01..."}
```
`tool_input.command` for Bash; `tool_input.file_path` for Write/Edit/Read [docs].
Deny output (verified: the command did not run and the reason reached Claude verbatim):
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"WAYMARK-DENY-REASON"}}
```
[docs] `permissionDecision` also accepts `allow`, `ask`, `defer`; `updatedInput` rewrites arguments; exit 2 + stderr also blocks. `additionalContext` is allowed in `hookSpecificOutput` for context next to the tool result.

## PostToolUse Bash failure
**A failed Bash call (non-zero exit) does NOT fire PostToolUse. It fires a separate event `PostToolUseFailure`.** [local] `false` produced only `PostToolUseFailure`; the successful `echo hi` produced only `PostToolUse`.
PostToolUseFailure sample [local]:
```json
{"session_id":"...","transcript_path":"...","cwd":"...","prompt_id":"...","permission_mode":"default","effort":{"level":"medium"},"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"false","description":"Run false command"},"tool_use_id":"toolu_01...","error":"Exit code 1","is_interrupt":false,"duration_ms":1945}
```
There is NO numeric exit-code field. The exit code is only in the string `error`, which starts with `Exit code N` (parse e.g. `sed -n 's/^Exit code \([0-9]*\).*/\1/p'`). [docs] `error` continues with the output text after a newline (e.g. `"Exit code 1\nError: ..."`). `is_interrupt:true` on aborts; cancelled tools do not fire it.
PostToolUse (success) sample [local]:
```json
{"...":"...","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo hi","description":"Print hi"},"tool_response":{"stdout":"hi","stderr":"\nShell cwd was reset to ~\\AppData\\Local\\Temp\\wm-exp\\work","interrupted":false,"isImage":false,"noOutputExpected":false},"tool_use_id":"toolu_01...","duration_ms":102}
```
`tool_response` for Bash has `stdout`, `stderr`, `interrupted`, `isImage`, `noOutputExpected` (no exit code). Hooks that care about failure must register `PostToolUseFailure` (matcher `Bash`) in hooks.json. Output [docs]: `hookSpecificOutput.additionalContext` with `hookEventName` set to the event; exit 2 shows stderr to Claude (tool already ran).

## Stop block
[local] Stop sample:
```json
{"session_id":"...","transcript_path":"...","cwd":"...","prompt_id":"...","permission_mode":"default","effort":{"level":"medium"},"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"...","background_tasks":[],"session_crons":[]}
```
Block output (verified: Claude continued and obeyed the reason):
```json
{"decision":"block","reason":"WAYMARK-TEST: say the word banana before stopping"}
```
On the forced continuation Stop fired again with `"stop_hook_active": true` [local]. Hooks MUST allow stop (print nothing, exit 0) when `stop_hook_active` is true, to avoid loops. [docs] There is also an 8-consecutive-continuation cap; exit 2 + stderr is an equivalent block; `hookSpecificOutput.additionalContext` (`hookEventName":"Stop"`) continues the conversation with non-error "Stop hook feedback". Stop does not fire on user interrupt; API errors fire StopFailure instead.

## PreCompact
[local] Fires in headless mode when `/compact` runs (`claude -p "/compact" -c`; under Git Bash set `MSYS_NO_PATHCONV=1`). Sample:
```json
{"session_id":"...","transcript_path":"...","cwd":"...","prompt_id":"...","hook_event_name":"PreCompact","trigger":"manual","custom_instructions":null}
```
`trigger` = `manual` | `auto` [docs]; `custom_instructions` is the user's `/compact` text or null (always null for auto). The auto trigger was not exercised locally.
**PreCompact CAN block** [local]: `{"decision":"block","reason":"WM-NO-COMPACT"}` made `/compact` print `Compaction blocked by PreCompact hook: [...]: WM-NO-COMPACT`. [docs] exit 2 also blocks; blocking an auto-compact before the context limit just skips it, but blocking one that recovers from a context-limit API error makes the request fail, so waymark must NOT block compaction.
**PreCompact cannot inject context** [docs]: `systemMessage` and `continue` are discarded and no `additionalContext` is documented for it. Not tested locally (no observable channel headless). Fallback (Task 10): use PreCompact only to snapshot state to disk (never block, always exit 0), then re-inject via the SessionStart hook, which fires with `source:"compact"` right after compaction [local] and supports `additionalContext`. PostCompact also exists [local] with `trigger` and `compact_summary` but no decision control [docs].

## SessionEnd
[local] Sample (fired on normal headless exit):
```json
{"session_id":"...","transcript_path":"...","cwd":"...","prompt_id":"...","hook_event_name":"SessionEnd","reason":"other"}
```
`reason`: `clear`, `resume`, `logout`, `prompt_input_exit`, `other` [docs]; `other` seen locally. No decision control; JSON output (e.g. `systemMessage`) is discarded. [docs] Default budget is 1.5 seconds total (applies on exit, `/clear`, `/resume`); a per-hook `timeout` raises it up to 60 s but timeouts on plugin-provided hooks do NOT raise the budget; env `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` sets it explicitly (user-level, not available to a plugin). Waymark's SessionEnd work must finish well under 1.5 s (cheap git/file writes only; detach anything slow).

## Auto-memory setting
[docs: https://code.claude.com/docs/en/memory] Settings key `autoMemoryEnabled` (boolean) in any settings scope: `{"autoMemoryEnabled": false}`. Env alternative: `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. Related: `autoMemoryDirectory` relocates the store. Not exercised locally.

## Plugin env
- hooks.json location [docs]: `hooks/hooks.json` in the plugin, shape `{"hooks":{"Event":[{"matcher":"...","hooks":[{"type":"command","command":"...","timeout":30}]}]}}`.
- `${CLAUDE_PLUGIN_ROOT}` [docs: https://code.claude.com/docs/en/hooks] is substituted in `command` with the plugin install dir, and is also exported as env var `CLAUDE_PLUGIN_ROOT` (plus `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_DATA`). Wrap the placeholder in double quotes in shell form (install paths may contain spaces, e.g. a Windows user dir).
- Windows shell [reference: installed superpowers 7.0.0 hooks.json]: it uses `"command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start", "shell": "bash"`. Its run-hook.cmd comment states Claude Code's Windows auto-detection prepends `bash` to any command containing `.sh`, hence extensionless scripts. The per-hook `"shell":"bash"` field is honoured [local]: a command of the form `C:/.../dump.sh` with `"shell":"bash"` ran under Git Bash and received stdin. For waymark: use `"shell":"bash"`, quote `"${CLAUDE_PLUGIN_ROOT}/hooks/<script>"`, `#!/usr/bin/env bash`, LF line endings, and `cygpath -u` for incoming Windows paths. Plugin-loaded `${CLAUDE_PLUGIN_ROOT}` expansion itself was not exercised locally (experiments used `--settings` hooks, which behave identically for stdin/output).

## Sources
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/memory
- Installed plugin reference: `~/.claude/plugins/cache/claude-plugins-official/superpowers/7.0.0/hooks/`

# Agent Status Hooks

Alera recognizes agent activity by installing hooks into each agent's **user global config**. It does not use runtime homes, config overlays, symlinks, or per-agent wrappers for that path. fx is the exception: it reports through its built-in Herdr integration and does not write user hook files.

Every switch defaults off. Enabling a switch writes Alera-scoped entries; disabling it removes only those entries. User-owned config stays. The runtime host is the writer (`prepare_enabled_integrations`). Install is idempotent: an already-current file is left byte-identical.

## What Alera writes

For the desktop profile launch dialog and persistent conversation binding, see [Agent Session Resume](agent-session-resume.md).

Alera-managed hook commands include `alera-runtime-agent-hook` in the command string. Older versions used per-agent names such as `alera-claude-hook.sh`; cleanup still recognizes those. Plugin files start with the comment `ALERA_AGENT_STATUS_MANAGED_FILE`.

| Agent | File | Shape |
| --- | --- | --- |
| Codex | `~/.codex/hooks.json` and `~/.codex/config.toml` | Merged hook definitions plus Alera-owned trust records. `$CODEX_HOME` is used when it is not an older Alera runtime-home leftover. |
| Claude Code | `~/.claude/settings.json` | Merged `hooks` object. `~/.claude/settings.local.json` is cleaned of leftovers only. |
| GitHub Copilot | `~/.copilot/hooks/alera.json` | Dedicated Alera file. `$COPILOT_HOME` is honored. On Windows each entry is a `powershell` command that posts by itself: Copilot runs that field as `pwsh -nop -nol -c`, never a `bash` one, and a failing `preToolUse` hook denies the tool. |
| Cursor | `~/.cursor/hooks.json` | Merged command entries with a 5s timeout. `sessionStart` is not registered. |
| Antigravity | `~/.gemini/config/hooks.json` | Top-level `alera-status` bundle. |
| Grok Build | `~/.grok/hooks/alera-status.json` | Dedicated Alera file. `$GROK_HOME` is honored. |
| OpenCode | `~/.config/opencode/plugins/alera-agent-status.js` | Dedicated plugin. `$OPENCODE_CONFIG_DIR` is honored. |
| OpenCode 2 | `~/.config/opencode/plugins/alera-agent-status-v2.js` | Dedicated plugin. Same config dir as v1. It reports only from a private server (`opencode2 --standalone`, which Alera's launches use): the shared background service carries the environment of whichever tab started it. |
| Pi | `~/.pi/agent/extensions/alera-agent-status.ts` | Dedicated extension. `$PI_CODING_AGENT_DIR` is honored. |
| Amp | `~/.config/amp/plugins/alera-agent-status.ts` | Dedicated plugin. `$AMP_CONFIG_DIR` is honored. |
| fx | none | Herdr socket and pane id in the terminal environment. fx reports its conversation id with `pane.report_agent_session` at startup, which binds the tab for `fx --resume`. |

The shared hook script lives at `~/.alera/agent-hooks/alera-runtime-agent-hook.sh` (`.cmd` on Windows). It no-ops unless the terminal identity environment is present, so hooks that fire outside an Alera terminal do not report.

## How to clean

The reversible path is the matching Settings (or `alera runtime agents disable`) toggle. That removes only Alera-marked definitions or dedicated Alera files.

To clean by hand without Alera:

1. Dedicated files (Copilot `hooks/alera.json`, Grok `hooks/alera-status.json`, OpenCode/Pi/Amp plugin files): delete the file if it contains `alera-runtime-agent-hook` or `ALERA_AGENT_STATUS_MANAGED_FILE`. Do not delete sibling user files in the same directory.
2. Merged JSON (Claude `settings.json`, Cursor `hooks.json`, Codex `hooks.json`, Antigravity `hooks.json`): remove array entries whose command contains `alera-runtime-agent-hook` or a legacy `alera-<agent>-hook` name. Keep every other entry. For Antigravity, drop the `alera-status` object if it is empty after that.
3. Codex `config.toml`: remove `[hooks.state]` keys that point at `agent-runtime-homes/codex` or at Alera commands in `hooks.json`. Do not disable `features.hooks` if other hooks remain.
4. Older overlay leftovers under the runtime directory (`agent-runtime-homes/`, `agent-runtime-overlays/`): delete those directories. Host start already does this. Desktop application-support copies of the same names from older app versions can be deleted the same way; they are not user config.

Unparseable user files are left untouched.

## Which events end a turn

Hooks only report what an agent announces, and the obvious event does not cover every way a turn ends. Agents also snapshot their hooks: a running Claude picks up edits through its settings watcher, but a running Codex keeps the hooks it started with until it is restarted.

- **Claude Code** skips `Stop` for an interrupted turn and for an API error. Alera also installs `StopFailure`, reads `is_interrupt` on `PostToolUseFailure`, and treats the `idle_prompt` notification (a minute of idle input) as the end of the turn. `permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog` and `worker_permission_prompt` notifications mean `waiting`. `SessionEnd` clears the tab when the process ends; with reason `clear` or `resume` the same process carries on, so the tab turns `done` instead. `SessionStart` turns an existing status `done` for every source but `compact`, and never creates one for an agent nobody has used yet. `SessionEnd` asks for a five-second timeout because Claude otherwise allows 1.5 seconds and the Windows hook starts PowerShell first.
- **Codex** skips `Stop` for an aborted turn and runs `Interrupt` instead (0.150 and later); `SessionEnd` (0.145 and later) clears the tab. Older releases ignore both keys. Codex runs them with a one-second default and a three-second cap; Alera writes `timeout: 3`, and its trust records hash that normalized timeout (Codex hashes the handler, timeout included). Codex ends a replaced thread only when it unloads it, well after `/new`, so a `SessionEnd` must name the conversation the tab is showing.
- **Grok** fires `StopCancelled` instead of `Stop` for Ctrl+C, a declined permission, the turn limit and a no-progress bail-out. Its notifications are read by `notificationType` (`idle_prompt`, `permission_prompt`), with the display text only as a fallback. Turn-end reports queue behind one worker and can land after the next prompt, so a turn-end whose `promptId` is not the current turn is dropped.
- **Copilot** `SessionStart` and **Amp** `session.start` bind the conversation but set no status: both also fire when a session is only opened or resumed.
- **Cursor** reads `is_interrupt` on `postToolUseFailure`; `stop` with `status: aborted` or `error` reports as interrupted.
- **Pi** also reports `agent_settled`, the final signal after retries and queued work (older releases end on `agent_end`), and `ui_prompt_start` / `ui_prompt_end` for blocking dialogs. Its handlers only enqueue: Pi awaits each handler, so a network call there would stall the agent.
- **OpenCode** reports `busy` again once a permission or question prompt is answered, because the session never leaves `busy` during the prompt.

A `done` that follows `idle_prompt` from `waiting` is marked inferred (see below): the prompt may have belonged to a dialog.

A Claude `SessionStart` for `startup`, `clear` or `fork` names a conversation with no transcript yet, so it never replaces the conversation bound to the tab for resume. `resume` does.

## Nested agents and sub-agents

An agent that the tab's agent runs as a tool (`codex exec`, `claude -p`, a review loop) inherits the tab's environment and reports through the same hooks. It must not finish the tab's turn, change the agent type, retitle the tab or rebind the conversation used for resume. The host decides in this order:

1. The hook script forwards Claude's `CLAUDE_PID`. When both the tab's status and the hook name a process, a hook from another process is nested for as long as the tab's agent process is alive, even after its turn ended. A relaunched agent (the old pid is gone) takes over.
2. Otherwise, while the tab's turn is running and its process group is still alive, a hook from a different native conversation id is nested. A finished or stale (30 minutes) turn lets the next conversation take over.

Sub-agents are part of the tab's agent: Claude and Codex keep the root `session_id` and add `agent_id`, Grok gives the child its own session tagged `subagentType`, and OpenCode and older Codex name the parent (`parent_session_id`, `parent_thread_id`). A sub-agent hook may ask for attention (`waiting`, `blocked`) and keep a running turn fresh, but it never ends the turn, closes the session or rebinds the conversation. For every agent but Claude it also never reopens a finished turn.

Claude's background sub-agents keep working after the main turn fires `Stop`, and the main agent often stops only to wait for them. Alera installs `SubagentStart` and `SubagentStop` and the host keeps a roster of the tab's children by `agent_id` (`claude_subagent_roster.rs`, memory only), next to the state the main agent's own hooks reported:

- The tab shows the main agent's `waiting` or `blocked` first, then `waiting` while any child waits for an answer (a permission prompt or `AskUserQuestion` inside the child), then `working` while the main turn or any child runs, and `done` only when the main turn ended and no child is left. That `done` is the one that accepts injection and push-on-idle.
- A child's own tool activity clears a main-agent `waiting` that Claude announced without naming a child (a `permission_prompt` notification, which follows a child's prompt as well as the main agent's) or that came from a child the full roster could not track. It never clears the main agent's own `PermissionRequest`, `PreToolUse` or `AskUserQuestion` prompt, and a notification for a prompt the main agent's own hook already raised keeps it the main agent's.
- A child's id is remembered once it stops, so any hook that posts after its `SubagentStop`, a question included, changes nothing. A later `SubagentStart` does revive it (teammates reuse their id every turn). A child hook never creates the tab's presence: only the main agent's hooks record the process the exit and silence sweeps watch.
- On `Stop` and `SubagentStop`, newer Claude releases list the main session's `background_tasks`: running `subagent` entries are adopted and unlisted ones are dropped, which recovers a lost `SubagentStop`. The child that is stopping is finished first, so an inventory that still lists it cannot revive it. `teammate` entries never name lifecycle ids, so while one is listed an unlisted teammate-shaped id (`a<name>-<hex>`) stays. Without the field the roster is left to the lifecycle hooks.
- An interrupted turn and a new conversation (`SessionStart`, `SessionEnd` for `clear`/`resume`) drop the roster: foreground children die with them, and a background child that survived reports again on its next hook.
- Background shells and crons in `background_tasks` do not keep the tab working: a dev server would hold it open forever.

## Activity without hooks

The runtime host reconciles presence every five seconds against what it can observe itself, for presence produced by its own hook receiver. Hooks a satellite relays to the hub are reconciled on the satellite:

- **Agent exited.** Each hook records the PTY's foreground process group, which is the agent's while it runs. Once no process is left in that group (the agent quit, crashed or was killed with `Ctrl+C`), the tab's status is removed as if the agent had sent its session-end hook. Where there is no job control (Windows), the pid the agent reports stands in for the group (Claude's `CLAUDE_PID`); other agents there rely on their session-end hooks and the silence rule.
- **Silent turn.** Every supported agent TUI redraws a spinner or an elapsed-time counter while a turn runs, tool calls included. A `working` status with no PTY output and no hook for 60 seconds becomes `done`. While a Claude sub-agent holds a finished main turn open the TUI may sit still at its prompt, so that silence has to last 15 minutes instead (child hooks fire around every tool call and Claude caps one Bash call at ten minutes); after that the roster is dropped as lost. A main turn that really ended keeps its confirmed `done`, so the next hook makes it injection-ready again. A hub applies this one rule to a remote Claude tab too, from the relayed hooks and the proxy's output, because the roster lives where the hooks are handled; exit detection for that tab stays on the satellite.

An inferred `done` (from the silence rule, or `idle_prompt` after `waiting`) never accepts orchestration or push-on-idle injection, because the agent may be sitting in a prompt no hook announced. `agentPresence.list` and `orchestration terminal list` report it as `inferredIdle: true`, `orchestration terminal show` does not call it `agent_ready`, and a hub mirrors the flag from its satellites. The next real hook replaces it.

Inside `tmux`, `screen` or `zellij` the tab's PTY shows the multiplexer client, not the agent: detaching would read as an exit and a hidden window as silence. The host leaves that presence to the agent's own hooks when the tab's foreground process is a multiplexer client (`tmux`, `screen`, `zellij`, `abduco`, `dtach`), and the hook script, the plugins and the Windows hooks also report the multiplexer they run under, so a reporter that cannot (fx) is still covered. Known gap: an agent that runs another agent in the background after its own turn ended is only recognized as nested for Claude (through its pid).

## Activity after migrate

New terminals do not set `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, or a Cursor wrapper `PATH` entry. Agents read their own global config, so activity recognition keeps working for the supported agents listed above as long as the matching toggle stays on. Nested Alera terminals still strip inherited overlay variables from older hosts so a parent runtime home cannot shadow the user config.

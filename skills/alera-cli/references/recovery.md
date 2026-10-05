# Runtime And Metadata Recovery

## Quick Checks

Start with runtime and inventory checks:

These commands are the same from Bash, PowerShell, and CMD:

```bash
alera runtime status
alera project list
alera workspace list --all
```

Use `--json` when you need machine-readable output:

These commands are the same from Bash, PowerShell, and CMD:

```bash
alera project --json list
alera workspace --json list --all
```

Outside Alera terminals, set `ALERA_RUNTIME_DIR` or pass `--runtime-dir` after the command group.

From Linux, macOS, or WSL:

```bash
ALERA_RUNTIME_DIR="$HOME/.alera/runtime" alera workspace list --all
alera workspace --runtime-dir "$HOME/.alera/runtime" list --all
```

From PowerShell:

```powershell
$env:ALERA_RUNTIME_DIR = "$HOME\.alera\runtime"
alera workspace list --all
alera workspace --runtime-dir "$HOME\.alera\runtime" list --all
```

From `cmd.exe`:

```cmd
set "ALERA_RUNTIME_DIR=%USERPROFILE%\.alera\runtime"
alera workspace list --all
alera workspace --runtime-dir "%USERPROFILE%\.alera\runtime" list --all
```

## Metadata-Only Recovery

Use these only for repair or migration tasks where Git worktrees must not be touched. `--host-id` stamps host metadata on the record. It is metadata only and does not create a remote Git worktree:

From Linux, macOS, or WSL:

```bash
alera workspace register --project-id <project-id> --name "<name>" --path "$HOME/Projects/workspaces/existing" --branch <branch>
alera workspace unregister --id <workspace-id>
```

From PowerShell:

```powershell
alera workspace register --project-id <project-id> --name "<name>" --path "$HOME\Projects\workspaces\existing" --branch <branch>
alera workspace unregister --id <workspace-id>
```

From `cmd.exe`:

```cmd
alera workspace register --project-id <project-id> --name "<name>" --path "%USERPROFILE%\Projects\workspaces\existing" --branch <branch>
alera workspace unregister --id <workspace-id>
```

If no runtime host is available, retry the same managed CLI command once; it can auto-start the host. If the retry fails, inspect the reported error before further recovery.

## Agent Not Linked To Its Tab

A tab can stop reflecting its agent's status (working, waiting, done) while the agent keeps running: the agent's hooks report through the terminal identity in its launch environment, and the host ignores them when that identity no longer matches the tab or when it takes the agent for a nested one. `alera tab link-agent` binds the running agent to the tab again. It does not explain or fix why the link was lost.

Run it from the agent's own shell tool. Inside Claude Code (`CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID`) and Codex (`CODEX_THREAD_ID`) every option is detected, and the tab defaults to `ALERA_TAB_ID`:

```bash
alera tab link-agent
alera tab link-agent --tab <tab-id>
```

From any other shell, or for another agent, name the tab, the agent and at least its conversation id or process id:

```bash
alera tab link-agent --tab <tab-id> --agent opencode --session-id <conversation-id>
alera tab link-agent --tab <tab-id> --agent claude --session-id <conversation-id> --pid <pid> --source-terminal <terminal-id>
```

What the host does:

- Replaces the tab's agent status with the given agent, its conversation id and process id, so its hooks are no longer taken for a nested agent. `--state` (`working` by default, or `waiting`, `blocked`, `done`) is shown until the next hook.
- Saves the conversation id as the one the tab resumes.
- When the agent's environment names another terminal (`--source-terminal`, default `ALERA_TERMINAL_SESSION_ID`), routes that agent's later hooks from that terminal to this tab. Only hooks with the same conversation id or process id are routed; a Claude `/clear` keeps the route through its process id. Routes live in memory: they end when the tab's terminal stops or the runtime host restarts, and running the command again from inside the tab removes them.

Limits: the tab needs a running terminal on the local runtime. An agent started without any `ALERA_*` environment (outside an Alera terminal) sends no hooks, so the command shows its status once and nothing updates it afterwards. A new Codex conversation (`/new`) needs the command again. Check the result with `alera terminal show --handle <terminal-id>`.

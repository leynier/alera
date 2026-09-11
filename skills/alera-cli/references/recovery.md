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

# Projects And Workspaces

## Projects

Register a Git project:

From Linux, macOS, or WSL:

```bash
alera project add --name "Alera" --repo-path "$HOME/Projects/Alera" --kind git-repository
```

From PowerShell:

```powershell
alera project add --name "Alera" --repo-path "$HOME\Projects\Alera" --kind git-repository
```

From `cmd.exe`:

```cmd
alera project add --name "Alera" --repo-path "%USERPROFILE%\Projects\Alera" --kind git-repository
```

Register a local folder project that is not treated as a Git repository:

From Linux, macOS, or WSL:

```bash
alera project add --name "Notes" --repo-path "$HOME/Notes" --kind folder
```

From PowerShell:

```powershell
alera project add --name "Notes" --repo-path "$HOME\Notes" --kind folder
```

From `cmd.exe`:

```cmd
alera project add --name "Notes" --repo-path "%USERPROFILE%\Notes" --kind folder
```

Remove a project and its runtime-owned child records:

This command is the same from Bash, PowerShell, and CMD:

```bash
alera project remove --id <project-id>
```

## Managed Workspaces

Create a new Git worktree workspace from a source branch:

This command is the same from Bash, PowerShell, and CMD when no explicit path is passed:

```bash
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --name "<display-name>"
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --host-id <ssh-target-id>
```

Create and link a child workspace in the same atomic operation:

```bash
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --parent-workspace-id <parent-workspace-id>
```

Use an exact destination path only when the user requests it:

From Linux, macOS, or WSL:

```bash
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --path "$HOME/Projects/workspaces/new-workspace"
```

From PowerShell:

```powershell
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --path "$HOME\Projects\workspaces\new-workspace"
```

From `cmd.exe`:

```cmd
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --path "%USERPROFILE%\Projects\workspaces\new-workspace"
```

Use a temporary root override when the user wants the default naming scheme under a different root:

From Linux, macOS, or WSL:

```bash
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --workspace-root "$HOME/Projects/workspaces"
```

From PowerShell:

```powershell
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --workspace-root "$HOME\Projects\workspaces"
```

From `cmd.exe`:

```cmd
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --workspace-root "%USERPROFILE%\Projects\workspaces"
```

`--path` and `--workspace-root` are mutually exclusive. Without either flag, Alera uses the runtime workspace directory setting, then falls back to the user's `.alera/workspaces` directory (`$HOME/.alera/workspaces` on Unix-like shells, `$HOME\.alera\workspaces` in PowerShell, or `%USERPROFILE%\.alera\workspaces` in CMD).

Focus a workspace on an existing local branch:

This command is the same from Bash, PowerShell, and CMD:

```bash
alera workspace add --project-id <project-id> --branch <existing-branch> --reuse-existing-branch --name "<display-name>"
```

Create a managed workspace and launch a declared agent profile in one step. From an Alera terminal this infers project, source branch, and parent from `ALERA_WORKSPACE_ID`. Pass `--branch` and `--name` to skip identity generation, and `--no-parent` to skip the parent link:

```bash
alera workspace --json start --profile "Codex Sol" --prompt "Add dark mode"
alera workspace --json start --profile "Codex Sol" --prompt "Add dark mode" --project-id <project-id> --source-branch main --branch feat/dark-mode --name "Dark Mode" --no-parent
```

Move the main worktree's current work into a new child workspace (hand off). From an Alera terminal this defaults to `ALERA_WORKSPACE_ID`:

This command is the same from Bash, PowerShell, and CMD:

```bash
alera workspace hand-off --branch feat/isolated-change --name "Isolated Change"
```

Reuse the branch already checked out on main:

```bash
alera workspace hand-off --branch feat/current --reuse-existing-branch
```

Bring a child worktree's current work back onto main (hand on), then remove that child workspace. The branch is kept:

```bash
alera workspace hand-on
alera workspace hand-on --id <child-workspace-id>
```

After a successful hand off or hand on, live shells in the moved work are sent a best-effort `cd` to the new path, and awake agents are told `hand off`/`hand on` happened `X → Y`. A dead PTY or missing shell is skipped. A failed prepare or git move leaves session cwd and agent UI unchanged.

Remove a managed workspace:

This command is the same from Bash, PowerShell, and CMD:

```bash
alera workspace remove --id <workspace-id>
```

By default, Alera deletes the branch only when Alera created it. Override that behavior explicitly:

These commands are the same from Bash, PowerShell, and CMD:

```bash
alera workspace remove --id <workspace-id> --delete-branch
alera workspace remove --id <workspace-id> --keep-branch
```

## Tags, Tabs, And Relations

Common runtime metadata commands:

These commands are the same from Bash, PowerShell, and CMD:

```bash
alera tag list
alera tag upsert --name "Review" --color "#3b82f6"
alera workspace tag --workspace-id <workspace-id> --tag-id <tag-id>
alera workspace untag --workspace-id <workspace-id> --tag-id <tag-id>
alera workspace link --parent-workspace-id <parent-id> --child-workspace-id <child-id>
alera workspace pin --id <workspace-id>
alera workspace unpin --id <workspace-id>
alera tab list --workspace-id <workspace-id>
alera tab create --workspace-id <workspace-id> --title "Terminal" --kind terminal
```

Read retained terminal output or write input without opening the UI:

```bash
alera terminal read --handle <terminal-handle> --max-bytes 65536
alera terminal read --handle <terminal-handle> --cursor <next-cursor>
alera terminal write --handle <terminal-handle> --text "continue" --enter
alera terminal write --handle <terminal-handle> --stdin --enter
```

JSON list commands return a consistent `{ "kind": "...", "items": [...], "filters": {...} }` envelope. Read `items` rather than relying on a resource-specific top-level array.

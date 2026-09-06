---
name: alera-cli
description: Use when operating Alera-managed projects, workspaces, worktrees, tabs, tags, Agent Profiles, SSH targets, or runtime state from an Alera terminal. Prefer this skill over raw git worktree commands when the task touches Alera workspace lifecycle or runtime metadata.
---

# Alera CLI

## Overview

Use the `alera` CLI to inspect and modify Alera runtime state. In Alera-managed terminals the app prepends a managed `alera` shim to `PATH` and sets `ALERA_RUNTIME_DIR`, so commands target the same runtime profile used by the UI.

When creating or removing Alera workspaces, use `alera workspace add` and `alera workspace remove`. Do not run `git worktree add`, `git worktree remove`, or edit runtime metadata directly unless the user explicitly asks for low-level recovery.

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

## Metadata-Only Recovery

Use these only for repair or migration tasks where Git worktrees must not be touched:

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

## Agent Profiles

Inspect the user-approved launch catalog:

```bash
alera agent-profile list
alera agent-profile --json show --profile-name "Codex Sol"
```

Create Command or Managed profiles through the authenticated runtime host:

```bash
alera agent-profile create --name "Codex Sol" --agent-type codex --launch-mode command --command "codex --search"
alera agent-profile create --name "Managed Codex" --agent-type codex --launch-mode managed --managed-config-file profile.json
```

Updates patch only the supplied fields. Use `--expected-revision` when a script must pin the revision it previously observed. Changing `--agent-type` on an existing Managed profile requires a new configuration through `--managed-config`, `--managed-config-file`, or `--managed-config-stdin`. Settings that newly reduce protections require `--confirm-reduced-protections`.

Preview removal impact before explicitly confirming deletion:

```bash
alera agent-profile removal-impact --profile-id <profile-id>
alera agent-profile remove --profile-id <profile-id> --confirm
```

Use `alera agent-profile reorder --id <id> --id <id>` with every current profile id exactly once to replace the persisted order. Keep `alera orchestration agent-profiles` for coordinator discovery; it does not mutate the catalog.

For model research, quota-aware catalog design, adapter-specific Managed configuration, or profile launch smoke tests, invoke the `alera-agent-profiles` skill. Keep ordinary list, show, and narrowly specified mutations here.

## Agent Rules

- Prefer `alera workspace add/remove` over raw Git when operating Alera-managed workspaces.
- Use metadata-only `register/unregister` only when intentionally avoiding filesystem or Git changes.
- Run list/status commands before destructive operations so you have the exact IDs.
- Use `workspace pin/unpin` for the persisted desktop sidebar section instead of editing runtime metadata directly.
- Keep user-created branches unless the user explicitly requests deletion or the workspace metadata shows Alera created the branch.
- If a command fails because no runtime host is available, retry the same CLI command; managed commands auto-start the runtime host when possible.

## Inter-Agent Orchestration

For structured multi-agent coordination - inter-agent messaging, task DAGs, dispatching work to worker agents, decision gates, and coordinator loops - invoke the `alera-orchestration` skill. Its command surface lives under `alera orchestration ...`.

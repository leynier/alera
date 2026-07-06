---
name: alera-cli
description: Use when operating Alera-managed projects, workspaces, worktrees, tabs, tags, SSH targets, or runtime state from an Alera terminal. Prefer this skill over raw git worktree commands when the task touches Alera workspace lifecycle or runtime metadata.
---

# Alera CLI

## Overview

Use the `alera` CLI to inspect and modify Alera runtime state. In Alera-managed terminals the app prepends a managed `alera` shim to `PATH` and sets `ALERA_RUNTIME_DIR`, so commands target the same runtime profile used by the UI.

When creating or removing Alera workspaces, use `alera workspace add` and `alera workspace remove`. Do not run `git worktree add`, `git worktree remove`, or edit runtime metadata directly unless the user explicitly asks for low-level recovery.

## Quick Checks

Start with runtime and inventory checks:

```bash
alera runtime status
alera project list
alera workspace list --all
```

Use `--json` when you need machine-readable output:

```bash
alera project --json list
alera workspace --json list --all
```

Outside Alera terminals, set `ALERA_RUNTIME_DIR` or pass `--runtime-dir` after the command group:

```bash
ALERA_RUNTIME_DIR="$HOME/.alera/runtime" alera workspace list --all
alera workspace --runtime-dir "$HOME/.alera/runtime" list --all
```

## Projects

Register a Git project:

```bash
alera project add --name "Alera" --repo-path /path/to/repo --kind git-repository
```

Register a local folder project that is not treated as a Git repository:

```bash
alera project add --name "Notes" --repo-path /path/to/folder --kind folder
```

Remove a project and its runtime-owned child records:

```bash
alera project remove --id <project-id>
```

## Managed Workspaces

Create a new Git worktree workspace from a source branch:

```bash
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --name "<display-name>"
```

Use an exact destination path only when the user requests it:

```bash
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --path /exact/workspace/path
```

Use a temporary root override when the user wants the default naming scheme under a different root:

```bash
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --workspace-root /path/to/workspace/root
```

`--path` and `--workspace-root` are mutually exclusive. Without either flag, Alera uses the runtime workspace directory setting, then falls back to `~/.alera/workspaces`.

Focus a workspace on an existing local branch:

```bash
alera workspace add --project-id <project-id> --branch <existing-branch> --reuse-existing-branch --name "<display-name>"
```

Remove a managed workspace:

```bash
alera workspace remove --id <workspace-id>
```

By default, Alera deletes the branch only when Alera created it. Override that behavior explicitly:

```bash
alera workspace remove --id <workspace-id> --delete-branch
alera workspace remove --id <workspace-id> --keep-branch
```

## Metadata-Only Recovery

Use these only for repair or migration tasks where Git worktrees must not be touched:

```bash
alera workspace register --project-id <project-id> --name "<name>" --path /path/to/workspace --branch <branch>
alera workspace unregister --id <workspace-id>
```

## Tags, Tabs, And Relations

Common runtime metadata commands:

```bash
alera tag list
alera tag upsert --name "Review" --color "#3b82f6"
alera workspace tag --workspace-id <workspace-id> --tag-id <tag-id>
alera workspace untag --workspace-id <workspace-id> --tag-id <tag-id>
alera workspace link --parent-workspace-id <parent-id> --child-workspace-id <child-id>
alera tab list --workspace-id <workspace-id>
alera tab create --workspace-id <workspace-id> --title "Terminal" --kind terminal
```

## Agent Rules

- Prefer `alera workspace add/remove` over raw Git when operating Alera-managed workspaces.
- Use metadata-only `register/unregister` only when intentionally avoiding filesystem or Git changes.
- Run list/status commands before destructive operations so you have the exact IDs.
- Keep user-created branches unless the user explicitly requests deletion or the workspace metadata shows Alera created the branch.
- If a command fails because no runtime host is available, retry the same CLI command; managed commands auto-start the runtime host when possible.

## Inter-Agent Orchestration

For structured multi-agent coordination — inter-agent messaging, task DAGs, dispatching work to worker agents, decision gates, and coordinator loops — invoke the `alera-orchestration` skill. Its command surface lives under `alera orchestration ...`.

---
title: "Automate New Worktree Setup With Alera.toml"
description: "Every new worktree needs the same ritual: copy the .env, install dependencies, bootstrap. We made the repo describe it once."
pubDate: 2026-07-28T13:00:00.000Z
---

You know the ritual. You create a fresh worktree for an agent, and before it can do anything useful you are copying `.env` from the main checkout, remembering which config files are gitignored but required, running install, running bootstrap. Ninety seconds of chores, every single time, multiplied by every agent you want in parallel.

We got tired of performing that ritual by hand, so we taught Alera to perform it for us. The instructions live in a file you own: `alera.toml`, at the project root.

## What It Looks Like

```toml
[worktree]
copy = [
  { from = ".env", to = ".env", overwrite = false },
  { from = ".claude/settings.local.json" }
]
setup = [
  "pnpm install",
  "make bootstrap"
]
```

Two ideas, nothing more:

- `copy` brings files or directories from the main project checkout into the new linked workspace. `to` defaults to `from`, and `overwrite` defaults to `false` so an existing file never gets clobbered silently.
- `setup` runs commands sequentially from the new workspace root and stops at the first non-zero exit, because continuing a bootstrap after a failure is how you get mysteriously broken environments.

Paths are repo-relative literals. Absolute paths and `..` escapes are rejected outright. Globs and custom command environments did not make v1; we would rather ship a small feature that is easy to reason about than a clever one that surprises you.

## When It Runs (And When It Does Not)

Setup applies only to **new linked workspaces that Alera creates**. It does not run for the main workspace, for workspaces discovered during reconcile, or on removal. That scoping is deliberate: automation should fire at the one moment you asked for something new, not retroactively on things that already exist.

Failure handling follows the same philosophy. If a copy or setup step fails after the Git worktree already exists, Alera keeps and opens the workspace and shows you a setup warning. A half-configured worktree you can see and fix beats a silent rollback you never hear about.

## Precedence: Your UI Choice Wins

Per-project settings in **Settings → Projects** are the source of truth when present. Choosing **Use Repo File** clears that override and falls back to `alera.toml`. When neither exists, there is simply no setup, and nothing happens. No hidden defaults.

## One File, One More Job

The same file can also declare how Pull Requests should talk to your forge:

```toml
git_hosting_provider = "github" # or "gitlab" / "azureDevops"
```

Without it, Alera auto-detects GitHub.com, GitLab.com, and Azure DevOps from `origin`. Set it explicitly for self-hosted instances. Authentication stays where it belongs, with `gh`, `glab`, or `az`.

Combined with [worktree-native parallel agents](/blog/run-cli-agents-in-parallel-with-git-worktrees), this turns "new branch for this agent" from a checklist into a non-event. Write the ritual once, then forget it exists.

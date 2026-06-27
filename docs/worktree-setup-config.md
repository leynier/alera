# Worktree Setup Config

Alera can run project-specific setup after it creates a linked workspace. The setup applies only to new Alera-created linked workspaces; it does not run for the main workspace, existing workspaces found during reconcile, or workspace removal.

## Precedence

Per-project settings saved in **Settings > Projects** are the source of truth when present. Selecting **Use Repo File** removes that UI override and makes Alera fall back to the repository file.

When no UI override exists, Alera reads `alera.toml` from the project root. Missing files mean no setup actions.

## `alera.toml`

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

`copy` entries copy files or directories from the main project checkout into the new linked workspace. `to` defaults to `from`, and `overwrite` defaults to `false`.

`setup` commands run sequentially from the new linked workspace root. Commands stop on the first non-zero exit code.

Paths are repo-relative literal paths. Absolute paths and `..` escapes are rejected. Globs and custom command environments are not part of v1.

If a copy or setup action fails after the Git worktree is created, Alera keeps and opens the workspace, then surfaces a setup warning so the user can fix the workspace in place.

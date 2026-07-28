# Worktree Setup Config

Alera can run project-specific setup after it creates a linked workspace. The setup applies only to new Alera-created linked workspaces; it does not run for the main workspace, existing workspaces found during reconcile, or workspace removal.

## Precedence

Per-project settings saved in **Settings > Projects** are stored in the runtime profile and are the source of truth when present. Selecting **Use Repo File** removes that runtime override and makes Alera fall back to the repository file.

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

## Git hosting provider

The same config carries the project's git hosting provider, used by the Pull Requests panel to talk to `gh` (GitHub), `glab` (GitLab), or `az` (Azure DevOps). Authenticate first with the corresponding CLI. It can be set in **Settings > Projects** (UI override) or in `alera.toml`:

```toml
git_hosting_provider = "github" # or "gitlab" / "azureDevops"
```

When absent, Alera auto-detects GitHub.com, GitLab.com, and Azure DevOps from the repository's `origin` remote. Set the provider explicitly for self-hosted hosts. GitHub Enterprise Server uses the `github` provider and the hostname parsed from the remote; `githubEnterprise`, `github_enterprise`, and `github-enterprise` are accepted aliases. GitHub Enterprise Server is supported on standard HTTPS only because `gh` does not accept custom HTTPS ports for these operations. GitLab self-managed similarly uses `gitlab`, including instances exposed on custom HTTPS ports. The Azure aliases `azure`, `azure_devops`, and `azure-devops` are also accepted. Authentication is delegated entirely to the CLIs: use `gh auth login --hostname github.example.com` for GitHub Enterprise Server, `glab auth login --hostname gitlab.example.com` for GitLab self-managed, or the standard `gh auth login`, `glab auth login`, and `az login` commands for public hosts.

GitLab review pagination requires `glab` 1.80.0 or newer.

If a copy or setup action fails after the Git worktree is created, Alera keeps and opens the workspace, then surfaces a setup warning so the user can fix the workspace in place. The UI and `alera workspace add` both execute this setup through the runtime host.

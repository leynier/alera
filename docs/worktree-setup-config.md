# Worktree Setup Config

Alera can run project-specific setup after it creates a linked workspace. The setup applies only to new Alera-created linked workspaces; it does not run for the main workspace, existing workspaces found during reconcile, or workspace removal.

## Precedence

Per-project settings saved in **Settings > Projects** are stored in the runtime profile and are the source of truth when present. Selecting **Use Repo File** removes that runtime override and makes Alera fall back to the repository file.

When no UI override exists, Alera reads `alera.toml` from the project root. Missing `alera.toml` files mean no Alera-specific copy or setup actions. A `.worktreeinclude` file at the project root is still applied in that case, including when a UI override is present.

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

[new_workspace]
prompt_append = """
Follow the project's contributor instructions.
Run the focused tests before finishing.
"""
```

`copy` entries copy files or directories from the main project checkout into the new linked workspace. `to` defaults to `from`, and `overwrite` defaults to `false`.

`setup` commands run sequentially from the new linked workspace root. When they run inline (see below) they stop on the first non-zero exit code.

Paths in `alera.toml` are repo-relative literal paths. Absolute paths and `..` escapes are rejected. Globs and custom command environments are not part of the `copy` list.

## `.worktreeinclude`

Git worktrees only check out tracked files. A `.worktreeinclude` file at the repository root lists gitignored files that should be copied from the main checkout into each new linked workspace. The format is the same one Conductor and Claude Code read: [`.gitignore` pattern syntax](https://git-scm.com/docs/gitignore), including comments, root-anchored paths, nested globs, directory patterns, and negation with `!`.

```txt
.env.local
config/secrets.json
certs/local/**
```

Alera copies a matching path when all of these are true:

- the path exists in the main project checkout
- Git ignores it
- it is not already tracked

Tracked files are already present in the new worktree, so they are not copied. Untracked files that Git does not ignore are not eligible. The file contains patterns, not secret values, so it can usually be committed.

`.worktreeinclude` is additive with `worktree.copy`. Explicit copy rules still run first and win when they name the same source path (so a rule can remap `from` / `to` or set `overwrite`). There is no hidden default pattern: without this file and without copy rules, Alera copies nothing.

Use setup commands when the workspace needs to install dependencies, generate files, create symlinks, or fetch secrets. `.worktreeinclude` is for static gitignored files that already exist in the main checkout.

## New Workspace Prompt Append

`new_workspace.prompt_append` is optional project-specific text added last to the prompt before Alera starts the selected agent profile from the **New Workspace** flow. When the profile has a Custom Prompt, the delivered order is the user prompt, the profile prompt, then this project prompt, with blank lines between non-empty sections. Alera does not send this append text through AI Assist and does not use it to generate the workspace name or branch.

Like the worktree settings, this value can be stored in `alera.toml` or edited under **Settings > Projects**. A UI override replaces the complete repository `alera.toml` config for that project, including this value. It does not disable `.worktreeinclude`.

## Where the setup runs

The desktop and mobile apps do not hold the New Workspace UI open while the setup runs. They ask the runtime host to *prepare* the setup instead (`deferSetup`), so creation completes as soon as the Git worktree exists. Each app starts the returned command once in a terminal named **Setup** and detaches from it so the setup continues in the runtime host. On desktop, the workspace opens with its usual `Terminal 1` plus the **Setup** terminal where the work happens in view.

The Setup terminal runs a script the host generates. That script exists because the terminal hosts whatever interactive shell the user configured, and chaining with `&&` is not portable: PowerShell 5.1 rejects it at parse time and nushell removed it. Writing one command per line up front does not work either, since the later lines would be delivered to the standard input of the process the earlier line started. So the terminal runs a single portable line (`/bin/sh "<script>"`, or `cmd /d /c "<script>"` on Windows) and the script does the sequencing.

For the Setup tab, the runtime adds the shell-specific wrapper needed to replace or exit the interactive shell after that line finishes, so the PTY exit code reflects the script result.

Inside the Setup terminal:

- the copy actions run first, through `alera workspace setup --id <workspace> --copies-only`, so their symlink and path-escape validation stays in Rust. That includes explicit `worktree.copy` rules and gitignored matches from `.worktreeinclude`;
- every `setup` command then runs in order, each preceded by an echoed `> <command>` marker, and **a failing command does not stop the ones after it** - the output is right there to read;
- the script deletes itself when it finishes and preserves a non-zero result if any copy or setup action failed. A run interrupted before that leaves the script behind, and the host sweeps any leftovers the next time it starts;
- the host closes the **Setup** terminal after a successful run. If the run fails, the terminal remains open with its output so the problem can be inspected and rerun.

The command is delivered once. After it is on its way the host drops it from the tab record, so restarting the terminal, the app, or the host leaves a clean shell rather than reinstalling dependencies.

`alera workspace add` keeps running the setup inline and reporting it, because the CLI has no terminal tab to show it in. `alera workspace setup --id <workspace>` applies a project's setup to an existing workspace, with `--copies-only` for just the copy actions. An older runtime host that does not understand `deferSetup` ignores it and runs the setup inline, which is the behavior described in the rest of this page.

## Git hosting provider

The same config carries the project's git hosting provider, used by the Pull Requests panel to talk to `gh` (GitHub), `glab` (GitLab), or `az` (Azure DevOps). Authenticate first with the corresponding CLI. It can be set in **Settings > Projects** (UI override) or in `alera.toml`:

```toml
git_hosting_provider = "github" # or "gitlab" / "azureDevops"
```

When absent, Alera auto-detects GitHub.com, GitLab.com, and Azure DevOps from the repository's `origin` remote. Set the provider explicitly for self-hosted hosts. GitHub Enterprise Server uses the `github` provider and the hostname parsed from the remote; `githubEnterprise`, `github_enterprise`, and `github-enterprise` are accepted aliases. GitHub Enterprise Server is supported on standard HTTPS only because `gh` does not accept custom HTTPS ports for these operations. GitLab self-managed similarly uses `gitlab`, including instances exposed on custom HTTPS ports. The Azure aliases `azure`, `azure_devops`, and `azure-devops` are also accepted. Authentication is delegated entirely to the CLIs: use `gh auth login --hostname github.example.com` for GitHub Enterprise Server, `glab auth login --hostname gitlab.example.com` for GitLab self-managed, or the standard `gh auth login`, `glab auth login`, and `az login` commands for public hosts.

GitHub native pull request stack mutations require the official `github/gh-stack` extension. Install it with `gh extension install github/gh-stack`. Alera can build a stack from ordered workspaces by reusing open pull requests and creating the missing ones with chained base branches. It reads stack state through the GitHub API and uses the extension only to link or atomically merge pull requests; it does not delegate branch checkout, rebase, or synchronization to the extension because Alera owns the worktrees.

GitLab review pagination requires `glab` 1.80.0 or newer.

If a copy or setup action fails after the Git worktree is created, Alera keeps and opens the workspace. When the setup ran inline, a setup warning is surfaced so the user can fix the workspace in place; when it ran in the Setup terminal, the terminal itself is the report. An invalid `alera.toml` or `.worktreeinclude` is surfaced as a warning either way. The UI and `alera workspace add` both execute this setup through the runtime host.

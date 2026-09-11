---
name: alera-cli
description: Operate Alera workspaces and runtime resources through the alera CLI.
---

# Alera CLI

Use the managed `alera` CLI for Alera resources. Inside Alera terminals, its shim and `ALERA_RUNTIME_DIR` select the UI's runtime profile. Use command-group `--help` for flags and `--json` for structured output; list envelopes use `items`.

## Choose The Relevant Workflow

- Projects, worktrees, hand-off/hand-on, tags, tabs, and relations: read [workspaces](references/workspaces.md).
- SSH targets and remote workspace setup: read [hosts](references/hosts.md).
- Automation definitions, approvals, and execution: read [automations](references/automations.md).
- Missing runtime host, external-shell configuration, or metadata repair: read [recovery](references/recovery.md).
- Agent Profile inspection, launch, or maintenance: use the `alera-agent-profiles` skill. Its simple-maintenance route does not require catalog research.
- Agent dispatch, worker tasks, or coordinator lifecycle: use the `alera-orchestration` skill.

Load only the workflow needed for the current request.

## Workspace Invariants

Use `workspace add/remove` for real managed worktrees. Use `register/unregister` only for intentional metadata repair; `register --host-id` does not create a remote worktree. SSH bootstrap installs only the sidecar; `workspace add --host-id` creates the remote worktree.

Do not use raw `git worktree add/remove` or edit runtime metadata unless the user requests low-level recovery. Inspect exact IDs and state before destructive operations. Keep user-created branches unless deletion is explicitly requested; default removal deletes only branches Alera created. Use `workspace pin/unpin` for sidebar placement.

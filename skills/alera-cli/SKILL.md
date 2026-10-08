---
name: alera-cli
description: Operate Alera workspaces and runtime resources through the alera CLI.
---

# Alera CLI

Use the managed `alera` CLI for Alera resources. Inside Alera terminals, its shim and `ALERA_RUNTIME_DIR` select the UI's runtime profile. Use command-group `--help` for flags and `--json` for structured output; list envelopes use `items`.

## Choose The Relevant Workflow

- Projects, worktrees, hand-off/hand-on, linked issues, Watch and Fix, tags, tabs, relations, and sections: read [workspaces](references/workspaces.md).
- SSH targets and remote workspace setup: read [hosts](references/hosts.md).
- Scheduled agent work: use the `alera-automations` skill; CLI entry points are in [automations](references/automations.md).
- Missing runtime host, external-shell configuration, metadata repair, or a tab that stopped showing its agent's status: read [recovery](references/recovery.md).
- Agent Profile inspection, launch, or maintenance: use the `alera-agent-profiles` skill. Its simple-maintenance route does not require catalog research.
- Asking a running agent a question from outside its terminal, or reading an inbox: read [inbox](references/inbox.md).
- Agent dispatch, worker tasks, or coordinator lifecycle: use the `alera-orchestration` skill.
- Signing the runtime in to an Alera account, naming it, or letting MCP clients drive it (MCP Control, `alera mcp serve`): read [mcp](references/mcp.md).

Load only the workflow needed for the current request.

## Workspace Invariants

Use `workspace add/remove` for real managed worktrees. Use `register/unregister` only for intentional metadata repair; `register --host-id` does not create a remote worktree. SSH bootstrap installs only the sidecar; `workspace add --host-id` creates the remote worktree.

Do not use raw `git worktree add/remove` or edit runtime metadata unless the user requests low-level recovery. Inspect exact IDs and state before destructive operations. Keep user-created branches unless deletion is explicitly requested; default removal deletes only branches Alera created. Use `workspace rename` to change a workspace's display name; it never renames the branch or worktree folder. Use `workspace focus` to select and show an existing workspace in the running desktop app; it fails instead of starting Alera. Use `workspace pin/unpin` for sidebar placement. Use `workspace section` to assign sidebar sections; do not edit `runtime.sqlite` to assign sections.

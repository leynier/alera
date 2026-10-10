---
name: alera-mcp
description: Work with Alera through this MCP server. Covers runtimes, projects, workspaces, agents and terminals, inbox questions, pull requests, events, and runtime settings. Read it before the first Alera task of a conversation.
metadata:
  version: 1
---

# Alera Through MCP

Alera runs coding agents in workspaces on the user's machines. A workspace is a task with its own Git worktree and branch, or a task on the project folder itself. Each machine is a runtime. This server reaches the runtimes the user granted to this connection.

## How Calls Work

- Call `list_runtimes` first. Every other Alera tool takes an optional `runtime` (name or id). Pass it whenever more than one runtime is online. Nothing is remembered between calls, so name the runtime on each call.
- Use exact ids from the list and show tools. Never guess an id, a branch, or a profile name.
- Access has three levels: read, full, and admin. A tool outside the connection's grant fails with `insufficient_scope`. Tell the user to reconnect Alera and allow that level; do not look for another tool that does the same thing.
- Waits return after at most 50 seconds. Call the wait again while the work is still running, and pass the returned cursor so nothing is read twice.
- Tools that change state and accept `clientRequestId` deduplicate retries. After a timeout or an unclear answer, retry with the same `clientRequestId` instead of a new one, so the action does not happen twice.
- A failed tool returns `structuredContent.error` with `code` and `retryable`. Codes include `not_found`, `invalid_argument`, `conflict`, `blocked` (the app refused, as it would in its own UI), `capability_missing` (the runtime needs an Alera update), `provider_unavailable` (`gh`, `glab`, or `az` is missing or signed out on that machine), `timeout_pending` (still running; read its state again), and `runtime_unavailable`. Retry only when `retryable` is true.
- Errors from this server itself start with `runtime_offline:`, `timeout:`, or `insufficient_scope:`. A `runtime_offline` runtime is not running or has MCP Control off; only the user can fix that.

## Authorization

Do only what the user asked for. Before removing anything, run the matching preview (`preview_workspace_removal`, `preview_project_removal`, `preview_agent_profile_removal`) and report what it would affect. Merging, closing, and removing are the user's decisions; honor an explicit request for the same scope without asking again, but never infer one.

## Choose The Workflow

- Projects, workspaces, New Workspace from Prompt, sections, tags, hosts, issues, and relocation: read [workspaces](references/workspaces.md).
- Launching agents, tabs, terminals, and asking an agent a question: read [agents](references/agents.md).
- Pull requests on GitHub, GitLab, and Azure DevOps, Ship, and Watch and Fix: read [pull requests](references/pull-requests.md).
- Following what happens without polling each item, and webhooks: read [events](references/events.md).
- Runtime status, settings, quotas, voice, status hooks, and the agents' Alera skills: read [runtime](references/runtime.md).
- Delegating tasks to agents, coordinator runs, and workflow recipes: use the `alera-mcp-orchestration` skill.
- Scheduled or recurring agent work: use the `alera-mcp-automations` skill.
- Creating or changing agent profiles: use the `alera-mcp-agent-profiles` skill.

Read only the references the task needs. Read them with `read_skill`, passing the reference path as `file`.

## Starting Work

For a task described in words, prefer `start_workspace_from_prompt`. It finds the project, names the workspace and branch, and launches the default agent, like the app's New Workspace from Prompt. Use `start_agent_workspace` when you already know the project, profile, and branch. Use `launch_agent` to add an agent to an existing workspace, and `delegate_task` when a running coordinator agent should own the result.

Then follow the agent with `wait_for_events`, `read_terminal`, or `ask_agent` with `wait_for_reply`. An agent only sees what is typed into its terminal or asked through the inbox; it cannot see this conversation.

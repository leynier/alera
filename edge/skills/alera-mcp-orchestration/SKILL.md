---
name: alera-mcp-orchestration
description: Delegate tasks to Alera agents and start, follow, and steer runs, their gates, and run recipes through this MCP server. Use when work should be split among agents or tracked as a run.
metadata:
  version: 4
---

# Alera Orchestration Through MCP

A run groups a plan, its tasks, gates, a timeline, and the worktrees it keeps. A coordinator agent plans it and workers carry it out; the runtime owns the lifecycle. Workers need no acceptance or heartbeat: the runtime sees them start and stall on its own. As an MCP client you are not a coordinator terminal, so the tools that cancel or interrupt a task run as audited administrative actions. Pass a clear `reason` to them.

Live agent chats use a separate credential-bound catalog injected into their provider sessions. Read [chat orchestration](references/chats.md) when working inside such a chat or explaining that boundary. Those tools are absent from this cloud connection and an ordinary local server.

## Pick The Simplest Tool

- One agent working on one request: use `start_workspace_from_prompt`, `start_agent_workspace`, or `launch_agent` from the `alera-mcp` skill. No task is needed.
- A coordinator agent is already running and should own the result: use `delegate_task`. It creates the task and starts a profile on it, in the coordinator's workspace, in a new child worktree with `newWorkspace`, or in an agent terminal that is already running with `terminal`. Find the coordinator's handle with `list_terminals`. Follow the task with `wait_for_task` or `wait_for_events`.
- A planned, multi-step run that a coordinator agent plans for you: read [runs](references/runs.md).

A failed delegation can still leave a created workspace and task. Keep the returned ids. Inspect them with `show_task` and `show_dispatch`, and retry only after confirming no worker is still running it. Do not repeat `delegate_task` blindly, and do not remove the workspace on your own.

## Tasks And Dispatches

- `show_task` reads a task with its active dispatch; `inspect_task` reads a task of a run with its result and history. `wait_for_task` waits until a task reaches the given states.
- `delegate_task` takes `runId` to add the task to a run the coordinator owns, `stage` to bind it to a stage of that run's plan, and `dependsOn` for tasks it waits for.
- `show_dispatch` shows the dispatch state and preamble. `interrupt_dispatch` interrupts a worker's current turn without closing its terminal.
- `cancel_task` cancels a task and its not-yet-started descendants.

## Gates And Messages

- `create_gate` asks a person to decide before a task continues. Read gates with `list_run_gates` and `show_run_gate`; see [runs](references/runs.md) for resolving them.
- `send_message` sends an orchestration message from one agent terminal to another terminal or a group such as `@all`. `delivery` `now` pastes it into a working agent that queues input mid-turn; the default waits for its turn to end. To ask an agent a question from outside, use `ask_agent` instead. `list_messages` lists recent messages.

## Recovery

These need administrative access, a reason, and the user's request:
- `recover_task` moves a stalled task to ready, failed, or cancelled.
- `transfer_coordinator` hands a task or a whole run to another coordinator terminal.
- `reset_orchestration` clears orchestration state.

A stalled task keeps its slot and is never redispatched silently; output from its worker revives it. Inspect it with `inspect_task` and `read_terminal` before recovering it.

---
name: alera-mcp-orchestration
description: Delegate tasks to Alera agents and follow coordinator runs, gates, and workflow recipes through this MCP server. Use when work should be split among agents or tracked as orchestration tasks.
metadata:
  version: 1
---

# Alera Orchestration Through MCP

Orchestration tracks work as tasks owned by a coordinator, which is a running agent terminal. Workers accept tasks, report progress, and complete them. The runtime owns the lifecycle. As an MCP client you are not a coordinator terminal, so the tools that stop, cancel, or interrupt work run as audited administrative actions. Pass a clear `reason` to them.

## Pick The Simplest Tool

- One agent working on one request: use `start_workspace_from_prompt`, `start_agent_workspace`, or `launch_agent` from the `alera-mcp` skill. No task is needed.
- A coordinator agent is already running and should own the result: use `delegate_task`. It creates the task and starts a profile that accepts it, in the coordinator's workspace or, with `newWorkspace`, in a new child worktree. Find the coordinator's handle with `list_terminals`. Follow the task with `wait_for_task` or `wait_for_events`.
- A planned, multi-stage run reviewed by a person: read [workflows](references/workflows.md).

A failed delegation can still leave a created workspace and task. Keep the returned ids. Inspect them with `show_task` and `show_dispatch`, and retry the existing task only after confirming no worker is still running it. Do not repeat `delegate_task` blindly, and do not remove the workspace on your own.

## Tasks And Dispatches

- `list_tasks` and `show_task` read tasks. `wait_for_task` waits until a task reaches the given states.
- `create_task` creates a task without starting an agent. A task of a coordinator run names the run and, with an execution policy, its stage.
- `spawn_agent` starts an agent for a ready task and dispatches it once the agent is ready. `dispatch_task` dispatches a ready task to an existing terminal; `dryRun` only builds the preamble.
- `show_dispatch` shows the dispatch state and preamble. `interrupt_dispatch` interrupts a worker's current turn without closing its terminal.
- `cancel_task` cancels a task and its not-yet-started descendants.

## Coordinator Runs

- `start_coordinator` starts the background loop for a running coordinator agent. It records the objective and dispatches the run's ready tasks. `stop_coordinator` stops it, and `cancelActive` also cancels active tasks.
- `list_runs`, `show_run`, and `orchestration_status` read runs. `get_orchestration_board` pages the run board grouped as attention, active, or history. `get_run_snapshot` reads a run with a page of its tasks, and `inspect_task` reads one task with its dispatches and history.
- `propose_run_policy` proposes a stage plan. The run holds scheduling until a person approves it in the Alera app. `show_run_policy` shows it. Never treat a pending policy as approved.

## Gates And Messages

- `create_gate` asks a person to decide before a task continues. `list_gates` lists gates. Gates are resolved by a person in the Alera app; never decide one for the user.
- `send_message` sends an orchestration message from one agent terminal to another terminal or a group such as `@all`. To ask an agent a question from outside, use `ask_agent` instead. `list_messages` lists recent messages.

## Recovery

These need administrative access, a reason, and the user's request:
- `recover_task` moves a stalled task to ready, failed, or cancelled.
- `transfer_coordinator` hands a task or a whole run to another coordinator terminal.
- `reset_orchestration` clears orchestration state.

A stalled task keeps its slot and is never redispatched silently. Inspect it with `inspect_task` and `read_terminal` before recovering it.

---
name: alera-orchestration
description: Use when coordinating multiple coding agents through Alera's orchestration system — inter-agent messaging, task DAGs with dependencies, dispatching work to worker agents, decision gates, or acting as a coordinator. For basic workspace and tab management, use the alera-cli skill instead.
---

# Alera Inter-Agent Orchestration

Use this skill when the task involves coordinating multiple coding agents through Alera's orchestration system.

## When To Use

- You need to send messages between agent terminals
- You need to decompose a spec into parallel subtasks with dependencies
- You need to dispatch tasks to worker agents with structured feedback
- You need to act as a coordinator managing a multi-agent workflow
- You need decision gates for human-in-the-loop checkpoints

## Preconditions

- The `alera` CLI must be on PATH (Alera-managed terminals get it automatically).
- All `alera orchestration` commands talk to the Alera runtime-host. If none is running, the CLI starts one automatically.
- Push-on-idle message delivery and @agent groups require the Alera app to be running with agent status hooks enabled (the app forwards agent presence to the runtime-host). Messaging, tasks, dispatch bookkeeping, and gates work without the app.
- Your own terminal handle is injected as `ALERA_TERMINAL_HANDLE` into every Alera-managed terminal. Omit `--from`/`--terminal` and the CLI resolves it from that variable.

## Command Surface

### Messaging

Inter-agent messaging via a persistent SQLite-backed mail store. Messages are delivered automatically into a recipient terminal when its agent goes idle (push-on-idle).

```bash
alera orchestration send --to <handle|@group> --subject <text> [--from <handle>] [--body <text>] [--type <type>] [--priority <level>] [--thread-id <id>] [--payload <json>]
alera orchestration check [--terminal <handle>] [--all] [--types <type,...>] [--inject] [--wait] [--timeout-ms <n>]
alera orchestration reply --id <msg_id> --body <text>
alera orchestration inbox [--terminal <handle>] [--limit <n>]
alera orchestration ask --to <handle> --question <text> [--options <csv>] [--timeout-ms <n>]
```

Why: `--wait` blocks until a matching message arrives or the timeout expires (default 2 minutes). This replaces sleep+poll loops. If unread messages already exist, it returns immediately. Combine with `--types` to wait for specific message types (e.g. `--wait --types worker_done --timeout-ms 300000`).

Why: `--inject` returns messages formatted as readable banners with priority indicators (`[HIGH]`, `[URGENT]`). Default output without `--json` shows the same banners.

Why: on Windows PowerShell, raw JSON in `--payload` is fragile. Prefer the structured flags: `--task-id`, `--dispatch-id`, `--files-modified <csv>`, `--report-path <path>`, `--phase <text>` — the CLI assembles the JSON payload.

**Message types**: `status` (general), `dispatch` (assign work), `worker_done` (signal completion), `merge_ready` (branch ready for merge), `escalation` (issue requiring attention), `handoff` (pass work to another agent), `decision_gate` (human-in-the-loop), `heartbeat` (liveness).

**Priority levels**: `normal`, `high`, `urgent`.

**Group addresses** resolve to terminal handles at send time (one message per recipient, shared thread):

| Group | Resolves To |
|-------|------------|
| `@all` | All live terminal handles except sender |
| `@idle` | Handles whose agent has reported `done` and can safely receive auto-submitted input |
| `@claude` / `@codex` / `@copilot` / `@cursor` / `@agy` / `@opencode` / `@pi` / `@amp` | Handles running that agent (via agent status hooks) |
| `@workspace:<id>` | All handles in a specific workspace |

Lifecycle messages (`worker_done`, `heartbeat`) cannot be sent to a group address.

### Tasks

Task tracking with DAG dependencies. A task becomes `ready` when all tasks in its `deps` array are `completed`; if any dependency fails, pending dependents fail instead of staying stuck.

```bash
alera orchestration task-create --spec <text> [--task-title <text>] [--deps <json_array>] [--parent <task_id>]
alera orchestration task-list [--status <status>] [--ready]
alera orchestration task-update --id <task_id> --status <status> [--result <json>]
```

**Task statuses**: `pending` (waiting on deps), `ready` (deps met, dispatchable), `dispatched` (assigned to a terminal), `completed`, `failed`, `blocked` (waiting on a decision gate).

Why: when a task is marked `completed`, the runtime automatically promotes any pending tasks whose deps are now all satisfied to `ready`. When a dependency is marked `failed`, pending dependents are marked `failed`. This is the DAG resolution step.

### Dispatch

Dispatch assigns a ready task to a terminal, optionally injecting the task spec + preamble so the agent knows how to report back.

```bash
alera orchestration dispatch --task <task_id> --to <handle> [--from <handle>] [--inject] [--dry-run] [--return-preamble]
alera orchestration dispatch-show --task <task_id>
```

Why: `--inject` writes a preamble that teaches the agent to report `worker_done` (with taskId + dispatchId), send heartbeats every 5 minutes, and use `ask` instead of AskUserQuestion. It requires a recognized agent running in the target terminal; for a bare shell, use `--dry-run` and paste the preamble manually.

Why: dispatch contexts are separate from tasks. A task can be dispatched, fail, and be re-dispatched — the task stays clean while dispatch contexts track retry state, and the failure count carries across retries.

**Circuit breaker**: after 3 accumulated failures on a task, the dispatch context is marked `circuit_broken` and the task is marked `failed`, preventing infinite retry loops. Below the threshold a failed dispatch returns the task to `ready`.

### Decision Gates

Human-in-the-loop decision points that block a task until resolved.

```bash
alera orchestration gate-create --task <task_id> --question <text> [--options <json_array>]
alera orchestration gate-resolve --id <gate_id> --resolution <text>
alera orchestration gate-list [--task <task_id>] [--status <status>]
```

Why: creating a gate is accepted for `ready` or `dispatched` tasks, blocks the task, and completes any active dispatch (releasing the worker). Resolving a gate sets the task back to `ready` with the resolution included in the next dispatch preamble as a `DECISION GATE RESOLVED` section.

**Gate statuses**: `pending`, `resolved`, `timeout`.

### Coordinator

Start an automated coordinator loop that dispatches ready tasks, processes `worker_done`/`escalation` messages, and advances the task DAG.

```bash
alera orchestration run --spec <text> [--from <handle>] [--poll-interval-ms <n>] [--max-concurrent <n>] [--workspace <workspace_id>]
alera orchestration run-stop
```

Why: `run` returns immediately with a run id; the loop runs in the background inside the runtime-host. Query progress via `alera orchestration task-list`. Only one coordinator can run at a time. Tasks must be pre-created — decomposition is your responsibility as the coordinating agent.

Why: `--workspace` scopes which terminals receive dispatches, enables the stale-base drift check (worktrees more than 20 commits behind their base are skipped unless the spec contains `allow-stale-base: true` on its own line), and lets the coordinator create worker terminal tabs when no idle worker exists (requires the app to be running).

Coordinator worker selection only uses injection-ready agents that can auto-submit injected preambles. Cursor-style editable-prompt agents are visible in `terminal-list` and can receive manual `dispatch --inject`, but `run` skips them for unattended dispatch.

### Terminals

```bash
alera orchestration terminal-list
alera tab create --workspace-id <id> --title <text> --command "claude" --spawn
```

Why: `terminal-list` shows live terminal handles with workspace, agent type, and agent state — the coordinator's worker inventory. `tab create --command "claude" --spawn` creates a terminal tab that the app starts eagerly (even while invisible) and runs the agent CLI in it. After creating one, wait for its presence to appear in `terminal-list` before dispatching.

### Lifecycle

```bash
alera orchestration reset [--all] [--tasks] [--messages]
```

Why: `--all` is the default when no scope flag is provided. `--tasks` clears tasks, dispatch contexts, decision gates, and coordinator runs but preserves messages.

## Agent Guidance

- When dispatched with a preamble, **always send `worker_done` when done** — exactly once, with both `--task-id` and `--dispatch-id`. Failure is still a `worker_done` with a subject like "Failed: <reason>"; never silently exit.
- If blocked, send an `escalation` to the coordinator instead of stalling, including both `--task-id` and `--dispatch-id` when you were dispatched with a preamble. For questions, use `alera orchestration ask` — never AskUserQuestion, which the coordinator cannot see or answer.
- Send a `heartbeat` every 5 minutes while actively working (skip while blocked inside `check --wait` or `ask` — those calls are themselves liveness signals). The coordinator warns about dispatches with no heartbeat for 10 minutes.
- Use `alera orchestration check` to read incoming messages. They are also delivered automatically into your prompt when you go idle.
- The coordinator uses `task-list --ready` as its external memory. Prefer querying orchestration state over tracking it in your context window.
- When acting as coordinator: discover workers with `terminal-list`, create tasks with `task-create`, dispatch with `dispatch --inject`, and block on `check --wait --types worker_done,escalation --timeout-ms 300000` instead of sleep+poll loops.
- `check --wait` returns the currently unread batch. If N workers finish near-simultaneously, loop on `check --wait` until all results are collected; after each return, mark progress and dispatch the next wave.
- After receiving `worker_done` from a terminal, that terminal is idle — dispatch the next task to it immediately.
- Keep dependency chains to 3-4 steps maximum. Prefer parallel waves of independent tasks over deep sequential chains.
- Insert decision gates between phases for human oversight of risky operations.
- Terminal handles equal the PTY session id and survive host restarts only while the session lives. Re-acquire handles with `terminal-list` if in doubt.

## Coordinator Worked Example

```bash
# 1. Create a worker terminal running Claude Code (the app spawns it eagerly)
alera tab --json create --workspace-id ws_123 --title "Worker 1" --command "claude" --spawn
# → payload.terminalSessionId is the worker's future handle

# 2. Wait for the agent to boot: poll terminal-list until agentState appears
alera orchestration --json terminal-list

# 3. Create and dispatch a task with preamble injection
alera orchestration --json task-create --spec "Fix the login button CSS"
# → id: task_...
alera orchestration --json dispatch --task task_... --to <handle> --inject

# 4. Block until the worker reports back (no sleep loops needed)
alera orchestration --json check --wait --types worker_done,escalation --timeout-ms 300000

# 5. On timeout with no messages, inspect state
alera orchestration --json task-list
alera orchestration --json dispatch-show --task task_...
```

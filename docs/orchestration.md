# Inter-Agent Orchestration

Alera orchestration is owned by the Rust runtime-host. Tasks, dispatches, messages, decision gates, coordinator runs, and administrative audit events are persisted in the runtime SQLite database; all mutations pass through the authenticated host actor.

## Contract Versions

- Terminal-host protocol: 4.
- Orchestration protocol: 2.
- Dispatch preamble: 2.
- Installed skill contract: 2.

`alera version --json` reports the CLI build and expected contracts, then queries an already-running compatible runtime host for its actual build and contract versions. Host fields are `null` and `runtimeHostAvailable` is `false` when no compatible host is reachable; the command never invents host equality from the CLI build.

The v2 schema is incompatible at the SQL constraint level, so the runtime performs a transactional table rebuild that preserves v1 messages, tasks, dispatches, gates, and runs while filling new ownership and scope fields with conservative defaults. Unknown future schema versions fail closed instead of deleting state.

## Runs And Ownership

Runs and tasks carry `workspaceId`, `runId`, `coordinatorHandle`, and `assigneeHandle`. Multiple workspaces can coordinate concurrently, but a workspace can have at most one active run. A coordinated run adopts ready/manual tasks in its workspace that belong to its coordinator. Creating a task for an existing run requires the same workspace and coordinator; injected dispatches likewise require the target terminal to belong to the task workspace.

Coordinator authority resolves from the run or task, never from whichever terminal calls dispatch. `dispatch` rejects `from == to` unless `--allow-self-dispatch` is present. Stopping runs, interrupting dispatches, recovering tasks, cancellation, and ownership transfer require the current coordinator or an audited `--force --reason` action. A task attached to a run cannot transfer independently; transfer the run so its durable tasks, active dispatches, and in-memory coordinator remain aligned.

```bash
alera orchestration task-create --workspace <workspace-id> --spec "Review tests"
alera orchestration run --workspace <workspace-id> --agent codex --spec "Audit the repository"
alera orchestration run-list --workspace <workspace-id>
alera orchestration run-show --id <run-id>
alera orchestration run-stop --id <run-id> [--cancel-active] --reason "Stopped by coordinator"
```

`run-stop` is graceful by default: it stops new scheduling while active workers retain authority to finish and persists the supplied reason on the run. `--cancel-active` applies cooperative cancellation to active tasks. Only the owning coordinator can stop the run normally; `--force` is reserved for audited administrative recovery, and forced child cancellations retain the administrative actor in their audit records.

## Agent Spawn And Readiness

`agent-spawn` creates or selects a terminal, launches the requested agent, waits for hook-based readiness, injects the v2 preamble, forces submission through the agent adapter, and waits for acceptance.

```bash
alera orchestration agent-spawn --workspace <workspace-id> --agent codex --task <task-id> --title "Review Tests"
alera orchestration terminal-wait --terminal <handle> --for agent-ready --timeout-ms 30000
alera orchestration terminal-wait --terminal <handle> --for dispatch-accepted --timeout-ms 60000
```

The built-in registry supports `codex`, `claude`, `copilot`, `cursor`, `agy`, `opencode`, `pi`, and `amp`, with default commands `codex`, `claude`, `copilot`, `cursor-agent`, `agy`, `opencode`, `pi`, and `amp`. `agent-spawn --command` overrides the default without changing the agent type.

Startup states distinguish process creation, agent detection, agent readiness, submitted-but-unconfirmed dispatch, acceptance, failure, and stall. An unaccepted coordinator dispatch expires after the same 90-second deadline used by `agent-spawn`; three startup/acceptance failures stall the task without consuming the execution circuit breaker. Wait commands return startup failures immediately as non-zero errors instead of reporting a normal timeout.

## Worker Context And Lifecycle

The primary worker commands infer task, dispatch, coordinator, and assignee from the active terminal context:

```bash
alera orchestration dispatch-accept
alera orchestration --json context
alera orchestration heartbeat --phase reviewing
alera orchestration escalate --subject "Blocked" --body "Missing credentials"
alera orchestration complete --summary "Review complete" --completion-kind success --artifacts '[]' --files-modified "path/a" --validation '[]'
```

Completion validates structured results and atomically commits task/dispatch state, promotes DAG dependants, invalidates scoped operational messages, and returns lifecycle reconciliation in one response. A completed dispatch is accepted idempotently only when its task is also completed; dispatches closed by a decision gate reject late completion. `worker-done --task --dispatch --summary` is the explicit idempotent recovery form. Generic `send --type worker_done` and arbitrary `task-update --status` are rejected.

The only supported completion acknowledgement policy is currently `return-immediately`. The host rejects `wait-for-ack` and `keep-agent-idle` until those policies have distinct runtime state and acknowledgement semantics; terminal reuse remains independently controlled by `--terminal-policy`. `close-on-success` terminates the PTY, removes its persisted worker tab, and notifies connected clients.

Required result fields are `summary`, `completionKind`, `artifacts`, `filesModified`, and `validation`. A task can additionally carry a result schema; pass schema-specific properties as a JSON object with `complete --result-extra '{"ticket":42}'` or `worker-done --result-extra ...`. Reports belong in `artifacts`; only workspace source changes belong in `filesModified`.

Cancellation atomically marks the task and dispatch `cancelled`, closes pending decision gates, obsoletes pending operational messages, queues an urgent cooperative cancellation, and cancels unstarted DAG descendants. Completed or failed tasks reject late cancellation so successful descendants are not invalidated; repeated cancellation of an already-cancelled task is idempotent. Only the owning coordinator can cancel normally; `task-cancel --force` is the audited administrative recovery path. Dispatch interruption has the same ownership rule and requires `dispatch-interrupt --force` for administrative recovery. Use an explicit terminal/dispatch interrupt or termination only when cooperative cancellation does not stop the worker.

## Liveness And Messages

Runtime activity combines agent hooks, PTY output, and context-aware worker commands into dispatch and run-level `lastActivityAt`. The default accepted-dispatch lease is ten minutes. Expiry marks the task and dispatch `stalled`; stalled work continues occupying a concurrency slot because the worker may still be active, and Alera does not automatically redispatch potentially duplicated work. Recover with:

```bash
alera orchestration task-recover --id <task-id> --status ready --reason "Worker inspected and stopped"
```

Operational messages carry task/dispatch/run/workspace scope and may expire. Completing, failing, cancelling, or superseding a dispatch marks its queued operational messages obsolete. Inbox and outbox responses refresh and expose queued, delivered, read, expired, and obsolete state.

Message admission is bounded at the storage boundary: handles and thread IDs are limited to 512 UTF-8 bytes, subjects to 256 bytes, lifecycle bodies to 8 KiB, and general bodies and serialized payloads to 64 KiB. Prompt injection truncates each body to 4 KiB and a complete batch to 16 KiB; omitted content remains available through `alera orchestration inbox`.

PTY input and durable output use bounded asynchronous queues. A blocked terminal writer cannot stall the host actor or unrelated terminals, and delivery is acknowledged only after the queued paste and optional submit complete. Absolute output cursors remain monotonic when retained scrollback is trimmed and when an exited session is reminted.

Wait commands return exit 0 for normal timeouts with `{ "outcome": "timeout", "items": [], "waitedMs": ... }`. Usage, transport, and runtime failures remain non-zero errors.

## Observability And Terminal Diagnostics

```bash
alera orchestration status --id <run-id>
alera orchestration task-show --id <task-id>
alera orchestration terminal-show --handle <handle>
alera terminal read --handle <handle> --max-bytes 65536
alera terminal read --handle <handle> --cursor <nextCursor>
alera terminal write --handle <handle> --text "continue" --enter
alera terminal write --handle <handle> --stdin --enter
```

Terminal reads return raw retained bytes, lossy text, an absolute monotonic stream cursor, the current retained `baseCursor`, and a 64 KiB default limit. If a requested cursor predates retained scrollback, reading resumes at `baseCursor` with `truncated: true`. Reads do not apply heuristic secret redaction because that could hide authentication or trust prompts.

All CLI list commands use the collection envelope `{ "kind": "...", "items": [...], "filters": {...} }`. Orchestration responses retain semantic aliases during the protocol transition.

`workspace add --parent-workspace-id <id>` creates and links a child workspace atomically.

## Validation

- `cargo test -p alera-core --features runtime` covers store, DAG, ownership, startup budget, cancellation, leases, and run isolation.
- `cargo test -p alera-cli` covers CLI/RPC contracts, real PTY behavior, wait outcomes, delivery, adapters, and regression scenarios.
- Adapter command construction is deterministic across supported platforms. Codex and Claude are the required live smoke targets when their executables are available.

The agent-facing command guide is `skills/alera-orchestration/SKILL.md`.

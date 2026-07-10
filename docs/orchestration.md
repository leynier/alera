# Inter-Agent Orchestration

Alera's orchestration system lets multiple coding agents coordinate through structured messaging, a task DAG, dispatch with retry tracking, decision gates, and an automated coordinator loop. The design ports the semantics of Orca's orchestration system (see `reference_projects/orca`) into Alera's Rust sidecar architecture.

## Architecture

The engine lives in the **runtime-host sidecar** (`rust/alera-cli`, binary `alera`), not in the Flutter app:

- **State** is persisted in the existing `RuntimeStore` SQLite database (`rust/alera-core/src/runtime/`): five tables — `orchestrationMessages`, `orchestrationTasks`, `orchestrationDispatchContexts`, `orchestrationDecisionGates`, `orchestrationCoordinatorRuns` — created by the same migration pass as the rest of the runtime schema.
- **Verbs** are `alera orchestration ...` CLI subcommands (`rust/alera-cli/src/cli_orchestration.rs`) that RPC into the running runtime-host over the existing socket protocol. There is no direct-store fallback: waiters, agent presence, and the coordinator are in-process host state, so a live host is required (the CLI auto-starts one).
- **Engine modules** live under `rust/alera-cli/src/terminal_host/orchestration/` (formatter, preamble, lifecycle reconciliation, group resolution, agent presence, waiter registry, coordinator ticker) with request handlers in `terminal_host/server/orchestration_requests.rs` and `terminal_host/server/coordinator_requests.rs`. All state mutation runs inside the single `ServerActor`.
- The host advertises the additive `orchestration` runtime capability. Protocol version stays at 3; older hosts remain usable for non-orchestration verbs.

## Identity

Each PTY session's handle is its session id, injected into the terminal environment as `ALERA_TERMINAL_HANDLE` at spawn (`terminal_host/session.rs`). This is the same id the app uses to key agent status entries, so no mapping table is needed. CLI verbs resolve `--from`/`--terminal` from that variable when omitted.

### Handle lifecycle and remint

- The handle equals the tab's `terminalSessionId` (payload) for the life of the tab record.
- When a PTY exits and the app calls `createOrAttach` again for the same session id, the host **remints** a new process under that same id while seeding its checkpoint with the previous scrollback. Orchestration dispatch targets and visible terminal history stay stable across remint.
- `dispatch --inject` against a missing or non-running session fails with a `stale_terminal_handle:` error. Reopen the tab (or pick a live handle from `terminal-list`) before retrying inject.
- After remint, agent presence starts empty until hooks report again; wait for `terminal-list` to show an idle agent before re-dispatching.

## Idle Detection and Push-On-Idle

The Flutter app detects agent state via agent-status hooks (working / waiting / blocked / done). A keepAlive forwarder (`lib/src/features/agent_status/application/agent_status_host_forwarder.dart`) diffs transitions and batches them to the host via the `orchestration.agentStatus` request.

The host keeps an agent presence registry per handle. State mapping:

- `done` → injection-ready: pending messages are formatted as banners and written into the PTY, followed 500 ms later by a separate Enter (Claude Code treats a large write as a paste and swallows an inline `\r`). Cursor-type agents get no auto-Enter — injected text stays as editable prompt input.
- `working` / `waiting` / `blocked` → busy. `waiting` can mean an approval or user-input prompt, so auto-injection waits until the agent reports `done`.
- removed → presence cleared; messages stay queued for explicit `check` or the next injection-ready transition.

Messages track `read` (consumed by `check`) and `delivered_at` (auto-injected) independently, so push-on-idle delivers at most once while `check` still sees delivered-but-unread messages. `delivered_at` is stamped only after the deferred Enter succeeds; failures leave the batch queued for the next idle transition. Push-on-idle never targets the active coordinator handle; coordinators use `check --wait --types worker_done,escalation,decision_gate` plus host lifecycle reconciliation, with `decision_gate` keeping taskless `ask` questions visible. Inject payloads use bracketed paste + deferred Enter so multiline preambles do not corrupt the shell.

Without the app running, push-on-idle and `@agent`/`@idle` groups degrade gracefully: messages queue and remain readable via `check`.

## Key Invariants (ported from Orca)

1. A task without deps starts `ready`; a task with deps starts `ready` only when all existing deps are already completed, `failed` when any dep has failed, and otherwise `pending`.
2. Completing or failing a task refreshes pending dependents in the same transaction (`update_orchestration_task_status`): completed deps promote children to `ready`; failed deps fail children instead of stranding them.
3. One active dispatch per terminal.
4. `failure_count` carries forward across a task's dispatch retries; at 3 failures the dispatch is `circuit_broken` and the task `failed`; below the threshold the task returns to `ready` (not `pending`, which would strand it).
5. `worker_done` authority requires taskId + dispatchId + sender handle to match the *active* dispatch (`lifecycle_reconciliation.rs`) — a stale retry cannot complete or fail the current dispatch. A `worker_done` subject of `Failed: ...` consumes dispatch failure/circuit-breaker budget instead of completing the task.
6. Heartbeats record only while the dispatch is `dispatched`.
7. Gate create is accepted only for `ready` or `dispatched` tasks. It sets the task `blocked` and completes any active dispatch; gate resolve returns the task to `ready` with the resolution injected into the next preamble.
8. Lifecycle messages reconcile before waking blocked waiters, so the dispatch lock is released by the time a coordinator reads the result.
9. Long-poll waiters (`check --wait`, `ask`) have a server-side deadline (600 s max) and die with their client connection.

## Coordinator

`orchestration run` starts a background ticker inside the host (one active run at a time; the run keeps the host alive). Each tick executes in the actor: process coordinator inbox (worker_done/heartbeat reconcile, authorized escalation → fail dispatch, authorized decision_gate → create gate) → re-assert gate blocks → warn hung dispatches (no heartbeat for 10 minutes; warn-only) → dispatch ready tasks (default max 4 concurrent, one new worker terminal per tick when none idle) → check convergence (all tasks completed/failed).

The automated coordinator only dispatches to injection-ready agents whose prompts can be auto-submitted. Cursor-type agents are skipped by `run` because their injected text intentionally remains editable; use manual `dispatch --inject` or a Claude-style worker for unattended coordinator loops.

Dispatch pre-flight probes worktree drift via `alera_core::git::probe_base_drift` (git2 `graph_ahead_behind` + revwalk, no fetch). More than 20 commits behind skips the dispatch silently — retried next tick without burning circuit budget — unless the spec contains `allow-stale-base: true` on its own line (the directive is stripped before the worker sees the spec).

Task decomposition is the caller's responsibility: `run` refuses to start with zero tasks.

## Worker Terminals

`alera tab create --command "claude" --spawn` mints a terminal tab whose payload carries `initialCommand` and `spawnOnCreate`. The app starts flagged tabs eagerly on arrival (`workbench_controller_sync.dart`) and writes the command once, only on new PTY creation — never on reattach (`terminal_runtime_session_handle.dart`). The coordinator uses the same mechanism when it needs a worker and none is idle.

**v1 limitation**: worker creation requires the app to be connected — agent hook environments are built app-side. A headless host queues work until an app connects or a worker appears.

## JSON Shape

Orchestration payloads serialize with snake_case fields and Orca's exact status strings (`worker_done`, `circuit_broken`, ...) so agent-facing skills and docs stay portable between Orca and Alera. This intentionally diverges from Alera's camelCase convention and is confined to orchestration rows.

## Testing

- `cargo test -p alera-core --features runtime` — store invariants (DAG promotion, circuit breaker, heartbeat guard, read/delivered independence, gates, resets).
- `cargo test -p alera-cli` — engine unit tests (reconciliation authority branches, preamble content, formatter, group resolution, presence, waiter type filters) and the end-to-end suite `tests/orchestration_conformance.rs` (real host binary, raw TCP: send/check/reply, wait wakeups + type filtering, ask/reply, DAG dispatch, gates, push-on-idle against a live PTY).
- `flutter test test/unit/agent_status_host_forwarder_test.dart` — the app-side presence forwarder.

The agent-facing usage guide is `skills/alera-orchestration/SKILL.md`.

## Settings Setup

`Settings > Agents > Alera CLI And Skills` can install or update the global `alera-orchestration` skill with `npx`, `bunx`, or the automatic fallback. A successful in-app installation reapplies only the status hooks already selected by the user. It does not enable new hook toggles; overlay-backed hooks take effect for newly launched terminals.

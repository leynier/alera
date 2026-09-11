---
name: alera-orchestration
description: Dispatch, coordinate, and complete agent tasks through Alera orchestration.
metadata:
  version: 3
---

# Alera Orchestration

The runtime host owns lifecycle authority. Use its lifecycle commands, not generic messages or arbitrary status edits, for completion, cancellation, leases, and ownership.

## Choose Your Role

- Dispatched worker: accept first with `alera orchestration dispatch-accept`, then read `alera orchestration --json context` and [worker](references/worker.md). Follow the installed task and worker instructions.
- Coordinator dispatching work or managing a run: read [coordinator](references/coordinator.md).
- Stalled tasks, cancellation, gates, or ownership transfer: read [recovery](references/recovery.md).
- Message delivery or terminal inspection: read [messaging](references/messaging.md).

Read only the references relevant to the current role. Worker completion is atomic and required exactly once; after successful completion, stop the turn and leave the terminal available for reuse.

## Shared Constraints

Run inside an Alera terminal. `ALERA_TERMINAL_HANDLE` identifies the caller and `ALERA_WORKSPACE_ID` supplies the workspace default; `alera orchestration current` inspects both. Check `alera version --json` if compatibility is uncertain.

Scope every task to its workspace and coordinator. A workspace may have one active coordinator run; run tasks and injected workers must match that run's workspace and coordinator.

Honor prior explicit user authorization for the same scope without duplicate approval requests. Runtime policy approvals and user-owned stall gates still apply; never bypass them or invent a user decision. Active workers ask the coordinator through `alera orchestration ask`, not a local user-input prompt.

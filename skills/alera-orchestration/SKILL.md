---
name: alera-orchestration
description: Use when coordinating multiple coding agents through Alera orchestration protocol v2, including scoped runs, task DAGs, atomic lifecycle operations, decision gates, and worker recovery.
metadata:
  version: 2
---

# Alera Inter-Agent Orchestration

Use this skill for structured multi-agent work in Alera. The runtime-host owns lifecycle authority; do not emulate completion, cancellation, leases, or ownership with generic messages.

## Preconditions

- Run inside an Alera terminal so `ALERA_TERMINAL_HANDLE` identifies the caller.
- Use `alera version --json` when CLI/host/skill compatibility is uncertain.
- Keep every coordinated task scoped to a workspace and coordinator. A workspace may have one active coordinator run; different workspaces may run concurrently. Tasks created for a run and injected worker terminals must match that run's workspace and coordinator.

## Coordinator Workflow

```bash
alera orchestration --json task-create --workspace <workspace-id> --task-title "Review Tests" --spec "Review automated test coverage"
alera orchestration --json run --workspace <workspace-id> --agent codex --spec "Audit the repository"
alera orchestration --json run-list --workspace <workspace-id>
alera orchestration --json status --id <run-id>
```

Use `--agent codex|claude|copilot|cursor|agy|opencode|pi|amp`. The runtime may create workers through the built-in adapter registry. Stop scheduling with `run-stop --id`; add `--cancel-active` only when active work should receive cooperative cancellation. Run stop, task recovery, and dispatch interruption require the owning coordinator; `--force` is the audited administrative recovery path.

For direct assignment:

```bash
alera orchestration --json agent-spawn --workspace <workspace-id> --agent codex --task <task-id> --title "Review Tests"
alera orchestration --json terminal-wait --terminal <handle> --for dispatch-accepted --timeout-ms 60000
```

`agent-spawn` encapsulates terminal creation, native agent startup, readiness, forced preamble submission, and acceptance. A timeout is an exit-0 outcome, not a transport failure.

## Worker Contract

The dispatch preamble installs a terminal-scoped context. Execute acceptance before doing work:

```bash
alera orchestration dispatch-accept
alera orchestration --json context
```

Use context-aware lifecycle commands:

```bash
alera orchestration heartbeat --phase reviewing
alera orchestration escalate --subject "Blocked" --body "Missing credentials"
alera orchestration complete --summary "Review completed" --completion-kind success --artifacts '[]' --files-modified "path/a" --validation '[]'
```

If the task defines a custom result schema, add its properties with `--result-extra '{"field":"value"}'`.

- `complete` is atomic and required exactly once. `completion-kind failure` consumes execution failure budget and may return the task to ready.
- `worker-done --task --dispatch --summary` is the idempotent explicit recovery form.
- Never use `send --type worker_done`, `send --type heartbeat`, or arbitrary task status mutation; protocol v2 rejects them.
- After successful completion, stop the turn. Default policy returns immediately and leaves the terminal open for reuse.
- Use `ask` for coordinator questions. While a dispatch is active, the host routes the question to the dispatch's current durable coordinator even if the run was transferred after its preamble was injected. Do not open a local user-input prompt the coordinator cannot see.

## Tasks, Gates, And Recovery

```bash
alera orchestration task-list --run <run-id>
alera orchestration task-show --id <task-id>
alera orchestration gate-create --task <task-id> --question "Choose approach" --options '["A","B"]'
alera orchestration gate-resolve --id <gate-id> --resolution "A"
alera orchestration task-cancel --id <task-id> --reason "No longer needed"
alera orchestration task-recover --id <task-id> --status ready --reason "Worker inspected and stopped"
```

Cancellation propagates to unstarted descendants, including tasks created after a dependency was already cancelled. Lease expiry produces `stalled`, keeps the concurrency slot occupied, and never silently redispatches work. Recovery and forced lifecycle mutations require a reason and are audited. Transfer a complete run rather than one of its owned tasks.

```bash
alera orchestration transfer-coordinator --task <task-id> --to <handle> --reason "Handoff"
alera orchestration transfer-coordinator --run <run-id> --to <handle> --force --reason "Coordinator crashed"
```

Self-dispatch is rejected unless `--allow-self-dispatch` is explicitly supplied for a protocol test.

## Messaging And Diagnostics

```bash
alera orchestration send --to <handle|@group> --subject "Status" --body "Details"
alera orchestration inbox --terminal <handle> --direction inbox
alera orchestration inbox --terminal <handle> --direction outbox
alera orchestration check --wait --types escalation,decision_gate --timeout-ms 300000
alera orchestration terminal-show --handle <handle>
alera terminal read --handle <handle> --max-bytes 65536
alera terminal write --handle <handle> --text "continue" --enter
```

Use `--body-file` or `--body-stdin` for multiline content. Operational messages become expired or obsolete when their scope ends. List commands return `{kind, items, filters}`; use `items` in automation.

For the compact command contract at runtime, call `alera orchestration worker-help`.

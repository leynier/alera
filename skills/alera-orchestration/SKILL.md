---
name: alera-orchestration
description: Use when coordinating multiple coding agents through Alera orchestration protocol v2, including scoped runs, task DAGs, atomic lifecycle operations, decision gates, and worker recovery.
metadata:
  version: 3
---

# Alera Inter-Agent Orchestration

Use this skill for structured multi-agent work in Alera. The runtime-host owns lifecycle authority; do not emulate completion, cancellation, leases, or ownership with generic messages.

## Preconditions

- Run inside an Alera terminal so `ALERA_TERMINAL_HANDLE` identifies the caller.
- `ALERA_WORKSPACE_ID` supplies the default workspace for task creation, direct spawn, coordinator runs, and terminal listings. Use `alera orchestration current` to inspect both inferred identities.
- Use `alera version --json` when CLI/host/skill compatibility is uncertain.
- Keep every coordinated task scoped to a workspace and coordinator. A workspace may have one active coordinator run; different workspaces may run concurrently. Tasks created for a run and injected worker terminals must match that run's workspace and coordinator.

## Coordinator Workflow

```bash
alera orchestration --json task-create --task-title "Review Tests" --spec "Review automated test coverage"
alera orchestration --json run --agent codex --spec "Audit the repository"
alera orchestration --json run-list --workspace <workspace-id>
alera orchestration --json status --id <run-id>
```

Use `--agent codex|claude|copilot|cursor|agy|opencode|opencode2|pi|amp|grok`. The runtime may create workers through the built-in adapter registry.

To discover the launch configurations the user declared, read the catalog:

```bash
alera orchestration --json agent-profiles
```

Each profile carries `name`, `agentType`, `command`, `description`, and an optional `quotaGroup`. Use `description` to choose a profile for a stage, and pass its `agentType` and `command` to `agent-spawn`. The catalog is read-only: never invent a profile or a launch command, and never edit one on the user's behalf. Profiles sharing a `quotaGroup` drain the same usage bucket, so falling back inside one group buys nothing. Stop scheduling with `run-stop --id`; add `--cancel-active` only when active work should receive cooperative cancellation. Run stop, task recovery, and dispatch interruption require the owning coordinator; `--force` is the audited administrative recovery path.

### Planning A Run

When a run should be split across agents, propose a stage plan and let the user approve it before dispatching:

```bash
alera orchestration --json run-policy-propose --run <run-id> --policy-file plan.json
alera orchestration --json run-policy-show --run <run-id>
alera orchestration --json task-create --run <run-id> --stage implementation --spec "..."
```

```json
{
  "version": 1,
  "stallPolicy": "ask",
  "stages": [
    {"id": "implementation", "title": "Implementation", "profile": "Codex GPT-5.6-Sol", "fallbacks": ["Claude Sonnet 5"]}
  ]
}
```

Pick each stage's profile by reading the catalog descriptions; every profile named, preferred or fallback, must already exist there. Prefer a fallback from a different `quotaGroup`, since a fallback inside the same bucket buys nothing. `stallPolicy` is `ask`, `auto-failover`, or `wait`.

A proposed plan holds scheduling until the user resolves it, so propose before creating stage-bound tasks and then wait. Do not approve your own plan: approval is the user's decision. A plan is revised by proposing again, not by re-approving.

For direct assignment:

```bash
alera orchestration --json agent-spawn --agent codex --task <task-id> --title "Review Tests" --timeout-ms 90000
alera terminal --json wait --terminal <handle> --for dispatch-accepted --timeout-ms 60000
```

`agent-spawn --profile <name>` launches a declared profile, resolving the adapter and command host-side; it replaces `--agent` and cannot be combined with `--agent` or `--command`. For a task bound to a policy stage the coordinator selects the profile itself, preferring a fallback from a different quota group.

`agent-spawn` creates the dispatch before launching Codex and supplies a short first-turn bootstrap that tells the worker to accept and read its context. Other adapters use hook-based readiness injection. Its `--timeout-ms` value may not exceed the host acceptance limit of 90000 milliseconds. A startup failure removes only a terminal created by that spawn; add `--keep-on-failure` to retain it for diagnosis. Reused terminals are never removed.

Manual fallback is:

```bash
alera orchestration dispatch --task <task-id> --to <handle>
alera terminal write --handle <handle> --text "<returned bootstrap>" --submit
```

The default dispatch response returns the short bootstrap. Use `--return-preamble` only when the complete preamble is explicitly needed. If an agent is confirmed idle but its hooks are unavailable, `dispatch --inject --assume-agent codex` is an audited override.

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
alera orchestration task-wait --task <task-id> --for completed,failed,stalled --timeout-ms 300000
alera orchestration gate-create --task <task-id> --question "Choose approach" --options '["A","B"]'
alera orchestration gate-resolve --id <gate-id> --resolution "A"
alera orchestration task-cancel --id <task-id> --reason "No longer needed"
alera orchestration task-recover --id <task-id> --status ready --reason "Worker inspected and stopped"
```

When a run's approved policy sets `stallPolicy: ask`, a stalled worker opens a decision gate with diagnostics attached. Resolve it with `gate-resolve` using one of `Kill And Failover`, `Keep Waiting`, or `Abort Stage`. Never resolve a stall gate on the user's behalf: the whole point is that a worker which may still be running is not respawned without a decision.

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
alera terminal list
alera terminal read --handle <handle> --max-bytes 65536
alera terminal write --handle <handle> --text "continue" --enter
alera terminal write --handle <handle> --stdin --submit
alera terminal prune
alera terminal prune --apply
```

`--enter` sends content first and a separate delayed carriage return. Use `--submit` for bracketed-paste TUI input. `terminal prune` is dry-run by default and only removes stopped terminal tabs when `--apply` is present.

Use `--body-file` or `--body-stdin` for multiline content. Operational messages become expired or obsolete when their scope ends. List commands return `{kind, items, filters}`; use `items` in automation. Terminal and task waits are held by the runtime host and make a final state check at timeout.

For the compact command contract at runtime, call `alera orchestration worker-help`.

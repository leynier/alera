# Tasks, Gates, And Recovery

```bash
alera orchestration task show --id <task-id>
alera orchestration task wait --id <task-id> --for completed,failed,stalled --timeout-ms 300000
alera orchestration task cancel --id <task-id> --reason "No longer needed"
alera orchestration task recover --id <task-id> --status ready --reason "Worker inspected and stopped"
alera orchestration dispatch show --task <task-id>
alera orchestration dispatch interrupt --id <dispatch-id> --reason "Wrong approach"
```

Cancellation propagates to unstarted descendants. A worker with no terminal output or worker command for 10 minutes becomes `stalled`: the task keeps its concurrency slot and is never redispatched silently. Any later output or worker command revives it. Recovery and forced lifecycle mutations require a reason and are audited; `--force` is the administrative path when you are not the owning coordinator.

## Gates

```bash
alera orchestration --json gate list --run <run-id> --status pending
alera orchestration --json gate show --id <gate-id>
alera orchestration gate create --task <task-id> --question "Choose approach" --options '["A","B"]'
alera orchestration gate resolve --id <gate-id> --decision A
```

Gate kinds and their option ids:

- `plan` and `stage`: `approve`, `requestChanges` (needs `--reason`, optionally `--tasks`), `reject`. A rejected plan cancels the run.
- `stall` (opened when the run's stall policy is `ask`): `killAndFailover`, `keepWaiting`, `abortStage`.
- `decision` (from `gate create`): one of its options, or free text when it has none.

A gate with options accepts only one of them. Pass `--expected-digest` with the `evidenceDigest` from `gate show`, so a gate whose evidence changed is refused as stale. Plan, stage, and stall gates are the user's decisions: never resolve them on the user's behalf, and never approve a plan you proposed. A stalled worker may still be running, so it is not killed or replaced without that decision.

## Ownership

```bash
alera orchestration transfer-coordinator --task <task-id> --to <handle> --reason "Handoff"
alera orchestration transfer-coordinator --run <run-id> --to <handle> --force --reason "Coordinator crashed"
```

Transfer a complete run rather than one of its owned tasks. For diagnostics, read [messaging](messaging.md).

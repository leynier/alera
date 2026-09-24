# Tasks, Gates, And Recovery

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

For diagnostic commands, read [messaging](messaging.md).

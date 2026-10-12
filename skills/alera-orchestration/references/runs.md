# Runs

A run groups a plan, its tasks, gates, a timeline, and retained resources. Statuses: `planning`, `awaitingApproval`, `running`, `paused`, `completed`, `failed`, `cancelled`.

```bash
alera orchestration --json run list [--workspace <id>] [--bucket attention|active|history]
alera orchestration --json run show --run <run-id>
alera orchestration --json run timeline --run <run-id> [--task <task-id>] [--kinds message,gateOpened]
alera orchestration --json plan show --run <run-id>
alera orchestration --json task show --id <task-id> --run <run-id>
alera orchestration --json gate list --run <run-id> --status pending
```

`run list` pages with `--cursor '<nextCursor JSON>'`; `run show` returns pending gates, the coordinator, the plan state, `controlSequence`, and a page of tasks (`--after-task`). The timeline is newest first and pages with `--cursor`.

## Control

```bash
alera orchestration run pause --run <run-id>
alera orchestration run resume --run <run-id>
alera orchestration run replan --run <run-id> --reason "Split the API task" [--tasks <id>,<id>]
alera orchestration run cancel --run <run-id> --reason "No longer needed"
```

Control commands act on the run's current `controlSequence`; pass `--expected-sequence` from `run show` to refuse acting on a run that changed since you looked. `pause` stops new work while dispatched workers keep going; `resume` is refused while a plan or stage gate waits. `replan` asks the coordinator for a new plan revision. `cancel` interrupts workers and the coordinator, cancels unfinished tasks, and invalidates pending gates; a coordinator stops its own run the same way.

In a paused isolated run, `run retry --run <id> --task <task-id>` starts a new attempt and `--integration <task-id>` integrates a result again; `--cancellation` retries a cancellation that needs attention.

## Resources And Cleanup

Isolated runs keep their worktrees and branches until cleanup. Selecting removes nothing until a reviewed preview is applied.

```bash
alera orchestration --json run resources --run <run-id>
alera orchestration --json run integrations --run <run-id>
alera orchestration --json run cleanup preview --run <run-id> --resource <workspace-id> [--delete-branch <workspace-id>]
alera orchestration --json run cleanup apply --id <cleanup-id> --digest <digest>
alera orchestration --json run cleanup status --id <cleanup-id>
alera orchestration --json run cleanup list --run <run-id>
alera orchestration run cleanup retry --id <cleanup-id> --digest <digest>
alera orchestration run cleanup abandon --id <cleanup-id> --digest <digest>
```

Preview at most 25 resources at once. `apply` fails if anything changed since the preview. Only clean up when the user asked for it.

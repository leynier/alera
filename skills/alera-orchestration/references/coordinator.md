# Coordinator

## Delegating Tasks

```bash
alera orchestration --json agent-profiles
alera orchestration --json delegate --profile "Codex Sol" --spec "Review automated test coverage"
alera orchestration --json delegate --profile "Codex Sol" --spec "Implement the API" --new-workspace
alera orchestration --json delegate --profile "Opus" --spec-file brief.md --terminal <handle>
alera orchestration --json delegate --profile "Codex Sol" --spec "Write docs" --depends-on <task-id>,<task-id>
```

`delegate` creates the task, starts the profile in a new terminal, and waits until the agent is ready (`--timeout-ms`, at most 180000). The task joins your delegated run in the workspace, or starts one; pass `--run <run-id>` to add it to a run you coordinate, and `--stage <stage-id>` to bind it to a stage of that run's plan. `--terminal <handle>` hands the task to an agent already running in that terminal. `--new-workspace` creates a child worktree first, inferring project, source branch, and parent from `ALERA_WORKSPACE_ID` or `--from-workspace`. `--contract '<json>' --contract-inputs '<json>'` freezes a version 1 role contract with concrete inputs.

Choose profiles from `agent-profiles` only: each carries `name`, `agentType`, `description`, and an optional `quotaGroup`. Profiles sharing a `quotaGroup` drain the same usage bucket, so a fallback inside one group buys nothing. Profile administration is a separate user-requested task handled by the `alera-agent-profiles` skill.

A failed delegation can leave a created workspace and task even when the worker did not start. Keep the returned IDs, inspect the task and terminal (`task show`, `terminal show`), and retry only after confirming no worker is still executing. Do not repeat `delegate --new-workspace` blindly or remove the workspace automatically. A ready agent proves dispatch; task completion and its validation establish the outcome.

Follow delegated work with `alera orchestration task wait --id <task-id> --timeout-ms 300000` and answer worker questions with `check` and `reply` (see [messaging](messaging.md)).

## Starting A Planned Run

```bash
alera orchestration --json run new --profile "Opus" --spec "Add audit logging" --template builtIn:feature-delivery
alera orchestration --json run new --profile "Opus" --spec "Audit the repository" --isolation shared --approval
```

`run new` starts a coordinator agent with the given profile in its own terminal; it plans the run and the runtime carries the plan out.

- `--isolation isolated` (default): each task runs in its own worktree and its result integrates as a squash commit, in order. The recipe (`--template builtIn:<id>`, `personal:<id>`, `project:<path>`; default `builtIn:freeform`) fixes the stages and roles. See `alera orchestration recipe list`.
- `--isolation shared`: workers share the run's workspace; the coordinator declares stages with a profile each.
- `--approval` holds the plan behind a plan gate until the user approves it. Without it the run starts as soon as a plan is proposed.
- `--worker-profile` and `--role-profile role=profile` choose worker profiles; `--max-concurrent` and `--stall-policy ask|auto-failover|wait` tune scheduling.

## Planning As A Run's Coordinator

```bash
alera orchestration --json plan context --run <run-id>
alera orchestration plan propose --run <run-id> --stdin < plan.json
```

`plan context` returns the objective, source, recipe, profiles, the current plan, any change request, and `planShape`, the JSON shape to propose. An isolated plan lists `tasks` (`id`, `title`, `spec`, `stageId`, optional `roleId`, `dependsOn`, `inputs`) against the recipe's stages. A shared plan also lists `stages` (`id`, `title`, `profile`, `fallbacks`, `gate`), whose profiles must exist in the catalog; prefer fallbacks from a different `quotaGroup`. Both accept `stallPolicy` and `maxConcurrent`.

Each proposal creates the next plan revision; one made while a plan waits for approval supersedes it. An isolated run accepts proposals only while planning or awaiting approval; a shared run also while running or paused. Do not edit repository files or start workers while planning, and never approve your own plan: approval is the user's decision. When changes are requested, read `plan context` again (its `correction` names the reason and prior results) and propose a corrected plan.

Stop scheduling with `alera orchestration run cancel --run <run-id>`; see [runs](runs.md).

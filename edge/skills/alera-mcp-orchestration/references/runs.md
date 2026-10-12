# Runs And Recipes

A run moves through `planning`, `awaitingApproval` (only when it requires approval), `running` or `paused`, and ends `completed`, `failed`, or `cancelled`.

## Starting A Run

`create_run` starts a coordinator agent with `coordinatorProfile` (from `list_agent_profiles`) in the workspace. It reads the objective, proposes a plan, and the runtime carries the plan out. Pass `clientRequestId` so a retry does not start a second run.
- `isolation` `isolated` (default) gives each task its own worktree and integrates results in order; `recipe` (`builtIn:<id>`, `personal:<id>`, or `project:<path>`) fixes its stages and roles, and defaults to the built-in freeform recipe.
- `isolation` `shared` lets workers use the run's workspace; the coordinator declares stages with a profile each.
- `approvalRequired` holds the plan for a person's approval. Without it the run starts as soon as a plan is proposed.

`show_run_plan_context` shows what the coordinator plans against, and `propose_run_plan` proposes a plan as JSON when you act as the coordinator. Never approve a plan you proposed.

## Following A Run

- `list_runs` pages runs grouped as attention, active, or history.
- `show_run` shows status, plan state, coordinator, pending gates, cleanup, `controlSequence`, and a page of tasks.
- `get_run_timeline` reads events and messages between the run's agents, newest first.
- `show_run_plan` shows the current plan or one revision. `inspect_task` reads one task with its result, attempt, gates, and history.
- `wait_for_events` with the kinds `orchestration.task.state` and `orchestration.gate.created` follows tasks and new gates without polling each run.

## Gates

`list_run_gates` lists plan approval, stage, decision, and stall gates; `show_run_gate` shows one with its options, `evidenceDigest`, and what it decides on.

`resolve_run_gate` needs administrative access and the user's explicit decision; never decide for the user. Plan and stage gates take `approve`, `requestChanges` (with `reason`), or `reject`; stall gates take `killAndFailover`, `keepWaiting`, or `abortStage`; decision gates take one of their options. Pass `expectedEvidenceDigest` so a gate whose evidence changed is refused as stale, then read the gate again.

## Control

`pause_run`, `resume_run`, `replan_run` (with what should change), and `cancel_run` act on the run as it is now; pass `expectedSequence` from `show_run` to refuse acting on a run that changed since. Pausing stops new work; dispatched workers keep going. `resume_run` is refused while a plan or stage gate waits. `cancel_run` interrupts workers and the coordinator and keeps retained worktrees.

In a paused isolated run, `retry_run_task` starts a new attempt of a task that needs attention, and `retry_run_integration` integrates its result again. `list_run_integrations` lists integration outcomes and conflicts.

## Cleanup

Cleanup is preview first, then apply with the preview's id and digest. Do it only when the user asks.
- `list_run_resources` lists retained worktrees and branches; `list_run_cleanups` lists cleanups.
- `preview_run_cleanup` previews removing up to 25 of them (`deleteBranchFor` also deletes their branches), and `show_run_cleanup` shows one cleanup.
- `apply_run_cleanup` removes them. `retry_run_cleanup` retries an unfinished cleanup, and `abandon_run_cleanup` keeps what was not removed. These three need administrative access.

## Recipes

- `list_recipes` lists built-in, personal, and a workspace's project recipes. `show_recipe` shows one with its digest, roles, and stages.
- `validate_recipe` checks YAML without saving or running it.
- `save_personal_recipe` creates or updates a personal recipe; updating needs its current revision.
- `preview_recipe_export` previews writing a recipe into a project's `.alera/workflows`. `export_recipe` writes it with the digest from the preview, and fails if anything changed since.

# Isolated Runs: Worktrees And Integration

An isolated [run](runs.md) keeps every task attempt in its own Git worktree and integrates results locally, one at a time, as squash commits. This page describes the runtime contracts behind that: attempt preparation, launch, integration receipts, recovery and cleanup. Agent Profiles and the existing terminal host do the work; no model provider or model is imposed, nothing is pushed, no pull request is opened, and no remote branch is merged. A worktree isolates Git changes; it is not an operating-system sandbox.

## Ownership

The run and its tasks belong to the source workspace. The run owns an integration workspace, created from the exact source commit frozen by `runs.create`, and lazily prepared attempt workspaces. Each attempt records its own execution workspace, instance, branch and base SHA, and its dispatch is bound to that execution workspace. Uncommitted changes in the source workspace are excluded and left untouched.

Branches are named `alera/runs/<workspace-uuid>`. Callers cannot choose resource paths, branches or existing workspace identities. Preparation uses the runtime's managed workspace directory and project layout, resolving symlinked ancestors before freezing the destination, and reuses the project's trusted setup, including explicit copy rules and `.worktreeinclude`. Those rules can intentionally copy ignored local files into the attempt.

Generic managed-workspace removal and setup replay reject run-owned resources, including worktrees re-registered under another metadata id. Project reconciliation keeps run identities when a checkout is missing, detached or on another branch; `workspace.list` reports a runtime-derived `workflowOwned` flag from one bulk ownership query, never from client input. Cancellation and orchestration resets preserve ownership records and Git data.

## The Scheduler Pump

While an isolated run is `running`, the runtime's scheduler pump walks its plan and takes one step at a time: prepare the integration workspace, prepare an attempt for a ready task, launch a prepared attempt, integrate a completed result, or open a stage gate that became due. There is no manual prepare, launch or integrate command. Attempts start from the current integration SHA, require integrated prerequisite results and approved prior gates, and respect the run's frozen concurrency limit (four by default, at most sixteen). Git and filesystem work runs outside the host actor.

### Preparation

A transaction reserves identities and request receipts before Git runs, and stable OS file locks serialize each resource. The Git branch-creation reflog entry is promoted into an immutable blob anchored by a private `refs/alera/run-resources/<workspace-uuid>` ref. This repository-local receipt binds the repository, destination, branch and base SHA and survives reflog expiry and garbage collection. Recovery can promote the authentic creation reflog after an interruption but never overwrites a conflicting receipt. Missing or foreign receipts, replaced identities, moved branches and occupied destinations are not adopted or overwritten.

Setup start is persisted before any copy or command. If its outcome is unknown after an interruption, the attempt becomes Attention and setup is not replayed. A failed setup keeps its report and worktree; large reports keep bounded details and a summary of omitted steps.

### Launch

A transaction assigns immutable launch, dispatch and terminal identities before the worker starts, through the single dispatch path shared with shared runs (`create_run_dispatch` with an attempt target). The `runDispatchRequiresLaunch` trigger refuses any dispatch to an isolated task that does not come from a reserved attempt launch, and a terminal dispatch to an isolated task is refused before it reaches the store. The worker receives the frozen profile configuration, custom instructions, task inputs and role contract; later catalog edits do not affect it. Its context token stays out of launch receipts and exports.

The worker has two minutes to run its first worker command (`context`, `ask`, `escalate` or `complete`, which accepts the dispatch implicitly). Otherwise its terminal is stopped and the attempt is retained in Attention. Terminal restoration and restart never replay a launch: opening a retained terminal attaches to the existing process or reads its checkpoint. An interrupted launch becomes Attention.

Retrying a task (`runs.retryTask`, run paused first) prepares a fresh attempt with a new branch and worktree and keeps the previous attempt. No automatic reset, rebase or cleanup is performed, and completed tasks are never reopened by this path.

## Result Ready Versus Integrated

The worker commits its changes and required artifacts on its own branch before completing. A completed result is ready for integration; it is neither integrated nor a gate approval, and dependents stay blocked until Git and durable evidence both finish.

Integration captures the exact committed result SHA, the current integration SHA, the result digest and the artifact paths. Both workspaces must be clean; uncommitted changes cause refusal, not implicit staging. Required artifacts must be committed regular files inside the worktree. Results are merged in memory against their original task base and squashed serially onto the integration head. A result without tree changes produces no empty commit. New commits use the repository's configured Git identity.

A conflict reports bounded paths without changing the integration index, worktree or branch. Nothing is resolved by an agent and active branches are not rebased. A committed submodule delta, or an artifact missing or no longer a regular file in the merged tree, is a definitive pre-apply refusal: the checkout, branch and receipt ref stay untouched and the task shows Needs Correction. Both settle the integration as `conflict`; the way forward is a corrected plan revision (Request Changes on a gate, or `runs.control replan` naming the task), which keeps the original completion SHA and worktrees.

## Receipts And Recovery

A SQLite reservation fences each integration before Git runs. An immutable metadata commit under `refs/alera/run-integrations/<id>` retains the result and the squash candidate through garbage collection. Safe checkout and exact head checks distinguish an untouched tree, a prepared checkout awaiting reference advancement, and an already applied commit. Mixed or dirty state that cannot be recognized becomes Attention without overwriting anything.

SQLite records integrated evidence and the new integration SHA only after Git verifies the receipt. Stage gates bind that SHA and the evidence digest, and an unsettled integration prevents resolving a gate and requesting changes. Cancellation, changed revisions or changed results never adopt stale evidence; such operations remain inspectable in Attention and cannot release dependents.

An integration in Attention is never retried on resume or host restart. Inspect the task and the integration workspace, correct the obstruction, then use `runs.retryIntegration` (run paused first). The runtime rechecks the original request, the Git resources, the receipt and the expected SHA; an unresolved issue stays in Attention without overwriting files. Resume the run separately afterwards.

Startup performs bounded recovery, not a polling loop: it reconciles confirmed work and leaves uncertain setup, launch and integration outcomes in Attention rather than repeating commands. Stable request ids make reconnects safe: replaying a request returns its receipt instead of acting twice.

### Cancellation

Cancelling a run stops its coordinator and worker terminals and prevents further dispatch; worktrees, branches and results remain. Setup and Git operations already in progress finish safely. A pending cancellation is not proof that its processes have stopped. Transient sweep failures retry on the runtime's background lane after two seconds without a second concurrent sweep. A settlement failure is recorded as Attention, other targets still receive cancellation, and recorded Attention waits for `runs.retryCancellation`, which is bound to the observed control sequence: repeating a lost request cannot restart a later failed attempt.

Integrations reserved before cancellation settle separately. Recovery only inspects existing Git receipts and clean, unchanged owned worktrees; it never prepares or applies another result. An already-applied receipt stays in history, but cancellation creates no task evidence or dependent work. Dirty files, a changed identity or an unexpected HEAD remain Attention.

## Cleanup

Cleanup is an explicit action on a finished isolated run (completed, failed or cancelled once outstanding operations have settled). Select at most 25 of the run's resources; branch removal is opt-in per resource and defaults off.

1. `runs.previewCleanup` reserves the selected identities before inspection, blocking new terminal, browser and automation use, and returns paths, branches, base and head SHAs, changed files and a `digest`. Preparing a preview removes nothing.
2. `runs.applyCleanup {id, digest, confirm: true}` requires clean, unlocked worktrees with no Git operation and no active runtime owner. The runtime rechecks ownership and Git state at application time. A changed or busy resource becomes Attention without stopping processes or discarding files.
3. Git receipts under `refs/alera/run-cleanup/` and transactional retirement recover interruptions between filesystem work and metadata persistence. Already-retired paths are not touched again if another owner later reuses them.

Only a confirmed, applying cleanup resumes during startup; previews and Attention never auto-apply. Use `runs.retryCleanup` after correcting an obstruction. If the reviewed HEAD changed, `runs.abandonCleanup` from Attention preserves the remaining files and branches, keeps retired resources retired, records the original preview and error in history, and releases reservations only after verifying identities, Git state and the absence of active owners. An interrupted Git removal must first reconcile through Retry Cleanup; abandonment cannot discard a removal receipt. Retrying a lost abandonment response is idempotent and never releases reservations of a newer cleanup.

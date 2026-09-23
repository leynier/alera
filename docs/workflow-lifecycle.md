# Run Board workflows

Open Run Board from the application menu or its registered keyboard action. No default shortcut is assigned. The global Board groups runs into Attention, Active and History, with search and project/workspace filters. Selecting a run does not change the active workspace. Open Workspace, Open Terminal and Open Diff are explicit navigation actions.

## Propose, review and start

Choose New Run, a local Git project/workspace, a recipe and Agent Profiles. Built-in, Personal and Project recipes have explicit origins; matching names do not override each other. The source is an exact commit. Uncommitted source changes are excluded and preserved.

Save the proposal and start its coordinator to obtain a concrete task plan. A saved proposal is not permission to execute workers. Review the objective, stages, dependencies, contracts, profiles and source revision before approving. Recipe, contract and effective profile snapshots remain frozen for that reviewed execution.

An approved desktop plan starts paused. Start authorizes scheduling; Pause prevents new work while already-running operations finish. Each task attempt uses its own managed worktree, with four workers by default and the reviewed concurrency limit. Dependencies become eligible only after local integration, not when a worker reports completion.

Result Ready, Integrated and Conflict are distinct states. Results are integrated serially as local squash commits. A conflict preserves the integration workspace and requires inspection and a reviewed corrective plan. Active task branches are not automatically rebased. Foundation and Product Gates always require explicit human approval bound to the current evidence and integration SHA. Changed evidence requires review again.

## Attention and recovery

Inspect a task to see its profile, dependencies, attempt, branch, base SHA, result, artifacts and validation history. Retained terminals attach to the original process or its checkpoint; opening one does not repeat a worker launch.

Retrying a failed task prepares a fresh attempt in a new worktree while retaining the previous attempt. Request Changes creates a traceable corrective revision rather than silently reopening completed tasks. Resume execution explicitly after reviewing the correction.

Cancel stops the run's coordinator and worker terminals and prevents further dispatch. Worktrees, branches and results remain. Setup and Git operations already in progress finish safely. Cancellation is irreversible for that run; a pending cancellation is not proof that its processes have stopped.

Proposal cancellation similarly prevents coordinator launch and late plan submission. If stopping the coordinator needs Attention, inspect its retained terminal and use Retry Cancellation. The retry is tied to the observed receipt sequence. Repeating a request after response loss cannot restart a later failed attempt, and an obsolete completion cannot settle a newer attempt.

Disconnecting does not authorize fallback execution. Reconnect and refresh durable receipts before acting again. Startup reconciles confirmed work and leaves uncertain setup/launch outcomes in Attention rather than duplicating commands.

## Reviewed resource cleanup

Manage Resources lists retained resources and cleanup history inside the Board. The run overview identifies cleanup in progress or cleanup needing attention, even after the run has completed. New cleanup previews are available for completed or cancelled runs. Select only resources belonging to that run; branch removal is separately opt-in and defaults off.

Review the preview's paths, branches, base/head SHAs and changed files. Preparing a preview removes nothing. Confirmation requires clean, unlocked worktrees with no Git operation or active runtime owner. The runtime rechecks ownership and Git state at application time. A changed or busy resource becomes Attention without forcing processes to stop or discarding files.

Cleanup reserves the selected identities before inspection, blocking new terminal, browser and automation use. Git receipts and transactional retirement recover interruptions between filesystem work and metadata persistence. Already-retired paths are not touched again if another owner later reuses them.

Only confirmed Applying cleanup resumes during startup. Preview and Attention never auto-apply. Use Retry Cleanup after inspecting and correcting an obstruction. Partial progress remains visible in its durable receipt. Resources are otherwise retained after success, cancellation and error; there is no automatic cleanup.

If the reviewed HEAD changed, use Abandon Cleanup from Attention before preparing a new preview. Abandonment preserves remaining files and branches, keeps already retired resources retired, and records the original preview and error in history. It releases reservations only after verifying resource identities, Git state and absence of active owners. Interrupted Git removal must first reconcile through Retry Cleanup; abandonment cannot discard a removal receipt. Retrying a lost abandonment response is idempotent and never releases reservations belonging to a newer cleanup.

## Compatibility and boundaries

The additive desktop capability is `workflowRunLifecycleV1`, independent of Board read support. Strict protocol versions are unchanged. An older host shows Update Required; there is no shared-workspace, ungated or legacy-approval fallback. Workflow lifecycle and approval operations are not granted to paired mobile clients.

Approvals use the [desktop authorization boundary](workflow-plans.md), not a caller-supplied actor label. Worktrees isolate Git changes, not operating-system access. Workflows do not publish per-task PRs, merge remote branches or run a second model client.

See [recipe catalogs](workflow-recipes.md), [reviewed plans](workflow-plans.md), [task worktrees](workflow-worktrees.md) and [integration receipts](workflow-integration.md) for runtime contracts and recovery details.

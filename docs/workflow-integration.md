# Isolated workflow execution and local integration

Workflow execution reuses Agent Profiles and the existing terminal host. The run and tasks belong to the source workspace; every dispatch executes in its own managed attempt. No model provider or model is imposed.

## Launching an approved attempt

After approving a plan and preparing integration and the task workspace, launch the exact attempt:

```sh
alera orchestration workspaces launch --run <run-id> --revision <revision> --request-id <stable-id> --task <task-id> --workspace-id <attempt-id>
alera orchestration workspaces launches --run <run-id>
```

The runtime verifies resource ownership, the committed base, integrated dependencies, human gates and the frozen concurrency limit. Git and filesystem checks run outside the server actor. A transaction assigns immutable launch, dispatch and terminal identities before any worker starts. Request replay returns the same launch receipt; it never installs another context or spawns another worker.

The worker receives the profile configuration, custom instructions, task inputs and role contract approved with the plan. Catalog edits do not affect an active run. Its private context token stays out of launch receipts and catalog exports. Legacy dispatch cannot manufacture a matching workflow reservation. The worker must accept its dispatch within two minutes; otherwise the attempt is retained in Attention and requires an explicit retry.

Terminal restoration and restart cannot replay a workflow bootstrap. Opening a retained terminal attaches to its existing process or reads its checkpoint without executing commands. Interrupted launches become Attention; inspect retained files and processes before requesting a new attempt with `prepare --retry-of`. Completed tasks are never reopened by this recovery path.

## Result ready versus integrated

The worker commits its changes and required artifacts in its own branch before reporting a successful contracted result. A completed result is ready for integration, not integrated and not a gate approval. Dependencies remain blocked until native Git and durable evidence both finish.

```sh
alera orchestration workspaces integrate --run <run-id> --revision <revision> --request-id <stable-id> --task <task-id> --workspace-id <attempt-id>
alera orchestration workspaces integrations --run <run-id>
alera orchestration workspaces integration --id <integration-id>
```

Integration captures the exact committed result SHA, current integration SHA, result digest and artifact paths. Both workspaces must be clean. Uncommitted changes are left intact and cause refusal, not implicit staging. Required artifacts must be committed regular files inside the worktree. Results are merged in memory with their original task base and squashed serially onto the integration head. A result without tree changes produces no empty commit. New commits use the repository's configured Git identity.

Conflicts report bounded paths without changing the integration index, worktree or branch. Inspect the retained result and prepare a reviewed correction; no agent resolves conflicts automatically and active workers are not rebased. Integration preserves every task's original base SHA.

## Receipts and recovery

A SQLite reservation fences each integration before Git. An immutable metadata commit under `refs/alera/workflow-integrations/<id>` retains the result and squash candidate, including through Git garbage collection. Safe checkout and exact head checks distinguish an untouched tree, a prepared checkout awaiting reference advancement, and an already applied commit. Unrecognized mixed or dirty state becomes Attention without overwrite.

SQLite records the integrated evidence and new integration SHA only after native Git verifies its receipt. Approval challenges bind that SHA and the evidence, and unsettled integration prevents approving a gate. Cancellation, changed revisions or changed results cannot silently adopt stale evidence. Such interrupted operations remain inspectable in Attention and cannot release dependents.

Startup performs bounded recovery, not a hidden polling loop. Stable request IDs also support reconnect recovery. Launch lists and integration summaries are paginated; detailed receipts load separately. The additive `workflowLocalIntegrationV1` capability covers these local-authenticated APIs; strict protocol versions remain unchanged and old hosts require an update. They are not mobile APIs.

No operation publishes task PRs, merges remote branches or removes retained resources. Worktrees provide Git isolation, not an operating-system sandbox. Final human gates, reviewed cleanup and the desktop launch surface are separate lifecycle actions.

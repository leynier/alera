# Managed workflow worktrees

An approved workflow owns an integration workspace and lazily prepared task attempts. The run and its tasks retain their original owner workspace scope; an attempt records its separate execution workspace, instance, branch and base SHA. Its dispatch ID remains null until the launch layer is implemented. This layer does not dispatch workers. Serial integration and dependent dispatch are added separately.

## Preparation

```sh
alera orchestration workspaces prepare --run <run-id> --revision <revision> --request-id <stable-id>
alera orchestration workspaces prepare --run <run-id> --revision <revision> --request-id <stable-id> --task <task-id>
alera orchestration workspaces list --run <run-id> --limit 20
```

The first command prepares integration from the exact approved source commit. It does not refresh a branch, fetch, pull, rebase or run setup. Uncommitted source changes are excluded and remain intact. Task attempts start from the current integration SHA, require integrated prerequisite results and prior human gates, and respect the frozen concurrency limit (four by default).

Preparation uses the runtime's managed workspace directory and project layout, resolving symlinked ancestors before freezing the destination. Branches are named `alera/workflows/<workspace-uuid>`; callers cannot select resource paths, branches or existing workspace identities. Task setup reuses the existing trusted project configuration, including explicit copy rules and `.worktreeinclude`. Those rules can intentionally copy ignored/local project files; a worktree is Git isolation, not an OS sandbox.

The additive `workflowManagedWorktreesV1` capability is required. The local-authenticated RPCs are `workflows.prepareWorkspace` and `workflows.workspaces`; they are not mobile operations. Strict protocol versions are unchanged. An older host must show Update Required, never fall back to a shared workspace.

## Recovery and retries

A transaction reserves identities and request receipts before Git runs. Stable OS file locks serialize each resource. A Git branch-creation reflog receipt is promoted into an immutable blob anchored by a private `refs/alera/workflow-resources/<workspace-uuid>` ref. This repository-local receipt binds the repository, destination, branch and base SHA and survives reflog expiry and garbage collection. Recovery can promote the authentic creation reflog after interruption, but never overwrites a conflicting receipt. The registered worktree identity lets recovery reconcile completed Git work before workspace metadata was committed. Missing/foreign receipts, replaced identities, moved branches or occupied destinations are not adopted or overwritten.

Client disconnects and request timeouts do not cancel preparation. Retry the same request ID and contents; changing contents under that ID is rejected. Listing returns retained records in bounded pages, with `nextBeforeRow` for `--before-row`. Preparation holds the host alive and runs outside its actor.

On startup, one paginated recovery sweep reconciles unfinished preparations. Setup start is persisted before any copy or command. If its outcome is unknown after interruption, the attempt becomes Attention and setup is not replayed. A failed setup keeps its report and worktree. Large reports retain bounded details and a summary of omitted steps, including their failure count; truncation does not change the setup outcome. Inspect retained processes and files before retrying:

```sh
alera orchestration workspaces prepare --run <run-id> --revision <revision> --request-id <new-stable-id> --task <task-id> --retry-of <latest-attempt-workspace-id>
```

Every retry receives a new branch and worktree. No automatic reset, rebase or cleanup is performed. Generic managed-workspace removal and setup replay reject workflow-owned resources, including worktrees re-registered under another metadata ID. The desktop's generic project reconciliation also retains workflow identities when a checkout is missing, detached or on another branch; `workspace.list` includes a runtime-derived `workflowOwned` flag from one bulk ownership query, never from client input. Cancellation and legacy orchestration resets preserve resource ownership records and Git data. Reviewed cleanup belongs to the later Run Board lifecycle surface, including the retained ownership refs.

## Validation boundary

These APIs prepare resources only after human plan approval. A completed worker result alone will not make a dependent eligible: integrated evidence is required. Until the integration layer is available, the existing workflow dispatch barrier remains in place across all legacy paths.

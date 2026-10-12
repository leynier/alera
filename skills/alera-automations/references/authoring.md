# Targets And JSON

`--target` selects one of four execution targets:

| Target | Required Context | Behavior |
| --- | --- | --- |
| `fresh-tab` | Workspace and profile | New agent tab in the existing workspace |
| `existing-tab` | Workspace, tab, capturable conversation | Send to that live conversation |
| `worktree` | Project and/or parent workspace, source branch, profile | New Git worktree per run on this computer; with a parent workspace it is that workspace's child |
| `project-checkout` | Project, host, profile | Workspace in the registered local or SSH project folder |

For `worktree`, `--project-id` names the project and `--workspace-id` the parent workspace. Without `--project-id`, the current workspace is the parent. A retried attempt reuses the worktree its run created. `managed-workspace` and `project-worktree` are older names for `worktree` and still work. In JSON the target is `{"worktree": {"projectId": "...", "parentWorkspaceId": "...", "sourceBranch": "main", "agentProfileId": "..."}}` with either id optional; the older `managedWorkspace` and `projectWorktree` keys are still accepted.

Flag creation can use `--at <RFC3339>` instead of `--cron`, and `--prompt-file` instead of `--prompt`. `--origin-workspace-id` controls where the definition appears contextually, independently of the execution target. The CLI uses the current workspace as the origin when available. Section membership follows that workspace dynamically.

Partial JSON input needs no IDs, revision, timestamps, actors, or slug:

```json
{
  "name": "Daily Review",
  "promptTemplate": "Review {{project.name}} and summarize findings",
  "schedule": {"recurring": {"cron": "0 9 * * 1-5", "timezone": "America/Mexico_City"}},
  "target": {"freshTab": {"workspaceId": "workspace-id", "agentProfileId": "profile-id"}},
  "originWorkspaceId": "workspace-id"
}
```

Advanced fields include `precheck`, `overlapPolicy`, `misfirePolicy`, `cleanupPolicy`, `retryMaxAttempts`, `retryBackoffSeconds`, and schedule bounds. Omit them for server defaults. `edit --id <id> --file changes.json` accepts only changed fields and supports `--expected-revision` to detect a stale edit.

`run-now` uses the configured precheck and overlap behavior; overrides are optional. It runs once without changing the schedule. `--continue-from-run <run-id>` creates a new linked run in the prior run's preserved workspace with its summary and context. Omit it to start fresh. Completed definitions are read-only but can run again, be copied with `clone`, or trashed. Restoring returns a completed definition to Completed; other restored definitions are Paused.

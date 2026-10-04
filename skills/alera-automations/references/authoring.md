# Targets And JSON

`--target` selects one of four execution targets:

| Target | Required Context | Behavior |
| --- | --- | --- |
| `fresh-tab` | Workspace and profile | New agent tab in the existing workspace |
| `existing-tab` | Workspace, tab, capturable conversation | Send to that live conversation |
| `managed-workspace` | Source workspace, source branch, profile | New Git worktree per run |
| `project-checkout` | Project, host, profile | Workspace in the registered local or SSH project folder |

Flag creation can use `--at <RFC3339>` instead of `--cron`, and `--prompt-file` instead of `--prompt`. `--origin-workspace-id` controls where the definition appears contextually, independently of the execution target. The CLI uses the current workspace as the origin when available. Section membership follows that workspace dynamically.

Partial JSON input needs no IDs, revision, timestamps, actors, slug, or approval fields:

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

`run-now` uses the configured precheck and overlap behavior; overrides are optional. It runs once without changing the schedule. `--continue-from-run <run-id>` creates a new linked run in the prior run's preserved workspace with its summary and context. Omit it to start fresh. Completed definitions are read-only but can run again, be cloned through creation, or trashed. Restoring returns a completed definition to Completed; other restored definitions are Paused.

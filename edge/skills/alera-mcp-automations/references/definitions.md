# Definitions And Targets

`create_automation` takes a `definition` object. Leave out ids, revisions, actors, and timestamps:

```json
{
  "name": "Daily Review",
  "promptTemplate": "Review {{project.name}} and summarize findings",
  "schedule": {"recurring": {"cron": "0 9 * * 1-5", "timezone": "America/Mexico_City"}},
  "target": {"freshTab": {"workspaceId": "workspace-id", "agentProfileId": "profile-id"}},
  "originWorkspaceId": "workspace-id"
}
```

A one-time schedule is `{"oneTime": {"at": "2026-11-02T09:00:00Z", "timezone": "UTC"}}`; `at` is an RFC 3339 date and time. A recurring schedule may add `startAt`, `endAt`, and `maxScheduledRuns`.

The target is one of four:

| Target | Fields | Behavior |
| --- | --- | --- |
| `freshTab` | `workspaceId`, `agentProfileId` | A new agent tab in an existing workspace |
| `existingTab` | `workspaceId`, `tabId`, optional `conversationId` | Sends to that tab's live conversation |
| `worktree` | `projectId` and/or `parentWorkspaceId`, `sourceBranch`, `agentProfileId` | A new worktree and branch per run on this computer; with `parentWorkspaceId` it is a child of that workspace and the project comes from it |
| `projectCheckout` | `projectId`, `hostId`, `agentProfileId` | A workspace in the project's local or SSH folder |

`worktree` needs `projectId`, `parentWorkspaceId`, or both. The older `managedWorkspace` (`sourceWorkspaceId`) and `projectWorktree` spellings are still accepted and come back as `worktree`. A retried attempt reuses the worktree its run already created.

The targets that create a workspace also take an optional `nameTemplate`.

Find ids with `list_workspaces`, `list_projects`, `list_agent_profiles`, `list_tabs`, and `list_project_branches`. `originWorkspaceId` decides where the definition appears in the app, independent of the target.

Optional fields include `precheck`, `overlapPolicy`, `misfirePolicy`, `cleanupPolicy`, `retryMaxAttempts`, `retryBackoffSeconds`, and schedule bounds. Leave them out for the defaults. When a field is rejected, `check_automation_readiness` names it.

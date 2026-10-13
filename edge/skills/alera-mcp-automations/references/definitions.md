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
| `projectCheckout` | `projectId`, `hostId`, `agentProfileId` | A workspace in the project's folder on that host: `local`, or a host from `list_project_hosts` |

`worktree` needs `projectId`, `parentWorkspaceId`, or both. The older `managedWorkspace` (`sourceWorkspaceId`) and `projectWorktree` spellings are still accepted and come back as `worktree`. A retried attempt reuses the worktree its run already created.

The targets that create a workspace also take an optional `nameTemplate`.

Find ids with `list_workspaces`, `list_projects`, `list_agent_profiles`, `list_tabs`, and `list_project_branches`. `originWorkspaceId` decides where the definition appears in the app, independent of the target.

## Reuse

`reusePolicy` decides where runs after the first one go:

| Policy | Later runs |
| --- | --- |
| `newEachRun` (default) | Create the target again every run |
| `reuseWorkspace` | Open a new agent tab in the workspace the first run used |
| `reuseConversation` | Paste into the first run's agent when idle, wait while it is busy, relaunch it in a new tab of the same workspace when it is gone, and open a fresh tab there after a takeover |

A run that stays busy past the misfire grace window follows `overlapPolicy`: `forceParallel` opens a parallel tab in the bound workspace, anything else skips it. Reused runs start with a note naming the previous run's summary and error.

The runtime owns `boundTarget` and ignores it in your input. It is cleared when the target changes, when `reusePolicy` returns to `newEachRun`, or when the bound workspace is removed or archived; `unbind_automation_target` clears it on request. `reuseWorkspace` does not apply to `existingTab`, and any reuse rejects `cleanupPolicy: "onSuccess"`. Reuse needs a runtime that advertises `automationReuseV1`.

Optional fields include `precheck`, `overlapPolicy`, `misfirePolicy`, `cleanupPolicy`, `retryMaxAttempts`, `retryBackoffSeconds`, and schedule bounds. Leave them out for the defaults. When a field is rejected, `check_automation_readiness` names it.

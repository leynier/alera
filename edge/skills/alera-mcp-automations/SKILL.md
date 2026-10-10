---
name: alera-mcp-automations
description: Create, edit, inspect, pause, and run scheduled Alera agent automations through this MCP server, and follow their runs. Use for recurring or one-time agent work.
metadata:
  version: 1
---

# Alera Automations Through MCP

An automation is a definition: a prompt, a schedule, a target, and an agent profile. Each time it fires, it creates a run. Orchestration tasks are separate; see the `alera-mcp-orchestration` skill.

## Authoring

Choose the execution target explicitly; never infer its type. A valid prompt, schedule, target, and launchable profile are enough. There is no approval or repository declaration step. Read [definitions](references/definitions.md) for the definition JSON and the five targets.

1. `check_automation_readiness` validates a full or partial definition without saving it and lists the fields to fix. Run it before creating.
2. `preview_automation_schedule` lists the next occurrences of a cron expression or a one-time date in a time zone.
3. `create_automation` saves it, active unless `draft` is true. Pass `clientRequestId` so a retry does not create a duplicate.
4. `update_automation` changes the given fields. Pass `expectedRevision` to refuse a stale edit. Edits apply to future runs.
5. `clone_automation` copies an automation's settings and target.

## Reading

`list_automations` filters like the Automations view. `show_automation` shows the definition, readiness, next occurrences, recent runs, and audit history. `list_automation_runs` and `show_automation_run` read runs and their attempts.

## Running And State

- `run_automation` runs it once now, like Run Now, without changing its schedule. `continueFromRunId` continues an earlier run's conversation in its preserved workspace.
- `pause_automation` stops scheduling. When runs are active, `activeRuns` chooses whether they continue or are cancelled. `resume_automation` activates a paused or draft automation.
- `trash_automation` moves it to the trash, and `restore_automation` brings it back. `purge_automations` permanently deletes everything in the trash for at least 30 days; use it only on request.

## Runs

- `cancel_automation_run` cancels a queued, running, or waiting run.
- A run can wait for the user. `resume_automation_run` lets it continue, and `extend_automation_run` extends its deadline.
- `take_over_automation_run` hands the run's terminal to a person; the automation stops driving the agent. Use it only when the user intends to operate that agent.

The runtime must be running for schedules to fire. Occurrences missed while it was offline are skipped by default. An interrupted run recovers on its own in its preserved workspace, a bounded number of times. Do not launch a replacement into the same target while that is happening.

## Catalog

- `list_automation_templates` and `upsert_automation_template` manage prompt templates.
- `list_automation_tags` lists tags, and `upsert_automation_tags` creates or renames a tag and sets an automation's tags.
- `export_automations` exports automations, templates, and tags as a portable catalog. `import_automations` imports one.

# Workflow Recipes And Runs

A workflow recipe is a YAML plan of roles and stages. A workflow run goes through these steps:
1. A proposal.
2. A coordinator drafts the plan.
3. A person approves the plan in the Alera app.
4. Tasks run in isolated attempts.
5. Results integrate into an integration workspace.

Approval always belongs to a person.

## Recipes

- `list_recipes` lists built-in, personal, and a workspace's project recipes. `show_recipe` shows one with its digest, roles, and stages.
- `validate_recipe` checks YAML without saving or running it.
- `save_personal_recipe` creates or updates a personal recipe; updating needs its current revision.
- `preview_recipe_export` previews writing a recipe into a project's `.alera/workflows`. `export_recipe` writes it with the digest from the preview, and fails if anything changed since.

## Proposals And Plans

- `create_workflow_proposal` proposes a run from a recipe at the source workspace's current commit. `start_workflow_coordinator` starts its coordinator, which drafts the plan without approving it.
- `list_workflow_proposals` and `get_workflow_proposal` read proposals. `submit_workflow_proposal` submits the concrete task list as the coordinator would. `cancel_workflow_proposal` cancels a proposal and its coordinator.
- `prepare_workflow_plan` prepares a plan for review from a document with a stable `requestId`. `show_workflow_plan` shows a plan revision.
- `create_workflow_correction` opens a correction of an approved revision; a person approves the corrected plan.

## Execution

- `get_workflow_execution` shows whether an approved run is scheduling, paused, or cancelled, with the sequence number `control_workflow_execution` needs to start, pause, or cancel it.
- `prepare_workflow_attempt` prepares the integration workspace or a task's isolated attempt. `launch_workflow_task` launches an approved task in its attempt. `integrate_workflow_result` squashes a completed task's result into the integration workspace.
- `list_workflow_integrations` lists integration outcomes and conflicts. `list_workflow_workspaces` lists the workspaces a run keeps.

## Cleanup

Cleanup is preview first, then apply with the preview's id and digest.
- `list_workflow_cleanups` lists retained resources.
- `preview_workflow_cleanup` previews removing up to 25 workspaces, and `get_workflow_cleanup` shows an operation.
- `apply_workflow_cleanup` removes them. `retry_workflow_cleanup` retries an unfinished cleanup, and `abandon_workflow_cleanup` keeps what was not removed. These three need administrative access.

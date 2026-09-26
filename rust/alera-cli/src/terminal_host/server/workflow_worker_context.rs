use alera_core::runtime::OrchestrationDispatchContext;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::agent_prompt_composition::compose_agent_prompt;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn workflow_worker_context(
        &self,
        dispatch: &OrchestrationDispatchContext,
    ) -> HostResult<Option<Value>> {
        let Some(frozen) = self
            .runtime_store
            .workflow_launch_inputs_for_dispatch(&dispatch.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(None);
        };
        let mut task = self
            .runtime_store
            .orchestration_task_by_id(&dispatch.task_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("workflow task was removed"))?;
        task.spec = compose_agent_prompt(&frozen.task.task.spec, &frozen.profile.custom_prompt, "");
        let instructions = format!(
            "{}\n\n{}",
            WORKER_INSTRUCTIONS,
            frozen
                .task
                .contract
                .worker_instructions()
                .map_err(|error| HostError::state(error.to_string()))?
        );
        Ok(Some(json!({
            "task": task, "dispatch": dispatch, "inputs": frozen.task.task.inputs,
            "workerInstructions": instructions, "executionWorkspaceId": frozen.workspace.workspace.id,
            "ownerWorkspaceId": frozen.workspace.owner_workspace_id, "baseSha": frozen.workspace.base_sha,
            "planDigest": frozen.plan_digest, "assigneeHandle": dispatch.assignee_handle,
            "phase": dispatch.status.as_str(), "completionState": dispatch.status.as_str(),
            "lastActivityAt": dispatch.last_activity_at,
        })))
    }
}

const WORKER_INSTRUCTIONS: &str = r#"This is one isolated attempt of a human-approved workflow task.
Work only in the assigned execution workspace. Its owner workspace is not your working directory.
Do not rebase, merge, integrate other tasks, or change workflow plans or human gates.
Commit the task changes and required artifacts in this attempt before reporting success.
Report activity with `alera orchestration heartbeat --phase <phase>`.
If blocked, use `alera orchestration escalate --subject <subject> --body <details>` and stop for human review.
Report completion exactly once with `alera orchestration complete --summary <summary> --completion-kind success --artifacts '<json array>' --validation '<json array>'`.
Successful completion only makes this result ready for local integration; it does not approve a gate.
After completion, return to an idle prompt. Do not poll, start another task, or modify the committed result.
The runtime will retain this worktree and use a fresh worktree for any retry."#;

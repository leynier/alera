use alera_core::runtime::OrchestrationDispatchContext;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::orchestration_validation::state_error;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn complete_dispatch_result(
        &self,
        dispatch: &OrchestrationDispatchContext,
        assignee: &str,
        result: &str,
    ) -> HostResult<OrchestrationDispatchContext> {
        let Some(completion_sha) = self.workflow_completion_sha(dispatch).await? else {
            return self
                .runtime_store
                .complete_orchestration_dispatch(&dispatch.id, assignee, result)
                .await
                .map_err(state_error);
        };
        self.runtime_store
            .complete_workflow_orchestration_dispatch(
                &dispatch.id,
                assignee,
                result,
                &completion_sha,
            )
            .await
            .map_err(state_error)
    }

    async fn workflow_completion_sha(
        &self,
        dispatch: &OrchestrationDispatchContext,
    ) -> HostResult<Option<String>> {
        if let Some(sha) = dispatch.completion_sha.clone() {
            return Ok(Some(sha));
        }
        let Some(terminal) = dispatch.assignee_handle.as_deref() else {
            return Ok(None);
        };
        let Some(launch) = self
            .runtime_store
            .workflow_launch_for_terminal(terminal)
            .await
            .map_err(state_error)?
        else {
            return Ok(None);
        };
        if launch.dispatch_id != dispatch.id {
            return Err(HostError::state(
                "workflow completion dispatch identity changed",
            ));
        }
        let workspace = self
            .runtime_store
            .workflow_workspace(&launch.request.workspace_id)
            .await
            .map_err(state_error)?;
        if workspace.dispatch_id.as_deref() != Some(dispatch.id.as_str()) {
            return Err(HostError::state(
                "workflow completion workspace identity changed",
            ));
        }
        let repo_path = workspace.identity.repo_path;
        let path = workspace.identity.workspace.path;
        let base_sha = workspace.identity.base_sha;
        let workspace_id = workspace.identity.workspace.id;
        tokio::task::spawn_blocking(move || {
            let sha = alera_core::git::verify_workflow_worktree_tip(
                &repo_path,
                &path,
                &base_sha,
                &workspace_id,
            )
            .map_err(|error| HostError::state(error.to_string()))?;
            if !alera_core::git::is_worktree_clean(&path)
                .map_err(|error| HostError::state(error.to_string()))?
            {
                return Err(HostError::state(
                    "commit or discard pending changes before completing the workflow task",
                ));
            }
            Ok(sha)
        })
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .map(Some)
    }
}

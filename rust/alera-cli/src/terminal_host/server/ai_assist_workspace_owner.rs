use alera_core::runtime::{Workspace, LOCAL_HOST_ID};

use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(super) async fn resolve_ai_assist_workspace(
        &self,
        workspace_id: Option<String>,
        tab_id: Option<String>,
    ) -> HostResult<Workspace> {
        let tab_workspace = if let Some(tab_id) = tab_id {
            Some(
                self.runtime_store
                    .find_workspace_tab(&tab_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| HostError::state(format!("Workspace tab not found: {tab_id}")))?
                    .workspace_id,
            )
        } else {
            None
        };
        if let (Some(requested), Some(actual)) = (&workspace_id, &tab_workspace) {
            if requested != actual {
                return Err(HostError::state(
                    "The tab belongs to a different workspace.",
                ));
            }
        }
        let id = workspace_id
            .or(tab_workspace)
            .ok_or_else(|| HostError::format("workspaceId or tabId is required."))?;
        let workspace = self
            .runtime_store
            .find_workspace(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace not found: {id}")))?;
        if workspace.host_id != LOCAL_HOST_ID {
            return Err(HostError::state("AI Assist must run on the workspace's owning host. Remote speech processing is not available yet."));
        }
        if self
            .mutation_queue
            .pending_workspace_shutdowns
            .contains_key(&id)
            || self.checkout_buffer_guards.values().any(|guard| {
                guard.workspace_id == id
                    || (guard.host_id == workspace.host_id
                        && (guard.scope.workspace_paths.iter().any(|path| {
                            alera_core::runtime::relocated_workspace_path(
                                &workspace.path,
                                path,
                                path,
                            )
                            .is_some()
                        }) || (guard.project_id == workspace.project_id
                            && matches!(guard.operation.as_str(), "handOff" | "handOn"))))
            })
        {
            return Err(HostError::state(
                "Wait for the workspace operation to finish before starting AI Assist.",
            ));
        }
        if self
            .runtime_store
            .pending_workspace_checkout_relocation(&workspace.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .is_some()
        {
            return Err(HostError::state(
                "Finish or recover the workspace relocation before starting AI Assist.",
            ));
        }
        Ok(workspace)
    }
}

use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceArchiveRequest {
    workspace_id: String,
}

impl ServerActor {
    pub(super) async fn handle_workspace_unarchive(
        &self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        let request: WorkspaceArchiveRequest = serde_json::from_value(payload.clone())
            .map_err(|error| HostError::format(error.to_string()))?;
        let workspace = self
            .runtime_store
            .set_workspace_archived(&request.workspace_id, false)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let project_id = workspace.project_id.clone();
        let value = serde_json::to_value(workspace)
            .map_err(|error| HostError::format(error.to_string()))?;
        self.broadcast_workspaces_changed(Some(&project_id));
        Ok(value)
    }
}

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::ServerActor;

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspacePinnedRequest {
    id: String,
    is_pinned: bool,
}

impl ServerActor {
    pub(super) async fn handle_workspace_pinning(
        &self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        let request: WorkspacePinnedRequest = serde_json::from_value(payload.clone())
            .map_err(|error| HostError::format(error.to_string()))?;
        let workspace = self
            .runtime_store
            .set_workspace_pinned(&request.id, request.is_pinned)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let value = serde_json::to_value(workspace)
            .map_err(|error| HostError::format(error.to_string()))?;
        self.broadcast_authenticated(event("workspacesChanged", json!({})));
        Ok(value)
    }
}

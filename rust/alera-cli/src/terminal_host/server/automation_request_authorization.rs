use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_gateway_surface::mobile_request_allowed;
use super::{ClientKind, ServerActor};

impl ServerActor {
    pub(super) fn require_request_allowed(
        &self,
        client_id: u64,
        request_type: &str,
    ) -> HostResult<()> {
        let Some(client) = self.clients.get(&client_id) else {
            return Err(HostError::state(
                "Terminal host client is not authenticated.",
            ));
        };
        if !client.authenticated {
            return Err(HostError::state(
                "Terminal host client is not authenticated.",
            ));
        }
        if client.chat_orchestration_binding.is_some()
            && !matches!(
                request_type,
                request if request.starts_with("chatOrchestration.")
                    || request == "project.list"
                    || request == "workspace.list"
                    || request == "status.get"
            )
        {
            return Err(HostError::conflict(
                "chat_scope_denied",
                "A chat-bound connection may only call chat orchestration and read-only host discovery requests.",
                serde_json::json!({}),
            ));
        }
        if client.kind == ClientKind::Local || mobile_request_allowed(request_type) {
            return Ok(());
        }
        Err(HostError::state(format!(
            "Mobile clients cannot call terminal host request: {request_type}"
        )))
    }
}

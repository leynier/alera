use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_terminal_requests::mobile_request_allowed;
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
        if client.kind == ClientKind::Local || mobile_request_allowed(request_type) {
            return Ok(());
        }
        Err(HostError::state(format!(
            "Mobile clients cannot call terminal host request: {request_type}"
        )))
    }
}

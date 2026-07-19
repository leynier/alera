use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::decode_bytes;
use crate::terminal_host::session::PtyWriteCompletion;

use super::ClientKind;
use super::ServerActor;

impl ServerActor {
    pub(super) fn queue_terminal_input(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<bool> {
        let session_id = self.require_session(payload)?;
        let bytes = decode_bytes(payload.get("dataBase64"))?;
        if bytes.is_empty() {
            return Ok(false);
        }
        let session = self
            .sessions
            .get_mut(&session_id)
            .ok_or_else(|| HostError::state("Terminal session is not attached."))?;
        session.queue_write(
            PtyWriteCompletion::ClientRequest {
                client_id,
                request_id,
            },
            &bytes,
        )?;
        // Typing from the phone claims the driver seat (most recent actor
        // wins) without changing the current viewport.
        let is_mobile = self
            .clients
            .get(&client_id)
            .is_some_and(|client| client.kind == ClientKind::Mobile);
        if is_mobile {
            self.claim_mobile_driver(client_id, &session_id, None);
        }
        Ok(true)
    }
}

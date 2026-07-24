use serde_json::Value;
use std::time::Duration;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::decode_bytes;
use crate::terminal_host::session::PtyWriteCompletion;

use super::ClientKind;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn finish_terminal_client_write(
        &mut self,
        session_id: &str,
        client_id: u64,
        request_id: i64,
        error: Option<String>,
    ) {
        if let Some(message) = error {
            self.client_write(
                client_id,
                crate::terminal_host::protocol::error_response(
                    request_id,
                    &HostError::state(message),
                ),
            );
            return;
        }
        self.client_write(
            client_id,
            crate::terminal_host::protocol::ok_response(request_id, serde_json::json!({})),
        );
        self.retry_backpressured_delivery_if_idle(session_id).await;
    }

    pub(super) fn queue_terminal_input(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<bool> {
        let session_id = self.require_session(payload)?;
        let mut bytes = decode_bytes(payload.get("dataBase64"))?;
        let deferred_enter = payload
            .get("deferredEnter")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let enter_only = bytes.is_empty() && deferred_enter;
        if bytes.is_empty() && !deferred_enter {
            return Ok(false);
        }
        if enter_only {
            bytes.extend_from_slice(
                crate::terminal_host::orchestration::agent_prompt_injection::AGENT_PROMPT_SUBMIT,
            );
        } else if payload
            .get("bracketedPaste")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            bytes = crate::terminal_host::orchestration::agent_prompt_injection::build_agent_prompt_paste_bytes(
                &String::from_utf8_lossy(&bytes),
            );
        }
        let session = self
            .sessions
            .get_mut(&session_id)
            .ok_or_else(|| HostError::state("Terminal session is not attached."))?;
        let completion = PtyWriteCompletion::ClientRequest {
            client_id,
            request_id,
        };
        if deferred_enter && !enter_only {
            session.queue_write_deferred(
                completion,
                &bytes,
                Duration::from_millis(
                    crate::terminal_host::orchestration::message_delivery::DEFERRED_ENTER_DELAY_MS,
                ),
                crate::terminal_host::orchestration::agent_prompt_injection::AGENT_PROMPT_SUBMIT,
            )?;
        } else {
            session.queue_write(completion, &bytes)?;
        }
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

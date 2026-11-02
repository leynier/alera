//! `agentChat.secret.provide` (`agentChatSecretRequestsV1`): a person answers
//! a chat's masked secret card. The value goes to the chat orchestration
//! secret broker, never to the chat actor.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::agent_chat_runtime::commands::CallerCtx;
use super::ServerActor;

pub(super) const SECRET_PROVIDE_VERB: &str = "agentChat.secret.provide";

/// Expired refs and files are deleted at most this often.
const SWEEP_INTERVAL: std::time::Duration = std::time::Duration::from_secs(10 * 60);

impl ServerActor {
    fn secret_service(&self) -> HostResult<super::chat_orchestration::ChatOrchestrationService> {
        self.chat_orchestration.clone().ok_or_else(|| {
            HostError::conflict(
                "unsupported",
                "Secret requests are unavailable on this host.",
                json!({}),
            )
        })
    }

    /// Starts `agentChat.secret.provide` off the actor; `false` for any
    /// other verb.
    pub(super) fn try_start_secret_provide(
        &self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
        ctx: CallerCtx,
    ) -> HostResult<bool> {
        if request_type != SECRET_PROVIDE_VERB {
            return Ok(false);
        }
        let service = self.secret_service()?;
        let payload = payload.clone();
        self.spawn_agent_chat_request(client_id, request_id, async move {
            service.provide_secret(&payload, ctx).await
        });
        Ok(true)
    }

    pub(super) async fn provide_secret_inline(
        &self,
        payload: &Value,
        ctx: CallerCtx,
    ) -> HostResult<Value> {
        self.secret_service()?.provide_secret(payload, ctx).await
    }

    pub(super) fn sweep_chat_secrets(&mut self) {
        let due = self
            .pull_request_watches
            .secrets_swept
            .is_none_or(|swept| swept.elapsed() >= SWEEP_INTERVAL);
        let Some(service) = self.chat_orchestration.clone().filter(|_| due) else {
            return;
        };
        self.pull_request_watches.secrets_swept = Some(std::time::Instant::now());
        tokio::spawn(async move { service.sweep_secrets().await });
    }
}

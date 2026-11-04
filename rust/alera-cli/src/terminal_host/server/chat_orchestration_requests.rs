use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::agent_chat_runtime::commands::CallerCtx;
use super::chat_orchestration::OrchestrationCaller;
use super::{ClientKind, ServerActor};

impl ServerActor {
    pub(super) async fn try_start_local_chat_orchestration_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !request_type.starts_with("chatOrchestration.") {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        if self
            .try_forward_to_hub(client_id, request_id, request_type, payload)
            .await?
        {
            return Ok(true);
        }
        let service = self.chat_orchestration.clone().ok_or_else(|| {
            HostError::conflict(
                "unsupported",
                "Chat orchestration is unavailable.",
                json!({}),
            )
        })?;
        let verb = request_type
            .strip_prefix("chatOrchestration.")
            .ok_or_else(|| HostError::format("invalid chat orchestration request"))?
            .to_owned();
        let payload = payload.clone();
        let caller = self.chat_orchestration_caller(client_id);
        self.spawn_agent_chat_request(client_id, request_id, async move {
            service.handle(&verb, &payload, &caller).await
        });
        Ok(true)
    }

    pub(crate) fn chat_orchestration_binding(
        &self,
        client_id: u64,
    ) -> Option<super::chat_orchestration::BoundChat> {
        self.clients
            .get(&client_id)
            .and_then(|client| client.chat_orchestration_binding.clone())
    }

    pub(super) async fn handle_chat_orchestration_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        let verb = request_type
            .strip_prefix("chatOrchestration.")
            .ok_or_else(|| HostError::format("invalid chat orchestration request"))?;
        let service = self.chat_orchestration.clone().ok_or_else(|| {
            HostError::conflict(
                "unsupported",
                "Chat orchestration is unavailable.",
                json!({}),
            )
        })?;
        service
            .handle(verb, payload, &self.chat_orchestration_caller(client_id))
            .await
    }

    pub(super) fn chat_orchestration_caller(&self, client_id: u64) -> OrchestrationCaller {
        let ctx = self.agent_chat_caller(client_id);
        self.chat_orchestration_binding(client_id)
            .map(|binding| {
                OrchestrationCaller::agent(
                    CallerCtx {
                        scope: format!("chat:{}", binding.chat_id),
                        actor: format!("agent:{}", binding.chat_id),
                        mobile: matches!(
                            self.clients.get(&client_id).map(|client| client.kind),
                            Some(ClientKind::Mobile)
                        ),
                    },
                    binding,
                )
            })
            .unwrap_or_else(|| OrchestrationCaller::human(ctx))
    }
}

#[cfg(test)]
#[path = "chat_orchestration_routing_tests.rs"]
mod routing_tests;

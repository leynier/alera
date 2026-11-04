use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::agent_chat_provider_settings::ProviderSettingsService;
use super::agent_chat_runtime::CallerCtx;
use super::ServerActor;

impl ServerActor {
    pub(super) fn start_provider_settings_request(
        &self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
        caller: CallerCtx,
    ) -> HostResult<bool> {
        if !ProviderSettingsService::handles(verb) {
            return Ok(false);
        }
        let service = self.agent_chat_provider_settings.clone().ok_or_else(|| {
            HostError::conflict(
                "unsupported",
                "Provider settings are unavailable.",
                json!({}),
            )
        })?;
        let verb = verb.to_owned();
        let payload = payload.clone();
        self.spawn_agent_chat_request(client_id, request_id, async move {
            service.dispatch(&verb, &payload, &caller).await
        });
        Ok(true)
    }
}

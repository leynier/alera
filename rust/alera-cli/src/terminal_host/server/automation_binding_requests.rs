use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::requests::require_string_key;
use super::ServerActor;

impl ServerActor {
    /// `automation.unbind {id, reason?}`: forgets where a reusing automation
    /// delivers, so its next run creates a new target and binds to that.
    pub(super) async fn automation_unbind_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.resolve_request_actor(client_id, payload, self.automation_actor(client_id))
            .await?;
        let id = require_string_key(payload, "id")?;
        let reason = payload
            .get("reason")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|reason| !reason.is_empty())
            .unwrap_or("unbound");
        self.runtime_store
            .find_automation(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation not found: {id}")))?;
        if self
            .runtime_store
            .clear_automation_bound_target(&id, reason)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            self.broadcast_automation_changed(Some(&id));
        }
        let definition = self
            .runtime_store
            .find_automation(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation not found: {id}")))?;
        self.automation_catalog_item(&definition).await
    }
}

//! Verbs for the catalogs the user declares by hand: agent profiles and SSH
//! targets. Both are configuration rather than run state, both are edited from
//! Settings, and both broadcast a change event the app watches.

use alera_core::runtime::{AgentProfile, SshTarget};
use chrono::Utc;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::{adapter_for, AGENT_ADAPTERS};
use crate::terminal_host::protocol::event;

use super::requests::require_string_key;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn ssh_target_list(&mut self) -> HostResult<Value> {
        let targets = self
            .runtime_store
            .list_ssh_targets()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        serde_json::to_value(targets).map_err(|error| HostError::format(error.to_string()))
    }

    pub(super) async fn ssh_target_upsert(&mut self, payload: &Value) -> HostResult<Value> {
        let mut target: SshTarget = serde_json::from_value(payload.clone())
            .map_err(|error| HostError::format(error.to_string()))?;
        // An omitted installDir means "leave it alone", not "clear it": the app
        // only sends it when the user edited the bootstrap location.
        if payload.get("installDir").is_none() {
            if let Some(existing) = self
                .runtime_store
                .find_ssh_target(&target.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                target.install_dir = existing.install_dir;
            }
        }
        let stored = self
            .runtime_store
            .upsert_ssh_target(target)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let value =
            serde_json::to_value(stored).map_err(|error| HostError::format(error.to_string()))?;
        self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
        Ok(value)
    }

    pub(super) async fn ssh_target_remove(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string_key(payload, "id")?;
        self.cancel_ssh_bootstrap_job_before_remove(&id).await?;
        self.runtime_store
            .remove_ssh_target(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
        Ok(json!({}))
    }

    pub(super) async fn agent_profile_list(&mut self) -> HostResult<Value> {
        let profiles = self
            .runtime_store
            .list_agent_profiles()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let items =
            serde_json::to_value(profiles).map_err(|error| HostError::format(error.to_string()))?;
        Ok(json!({ "kind": "agentProfiles", "items": items, "filters": {} }))
    }

    pub(super) async fn agent_profile_upsert(&mut self, payload: &Value) -> HostResult<Value> {
        let profile = profile_from_payload(payload)?;
        let stored = self
            .runtime_store
            .upsert_agent_profile(profile)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let value =
            serde_json::to_value(stored).map_err(|error| HostError::format(error.to_string()))?;
        self.broadcast_authenticated(event("agentProfilesChanged", json!({})));
        Ok(value)
    }

    pub(super) async fn agent_profile_remove(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_profile_string(payload, "id")?;
        let removed = self
            .runtime_store
            .remove_agent_profile(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if removed {
            self.broadcast_authenticated(event("agentProfilesChanged", json!({})));
        }
        Ok(json!({ "removed": removed }))
    }
}

fn profile_from_payload(payload: &Value) -> HostResult<AgentProfile> {
    let agent_type = require_profile_string(payload, "agentType")?;
    // The store cannot validate this: alera-core does not know the adapter
    // registry. A profile pointing at an unknown adapter would spawn a worker
    // the host has no way to make ready.
    if adapter_for(&agent_type).is_none() {
        let supported = AGENT_ADAPTERS
            .iter()
            .map(|adapter| adapter.agent_type)
            .collect::<Vec<_>>()
            .join(", ");
        return Err(HostError::format(format!(
            "unsupported agent type: {agent_type}. Supported adapters: {supported}."
        )));
    }
    let now = Utc::now();
    let id = optional_profile_string(payload, "id")
        .unwrap_or_else(|| format!("prof_{}", Uuid::new_v4().simple()));
    Ok(AgentProfile {
        id,
        name: require_profile_string(payload, "name")?,
        agent_type,
        command: require_profile_string(payload, "command")?,
        description: optional_profile_string(payload, "description").unwrap_or_default(),
        quota_group: optional_profile_string(payload, "quotaGroup"),
        created_at: now,
        updated_at: now,
    })
}

fn require_profile_string(payload: &Value, key: &str) -> HostResult<String> {
    optional_profile_string(payload, key)
        .ok_or_else(|| HostError::format(format!("{key} is required.")))
}

fn optional_profile_string(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

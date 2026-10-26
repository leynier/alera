//! Verbs for the catalogs the user declares by hand: agent profiles and SSH
//! targets. Both are configuration rather than run state, both are edited from
//! Settings, and both broadcast a change event the app watches.

use std::collections::HashMap;

use alera_core::runtime::{AgentProfile, AgentProfileLaunchMode, RuntimeStoreError, SshTarget};
use chrono::Utc;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::ssh_bootstrap::reject_new_password_ssh_target;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::{adapter_for, AGENT_ADAPTERS};
use crate::terminal_host::orchestration::managed_agent_launch::build_managed_agent_launch;
use crate::terminal_host::orchestration::managed_launch_shell_rendering::managed_launch_preview;
use crate::terminal_host::protocol::event;

use super::ServerActor;

impl ServerActor {
    pub(super) async fn ssh_target_upsert(&mut self, payload: &Value) -> HostResult<Value> {
        let mut target: SshTarget = serde_json::from_value(payload.clone())
            .map_err(|error| HostError::format(error.to_string()))?;
        let existing = self
            .runtime_store
            .find_ssh_target(&target.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        reject_new_password_ssh_target(
            target.auth_kind,
            existing.as_ref().map(|existing| existing.auth_kind),
        )
        .map_err(|error| HostError::state(error.to_string()))?;
        keep_server_owned_fields(&mut target, existing.as_ref(), payload);
        let endpoint_changed = existing
            .as_ref()
            .is_some_and(|existing| ssh_endpoint_changed(existing, &target));
        let stored = self
            .runtime_store
            .upsert_ssh_target(target)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let host_id = stored.id.clone();
        let value = self.ssh_target_value(&stored)?;
        if endpoint_changed {
            // A link to the old address is stale, and a pause or a failure
            // recorded against it no longer describes the host.
            let links = self.host_links.clone();
            let changed = host_id.clone();
            tokio::spawn(async move { links.target_changed(&changed).await });
        }
        self.broadcast_ssh_targets_changed(Some(&host_id));
        Ok(value)
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
        let is_update = optional_profile_string(payload, "id").is_some();
        let expected_revision = if is_update {
            Some(required_revision(payload, "expectedRevision")?)
        } else {
            optional_revision(payload, "expectedRevision")?
        };
        let profile = profile_from_payload(payload)?;
        let stored = self
            .runtime_store
            .upsert_agent_profile(profile, expected_revision)
            .await
            .map_err(agent_profile_store_error)?;
        let value =
            serde_json::to_value(stored).map_err(|error| HostError::format(error.to_string()))?;
        self.broadcast_authenticated(event("agentProfilesChanged", json!({})));
        Ok(value)
    }

    pub(super) async fn agent_profile_reorder(&mut self, payload: &Value) -> HostResult<Value> {
        let raw_ids = payload
            .get("ids")
            .and_then(Value::as_array)
            .ok_or_else(|| HostError::format("ids must be a JSON array."))?;
        let profile_ids = raw_ids
            .iter()
            .map(|value| {
                value
                    .as_str()
                    .map(str::trim)
                    .filter(|id| !id.is_empty())
                    .map(str::to_string)
                    .ok_or_else(|| HostError::format("ids must contain profile IDs."))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let expected_revisions = payload
            .get("expectedRevisions")
            .and_then(Value::as_object)
            .ok_or_else(|| HostError::format("expectedRevisions must be a JSON object."))?
            .iter()
            .map(|(id, value)| {
                let revision = value
                    .as_i64()
                    .filter(|revision| *revision >= 0)
                    .ok_or_else(|| {
                        HostError::format("expectedRevisions must contain non-negative integers.")
                    })?;
                Ok((id.clone(), revision))
            })
            .collect::<HostResult<HashMap<_, _>>>()?;
        let profiles = self
            .runtime_store
            .reorder_agent_profiles(&profile_ids, &expected_revisions)
            .await
            .map_err(agent_profile_store_error)?;
        let items =
            serde_json::to_value(profiles).map_err(|error| HostError::format(error.to_string()))?;
        self.broadcast_authenticated(event("agentProfilesChanged", json!({})));
        Ok(json!({
            "kind": "agentProfiles",
            "items": items,
            "filters": {}
        }))
    }

    pub(super) async fn agent_profile_removal_impact(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let id = require_profile_string(payload, "id")?;
        let expected_revision = required_revision(payload, "expectedRevision")?;
        let impact = self
            .runtime_store
            .agent_profile_removal_impact(&id, expected_revision)
            .await
            .map_err(agent_profile_store_error)?;
        let reference_count = impact.reference_count();
        let blocking_reference_count =
            impact.automation_ids.len() + impact.execution_policy_run_ids.len() + impact.tabs.len();
        let mut value =
            serde_json::to_value(impact).map_err(|error| HostError::format(error.to_string()))?;
        let object = value
            .as_object_mut()
            .ok_or_else(|| HostError::format("Agent profile removal impact must be an object."))?;
        object.insert("referenceCount".into(), json!(reference_count));
        object.insert(
            "blockingReferenceCount".into(),
            json!(blocking_reference_count),
        );
        Ok(value)
    }

    pub(super) async fn agent_profile_remove(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_profile_string(payload, "id")?;
        let expected_revision = required_revision(payload, "expectedRevision")?;
        if payload.get("confirmed").and_then(Value::as_bool) != Some(true) {
            return Err(HostError::format(
                "Agent profile removal requires explicit confirmation.",
            ));
        }
        let removed = self
            .runtime_store
            .remove_agent_profile(&id, expected_revision)
            .await
            .map_err(agent_profile_store_error)?;
        if removed {
            self.broadcast_authenticated(event("agentProfilesChanged", json!({})));
            self.broadcast_authenticated(event("runtimeSettingsChanged", json!({})));
            self.broadcast_automation_changed(None);
        }
        Ok(json!({ "removed": removed }))
    }
}

pub(super) fn profile_from_payload(payload: &Value) -> HostResult<AgentProfile> {
    let agent_type = require_profile_string(payload, "agentType")?;
    let agent_type = alera_core::runtime::canonical_agent_type(&agent_type).to_string();
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
    let launch_mode = optional_profile_string(payload, "launchMode")
        .unwrap_or_else(|| "command".to_string())
        .parse::<AgentProfileLaunchMode>()
        .map_err(HostError::format)?;
    let (command, managed_config) = match launch_mode {
        AgentProfileLaunchMode::Command => (require_profile_string(payload, "command")?, None),
        AgentProfileLaunchMode::Managed => {
            let config = payload
                .get("managedConfig")
                .cloned()
                .unwrap_or_else(|| json!({}));
            let launch =
                build_managed_agent_launch(&agent_type, &config).map_err(HostError::format)?;
            (managed_launch_preview(&launch), Some(config))
        }
    };
    Ok(AgentProfile {
        id,
        name: require_profile_string(payload, "name")?,
        sort_order: 0,
        agent_type,
        command,
        launch_mode,
        managed_config,
        custom_prompt: optional_profile_string(payload, "customPrompt").unwrap_or_default(),
        description: optional_profile_string(payload, "description").unwrap_or_default(),
        quota_group: optional_profile_string(payload, "quotaGroup"),
        show_in_new_tab_menu: optional_profile_bool(payload, "showInNewTabMenu")?,
        revision: 0,
        created_at: now,
        updated_at: now,
    })
}

fn required_revision(payload: &Value, key: &str) -> HostResult<i64> {
    optional_revision(payload, key)?.ok_or_else(|| HostError::format(format!("{key} is required.")))
}

fn optional_revision(payload: &Value, key: &str) -> HostResult<Option<i64>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_i64()
            .filter(|revision| *revision >= 0)
            .map(Some)
            .ok_or_else(|| HostError::format(format!("{key} must be a non-negative integer."))),
    }
}

fn agent_profile_store_error(error: anyhow::Error) -> HostError {
    if let Some(RuntimeStoreError::AgentProfileRevisionConflict {
        profile_id,
        expected,
        current,
    }) = error.downcast_ref::<RuntimeStoreError>()
    {
        return HostError::conflict(
            "agent_profile_revision_conflict",
            error.to_string(),
            json!({
                "profileId": profile_id,
                "expectedRevision": expected,
                "currentRevision": current,
            }),
        );
    }
    HostError::state(error.to_string())
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

fn optional_profile_bool(payload: &Value, key: &str) -> HostResult<bool> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(false),
        Some(value) => value
            .as_bool()
            .ok_or_else(|| HostError::format(format!("{key} must be a boolean."))),
    }
}

#[cfg(test)]
mod tests {
    use alera_core::runtime::AgentProfileLaunchMode;
    use serde_json::json;

    use super::profile_from_payload;

    #[test]
    fn legacy_profile_payload_defaults_to_command_mode() {
        let profile = profile_from_payload(&json!({
            "name": "Codex",
            "agentType": "codex",
            "command": "codex --search"
        }))
        .unwrap();

        assert_eq!(profile.launch_mode, AgentProfileLaunchMode::Command);
        assert_eq!(profile.command, "codex --search");
        assert_eq!(profile.managed_config, None);
        assert_eq!(profile.custom_prompt, "");
        assert!(!profile.show_in_new_tab_menu);
    }

    #[test]
    fn profile_payload_reads_the_new_tab_menu_opt_in() {
        let profile = profile_from_payload(&json!({
            "name": "Codex",
            "agentType": "codex",
            "command": "codex --search",
            "showInNewTabMenu": true
        }))
        .unwrap();

        assert!(profile.show_in_new_tab_menu);
    }

    #[test]
    fn profile_payload_trims_custom_prompt() {
        let profile = profile_from_payload(&json!({
            "name": "Codex",
            "agentType": "codex",
            "command": "codex --search",
            "customPrompt": "  Keep The Changes Focused  "
        }))
        .unwrap();

        assert_eq!(profile.custom_prompt, "Keep The Changes Focused");
    }

    #[test]
    fn managed_profile_payload_builds_a_command_preview() {
        let profile = profile_from_payload(&json!({
            "name": "Codex",
            "agentType": "codex",
            "launchMode": "managed",
            "managedConfig": {
                "model": "gpt-5.6-sol",
                "webSearch": true
            }
        }))
        .unwrap();

        assert_eq!(profile.launch_mode, AgentProfileLaunchMode::Managed);
        assert!(profile.command.contains("--model"));
        assert!(profile.command.contains("gpt-5.6-sol"));
        assert!(profile.command.contains("--search"));
    }

    #[test]
    fn managed_profile_payload_rejects_unknown_options() {
        let error = profile_from_payload(&json!({
            "name": "Codex",
            "agentType": "codex",
            "launchMode": "managed",
            "managedConfig": {"unknown": true}
        }))
        .unwrap_err();

        assert!(error
            .to_string()
            .contains("unsupported managed agent option"));
    }
}

/// What the hub owns on a target: the install record, the last probe and
/// what the runtime reported. A client sends the whole record back on every
/// edit, so for an existing target these come from the stored row, never
/// from the payload.
fn keep_server_owned_fields(target: &mut SshTarget, existing: Option<&SshTarget>, payload: &Value) {
    let Some(stored) = existing.cloned() else {
        return;
    };
    target.last_status = stored.last_status;
    target.runtime_version = stored.runtime_version;
    target.runtime_platform = stored.runtime_platform;
    target.runtime_arch = stored.runtime_arch;
    target.bootstrap_status = stored.bootstrap_status;
    target.last_bootstrap_at = stored.last_bootstrap_at;
    target.last_checked_at = stored.last_checked_at;
    target.last_error = stored.last_error;
    target.created_at = stored.created_at;
    // An omitted field means "leave it alone", not "clear it": older apps
    // only send installDir when the user edited the bootstrap location, and
    // know nothing of identityFile.
    if payload.get("installDir").is_none() {
        target.install_dir = stored.install_dir;
    }
    if payload.get("identityFile").is_none() {
        target.identity_file = stored.identity_file;
    }
}

/// Whether an edit changes how the hub reaches the host. A new alias or
/// projects folder does not.
fn ssh_endpoint_changed(existing: &SshTarget, next: &SshTarget) -> bool {
    existing.host != next.host
        || existing.port != next.port
        || existing.username != next.username
        || existing.auth_kind != next.auth_kind
        || existing.install_dir != next.install_dir
        || existing.identity_file != next.identity_file
}

#[cfg(test)]
mod ssh_target_upsert_tests {
    use super::*;

    #[test]
    fn only_reaching_the_host_differently_changes_its_endpoint() {
        let target: SshTarget = serde_json::from_value(serde_json::json!({
            "id": "ssh-1", "alias": "Lab", "host": "10.0.0.7", "port": 22,
            "username": "dev", "authKind": "agent",
            "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
        }))
        .unwrap();
        let mut renamed = target.clone();
        renamed.alias = "Studio".into();
        renamed.projects_dir = Some("~/code".into());
        assert!(!ssh_endpoint_changed(&target, &renamed));
        let mut moved = target.clone();
        moved.host = "10.0.0.8".into();
        assert!(ssh_endpoint_changed(&target, &moved));
        let mut port = target.clone();
        port.port = 2222;
        assert!(ssh_endpoint_changed(&target, &port));
    }

    fn stored_target() -> SshTarget {
        serde_json::from_value(serde_json::json!({
            "id": "ssh-1", "alias": "Lab", "host": "10.0.0.7", "port": 22,
            "username": "dev", "authKind": "agent", "lastStatus": "runtimeReady",
            "installDir": "~/.alera", "identityFile": "~/.ssh/lab", "runtimeVersion": "1.4.0",
            "runtimePlatform": "linux", "runtimeArch": "x64", "bootstrapStatus": "installed",
            "lastCheckedAt": "2026-07-20T00:00:00Z", "lastError": "old failure",
            "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
        }))
        .unwrap()
    }

    #[test]
    fn an_upsert_cannot_overwrite_what_the_hub_owns() {
        let existing = stored_target();
        let payload = serde_json::json!({
            "id": "ssh-1", "alias": "Studio", "host": "10.0.0.7", "port": 22,
            "username": "dev", "authKind": "agent", "lastStatus": "unreachable",
            "runtimeVersion": "0.0.1", "bootstrapStatus": "notInstalled",
            "lastError": null, "lastCheckedAt": null,
            "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z",
        });
        let mut target: SshTarget = serde_json::from_value(payload.clone()).unwrap();
        keep_server_owned_fields(&mut target, Some(&existing), &payload);
        assert_eq!(target.alias, "Studio");
        assert_eq!(target.last_status.as_deref(), Some("runtimeReady"));
        assert_eq!(target.runtime_version.as_deref(), Some("1.4.0"));
        assert_eq!(target.bootstrap_status, existing.bootstrap_status);
        assert_eq!(target.last_checked_at, existing.last_checked_at);
        assert_eq!(target.last_error.as_deref(), Some("old failure"));
        assert_eq!(target.created_at, existing.created_at);
        assert_eq!(target.install_dir.as_deref(), Some("~/.alera"));
        assert_eq!(target.identity_file.as_deref(), Some("~/.ssh/lab"));
        assert!(!ssh_endpoint_changed(&existing, &target));

        let mut fresh: SshTarget = serde_json::from_value(payload.clone()).unwrap();
        keep_server_owned_fields(&mut fresh, None, &payload);
        assert_eq!(
            fresh.runtime_version.as_deref(),
            Some("0.0.1"),
            "a new target has nothing stored to keep"
        );
    }

    #[test]
    fn a_new_identity_file_changes_the_endpoint() {
        let existing = stored_target();
        let payload = serde_json::json!({
            "id": "ssh-1", "alias": "Lab", "host": "10.0.0.7", "port": 22,
            "username": "dev", "authKind": "key", "identityFile": null,
            "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
        });
        let mut target: SshTarget = serde_json::from_value(payload.clone()).unwrap();
        keep_server_owned_fields(&mut target, Some(&existing), &payload);
        assert_eq!(target.identity_file, None, "an explicit null clears it");
        assert!(ssh_endpoint_changed(&existing, &target));
    }
}

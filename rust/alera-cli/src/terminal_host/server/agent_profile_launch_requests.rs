use alera_core::runtime::{AgentProfileLaunchReceiptOutcome, WorkspaceStatus, WorkspaceTabRecord};
use serde_json::{json, Value};
use sha2::{Digest as _, Sha256};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::{
    AgentInitialDeliveryMechanismV1, AgentInitialDeliveryReplayV1, AgentProfileLaunchSnapshotV1,
    AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY,
};
use crate::terminal_host::orchestration::agent_registry::adapter_for;

use super::agent_prompt_composition::compose_agent_prompt;
use super::client_delivery::LocalClientRole;
use super::host_service_requests::required_non_blank;
use super::orchestration_profile_spawn::launch_for_profile;
use super::tab_compatibility::redact_private_tab_payload;
use super::{ClientKind, ServerActor};

const CLIENT_MUTATION_ID_MAX_BYTES: usize = 128;

impl ServerActor {
    pub(super) async fn launch_agent_profile(
        &mut self,
        client_id: Option<u64>,
        payload: &Value,
    ) -> HostResult<Value> {
        let workspace_id = required_non_blank(payload, "workspaceId")?;
        let profile_id = required_non_blank(payload, "profileId")?;
        let prompt = required_non_blank(payload, "prompt")?;
        let client_mutation_id = match payload.get("clientMutationId") {
            None => None,
            Some(Value::String(value)) if !value.trim().is_empty() => {
                Some(value.trim().to_string())
            }
            Some(_) => {
                return Err(HostError::format(
                    "clientMutationId must be a non-empty string.",
                ));
            }
        };
        if client_mutation_id
            .as_ref()
            .is_some_and(|value| value.len() > CLIENT_MUTATION_ID_MAX_BYTES)
        {
            return Err(HostError::format(format!(
                "clientMutationId must not exceed {CLIENT_MUTATION_ID_MAX_BYTES} bytes."
            )));
        }
        let caller_scope = client_mutation_id
            .as_ref()
            .map(|_| {
                client_id
                    .ok_or_else(|| {
                        HostError::state(
                            "clientMutationId requires an authenticated client identity.",
                        )
                    })
                    .and_then(|client_id| self.agent_profile_launch_caller_scope(client_id))
            })
            .transpose()?;
        let automation_run_id = payload
            .get("automationRunId")
            .and_then(Value::as_str)
            .map(str::to_string);
        let automation_owned = payload
            .get("automationOwned")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let payload_digest = client_mutation_id.as_ref().map(|_| {
            agent_profile_launch_payload_digest(
                &workspace_id,
                &profile_id,
                &prompt,
                automation_run_id.as_deref(),
                automation_owned,
            )
        });
        if let (Some(mutation_id), Some(scope), Some(digest)) = (
            client_mutation_id.as_deref(),
            caller_scope.as_deref(),
            payload_digest.as_deref(),
        ) {
            match self
                .runtime_store
                .find_agent_profile_launch_receipt(scope, &workspace_id, mutation_id, digest)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                Some(AgentProfileLaunchReceiptOutcome::Replay(result)) => {
                    return Ok(redact_agent_profile_launch_result(result));
                }
                Some(AgentProfileLaunchReceiptOutcome::Conflict) => {
                    return Err(HostError::state(
                        "clientMutationId was already used with a different agentProfile.launch payload.",
                    ));
                }
                Some(AgentProfileLaunchReceiptOutcome::Created) | None => {}
            }
        }
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
        if workspace.status != WorkspaceStatus::Active {
            return Err(HostError::state(format!(
                "Workspace is not active: {workspace_id}"
            )));
        }
        let effective_config = crate::project_management::effective_project_config(
            &self.runtime_store,
            &workspace.project_id,
        )
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
        if let Some(error) = effective_config.error {
            return Err(HostError::state(format!(
                "Could not load project configuration: {error}"
            )));
        }
        let profile = self
            .runtime_store
            .find_agent_profile(&profile_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Agent profile not found: {profile_id}")))?;
        let prompt = compose_agent_prompt(
            &prompt,
            &profile.custom_prompt,
            &effective_config.config.new_workspace.prompt_append,
        );
        let adapter = adapter_for(&profile.agent_type).ok_or_else(|| {
            HostError::format(format!("Unsupported agent type: {}", profile.agent_type))
        })?;
        let (command, managed_launch) = launch_for_profile(&profile).map_err(HostError::format)?;
        let launch_snapshot = AgentProfileLaunchSnapshotV1::new(
            &profile,
            adapter,
            command,
            managed_launch,
            AgentInitialDeliveryReplayV1::Once,
        )
        .map_err(HostError::format)?;
        let prompt_after_ready = launch_snapshot.initial_delivery.mechanism
            == AgentInitialDeliveryMechanismV1::TerminalAfterReady;
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now();
        let mut tab_payload = json!({
            "terminalSessionId": id,
            // Most adapters take the prompt at launch. fx receives it
            // after its built-in lifecycle reports that the TUI is ready.
            "initialPrompt": (!prompt_after_ready).then(|| prompt.clone()),
            "pendingAgentPrompt": prompt_after_ready.then(|| json!({
                "agent": adapter.agent_type,
                "prompt": prompt,
            })),
            "spawnOnCreate": true,
            "automationRunId": automation_run_id,
            "automationOwned": automation_owned,
        });
        tab_payload[AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY] = serde_json::to_value(launch_snapshot)
            .map_err(|error| {
                HostError::state(format!(
                    "could not encode agent profile launch snapshot: {error}"
                ))
            })?;
        let tab = WorkspaceTabRecord {
            id: id.clone(),
            workspace_id: workspace_id.clone(),
            kind: "terminal".to_string(),
            title: profile.name.clone(),
            created_at: now,
            updated_at: now,
            payload: tab_payload,
        };
        let mut projected_tab = tab.clone();
        redact_private_tab_payload(&mut projected_tab);
        let result = json!({
            "tab": projected_tab,
            "agentType": adapter.agent_type,
            "profileId": profile.id,
        });
        let Some(mutation_id) = client_mutation_id.as_deref() else {
            let mut saved = self.upsert_workspace_tab_and_spawn(tab).await?;
            redact_private_tab_payload(&mut saved);
            return Ok(json!({
                "tab": saved,
                "agentType": adapter.agent_type,
                "profileId": profile.id,
            }));
        };
        let scope = caller_scope.expect("mutation caller scope was computed");
        let digest = payload_digest.expect("mutation payload digest was computed");
        match self
            .runtime_store
            .record_agent_profile_launch(&scope, &workspace_id, mutation_id, &digest, &result, &tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            AgentProfileLaunchReceiptOutcome::Replay(result) => {
                return Ok(redact_agent_profile_launch_result(result));
            }
            AgentProfileLaunchReceiptOutcome::Conflict => {
                return Err(HostError::state(
                    "clientMutationId was already used with a different agentProfile.launch payload.",
                ));
            }
            AgentProfileLaunchReceiptOutcome::Created => {}
        }
        if let Err(error) = self.ensure_spawn_on_create_terminal(&tab).await {
            if let Err(cleanup_error) = self.runtime_store.remove_workspace_tab(&tab.id).await {
                tracing::error!(
                    tab_id = %tab.id,
                    "failed to roll back agent profile launch receipt: {cleanup_error}"
                );
            }
            self.terminate_sessions_for_tab(&tab.id).await;
            return Err(error);
        }
        self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        Ok(result)
    }

    fn agent_profile_launch_caller_scope(&self, client_id: u64) -> HostResult<String> {
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| HostError::state("Terminal host client is not authenticated."))?;
        match client.kind {
            ClientKind::Mobile => client
                .mobile_device_id
                .as_ref()
                .map(|device_id| format!("mobile:{device_id}"))
                .ok_or_else(|| {
                    HostError::state("Authenticated mobile device identity is missing.")
                }),
            ClientKind::Local => Ok(match client.local_role {
                LocalClientRole::App => "local:app",
                LocalClientRole::Cli => "local:cli",
            }
            .to_string()),
        }
    }

    /// Types a prompt into an agent that reported it is idle.
    ///
    /// fx has no interactive initial-prompt argument. Its lifecycle receiver
    /// reports the first idle state after the TUI is ready, which makes this
    /// PTY paste deterministic. Older tabs may also still carry the payload.
    pub(super) async fn deliver_pending_agent_prompt(&mut self, session_id: &str) {
        if !self.agent_presence.is_injection_ready(session_id) {
            return;
        }
        let Some(session) = self.sessions.get(session_id) else {
            return;
        };
        if session.initial_agent_prompt_delivered {
            return;
        }
        let tab_id = session.tab_id.clone();
        let instance_id = session.instance_id();
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(&tab_id).await else {
            return;
        };
        let Some(pending) = tab.payload.get("pendingAgentPrompt").cloned() else {
            return;
        };
        let Some(prompt) = pending.get("prompt").and_then(Value::as_str) else {
            return;
        };
        let matches_agent = pending
            .get("agent")
            .and_then(Value::as_str)
            .is_some_and(|agent| self.agent_presence.agent_type(session_id) == Some(agent));
        if !matches_agent {
            return;
        }
        let bytes =
            crate::terminal_host::orchestration::agent_prompt_injection::build_agent_prompt_paste_bytes(
                prompt,
            );
        let Some(session) = self.sessions.get_mut(session_id) else {
            return;
        };
        if session
            .queue_write_deferred(
                crate::terminal_host::session::PtyWriteCompletion::OrchestrationPaste {
                    session_instance_id: instance_id,
                    message_ids: Vec::new(),
                    force_submit: true,
                },
                &bytes,
                std::time::Duration::from_millis(
                    crate::terminal_host::orchestration::message_delivery::DEFERRED_ENTER_DELAY_MS,
                ),
                crate::terminal_host::orchestration::agent_prompt_injection::AGENT_PROMPT_SUBMIT,
            )
            .is_err()
        {
            return;
        }
        session.initial_agent_prompt_delivered = true;
        tab.payload["pendingAgentPrompt"] = Value::Null;
        tab.updated_at = chrono::Utc::now();
        let workspace_id = tab.workspace_id.clone();
        if let Err(error) = self.runtime_store.upsert_workspace_tab(tab).await {
            tracing::error!(tab_id = %tab_id, "failed to clear pending agent prompt: {error}");
        }
        self.broadcast_workspace_tabs_changed(Some(&workspace_id));
    }
}

fn redact_agent_profile_launch_result(mut result: Value) -> Value {
    let Some(tab_value) = result.get_mut("tab") else {
        return result;
    };
    let Ok(mut tab) = serde_json::from_value::<WorkspaceTabRecord>(tab_value.clone()) else {
        return result;
    };
    redact_private_tab_payload(&mut tab);
    *tab_value = json!(tab);
    result
}

fn agent_profile_launch_payload_digest(
    workspace_id: &str,
    profile_id: &str,
    prompt: &str,
    automation_run_id: Option<&str>,
    automation_owned: bool,
) -> String {
    let canonical = json!({
        "automationOwned": automation_owned,
        "automationRunId": automation_run_id,
        "profileId": profile_id,
        "prompt": prompt,
        "workspaceId": workspace_id,
    });
    let bytes = serde_json::to_vec(&canonical).expect("canonical launch payload is serializable");
    hex::encode(Sha256::digest(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payload_digest_uses_the_effective_launch_payload() {
        let first = agent_profile_launch_payload_digest(
            "workspace-1",
            "profile-1",
            "Build it",
            None,
            false,
        );
        assert_eq!(
            first,
            agent_profile_launch_payload_digest(
                "workspace-1",
                "profile-1",
                "Build it",
                None,
                false,
            )
        );
        assert_ne!(
            first,
            agent_profile_launch_payload_digest(
                "workspace-1",
                "profile-1",
                "Build something else",
                None,
                false,
            )
        );
    }
}

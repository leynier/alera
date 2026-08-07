use alera_core::runtime::{WorkspaceStatus, WorkspaceTabRecord};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::adapter_for;

use super::agent_prompt_composition::compose_agent_prompt;
use super::host_service_requests::required_non_blank;
use super::orchestration_profile_spawn::launch_for_profile;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn launch_agent_profile(&mut self, payload: &Value) -> HostResult<Value> {
        let workspace_id = required_non_blank(payload, "workspaceId")?;
        let profile_id = required_non_blank(payload, "profileId")?;
        let prompt = required_non_blank(payload, "prompt")?;
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
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now();
        let automation_run_id = payload
            .get("automationRunId")
            .and_then(Value::as_str)
            .map(str::to_string);
        let automation_owned = payload
            .get("automationOwned")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let tab = WorkspaceTabRecord {
            id: id.clone(),
            workspace_id: workspace_id.clone(),
            kind: "terminal".to_string(),
            title: profile.name.clone(),
            created_at: now,
            updated_at: now,
            payload: json!({
                "terminalSessionId": id,
                "initialCommand": command.unwrap_or_else(|| {
                    if managed_launch.is_some() {
                        String::new()
                    } else {
                        adapter.default_command.to_string()
                    }
                }),
                "initialManagedAgentLaunch": managed_launch,
                // Every adapter takes its prompt at launch. The shape differs
                // per agent and is resolved at spawn, where the shell is known.
                "initialPrompt": prompt,
                "initialPromptOnce": true,
                "agentProfileId": profile.id,
                "agentType": profile.agent_type,
                "spawnOnCreate": true,
                "automationRunId": automation_run_id,
                "automationOwned": automation_owned,
            }),
        };
        let saved = self.upsert_workspace_tab_and_spawn(tab).await?;
        Ok(json!({
            "tab": saved,
            "agentType": adapter.agent_type,
            "profileId": profile.id,
        }))
    }

    /// Types a prompt into an agent that reported it is idle.
    ///
    /// No adapter asks for this any more: a prompt now travels with the launch.
    /// It stays because a tab written by an older host can still carry
    /// `pendingAgentPrompt`, and the app attaches to whichever sidecar is
    /// already running, so a newer host has to be able to finish that delivery.
    pub(super) async fn deliver_pending_agent_prompt(&mut self, session_id: &str) {
        if !self.agent_presence.is_injection_ready(session_id) {
            return;
        }
        let Some(session) = self.sessions.get(session_id) else {
            return;
        };
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
        tab.payload["pendingAgentPrompt"] = Value::Null;
        tab.updated_at = chrono::Utc::now();
        let workspace_id = tab.workspace_id.clone();
        if let Err(error) = self.runtime_store.upsert_workspace_tab(tab).await {
            tracing::error!(tab_id = %tab_id, "failed to clear pending agent prompt: {error}");
        }
        self.broadcast_workspace_tabs_changed(Some(&workspace_id));
    }
}

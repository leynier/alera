use alera_core::runtime::RuntimeAgentQuotaSettings;
use serde::Serialize;
use serde_json::{json, Value};

use crate::agent_status::reconcile_agent_integrations;
use crate::host_tools::{
    cli_registration_status, install_cli_registration, install_skill, SkillKind, SkillRunner,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, event, ok_response};

use super::{ServerActor, ServerCommand};

impl ServerActor {
    pub(super) async fn apply_mobile_runtime_settings(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        if let Some(value) = payload.get("workspaceDirectory") {
            let directory = match value {
                Value::String(value) => Some(value.as_str()),
                Value::Null => None,
                _ => {
                    return Err(HostError::format(
                        "workspaceDirectory must be a string or null.",
                    ))
                }
            };
            runtime_value(self.runtime_store.set_workspace_directory(directory).await)?;
        }
        if let Some(value) = payload.get("confirmProjectRemoval") {
            let enabled = value
                .as_bool()
                .ok_or_else(|| HostError::format("confirmProjectRemoval must be a boolean."))?;
            runtime_value(
                self.runtime_store
                    .set_confirm_project_removal(enabled)
                    .await,
            )?;
        }
        if let Some(value) = payload.get("confirmWorkspaceRemoval") {
            let enabled = value
                .as_bool()
                .ok_or_else(|| HostError::format("confirmWorkspaceRemoval must be a boolean."))?;
            runtime_value(
                self.runtime_store
                    .set_confirm_workspace_removal(enabled)
                    .await,
            )?;
        }
        if let Some(value) = payload.get("agentStatusHooks") {
            let settings = serde_json::from_value(value.clone()).map_err(|_| {
                HostError::format("agentStatusHooks must contain boolean agent switches.")
            })?;
            runtime_value(
                self.runtime_store
                    .set_agent_status_hook_settings(&settings)
                    .await,
            )?;
            self.agent_presence
                .retain_enabled(&settings.enabled_agents());
            let runtime_dir = self.runtime_dir.clone();
            let reconcile_settings = settings.clone();
            let warnings = tokio::task::spawn_blocking(move || {
                reconcile_agent_integrations(&runtime_dir, &reconcile_settings)
            })
            .await
            .unwrap_or_else(|error| vec![error.to_string()]);
            for warning in warnings {
                tracing::warn!("alera agent integration warning: {warning}");
            }
            self.broadcast_agent_presence_changed();
        }
        if let Some(value) = payload.get("agentQuotas") {
            let settings: RuntimeAgentQuotaSettings = serde_json::from_value(value.clone())
                .map_err(|_| HostError::format("agentQuotas is invalid."))?;
            validate_agent_quota_settings(&settings)?;
            runtime_value(self.runtime_store.set_agent_quota_settings(settings).await)?;
            self.agent_quota_cache = None;
        }
        let value = runtime_value(self.runtime_store.runtime_settings().await)?;
        self.broadcast_authenticated(event("runtimeSettingsChanged", json!({})));
        Ok(value)
    }

    pub(super) fn start_cli_registration_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        install: bool,
    ) {
        let runtime_dir = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = if install {
                install_cli_registration(&runtime_dir)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))
            } else {
                Ok(cli_registration_status(&runtime_dir).await)
            }
            .and_then(|value| {
                serde_json::to_value(value).map_err(|error| HostError::state(error.to_string()))
            });
            let _ = inbox.send(ServerCommand::HostToolFinished {
                client_id,
                request_id,
                result,
                operation_id: None,
                skill: None,
            });
        });
    }

    pub(super) fn start_skill_install_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let skill_name = required_non_blank(payload, "skill")?;
        let runner_name = required_non_blank(payload, "runner")?;
        let skill = SkillKind::parse(&skill_name)
            .ok_or_else(|| HostError::format("skill must be cli, emulator, or orchestration."))?;
        let runner = SkillRunner::parse(&runner_name)
            .ok_or_else(|| HostError::format("runner must be auto, npx, or bunx."))?;
        self.broadcast_authenticated(event(
            "agentSkillInstallProgress",
            json!({
                "operationId": operation_id,
                "skill": skill_name,
                "phase": "installing",
                "message": "Installing Skill",
            }),
        ));
        let store = self.runtime_store.clone();
        let runtime_dir = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        let operation_for_task = operation_id.clone();
        let skill_for_task = skill_name.clone();
        tokio::spawn(async move {
            let install_result = install_skill(skill, runner).await;
            let mut value = serde_json::to_value(&install_result)
                .map_err(|error| HostError::state(error.to_string()));
            if install_result.succeeded && matches!(skill, SkillKind::Orchestration) {
                let settings = store
                    .agent_status_hook_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()));
                if let Ok(settings) = settings {
                    let warnings = tokio::task::spawn_blocking(move || {
                        reconcile_agent_integrations(&runtime_dir, &settings)
                    })
                    .await
                    .unwrap_or_else(|error| vec![error.to_string()]);
                    if let Ok(Value::Object(object)) = &mut value {
                        object.insert("hookWarnings".to_string(), json!(warnings));
                    }
                }
            }
            let _ = inbox.send(ServerCommand::HostToolFinished {
                client_id,
                request_id,
                result: value,
                operation_id: Some(operation_for_task),
                skill: Some(skill_for_task),
            });
        });
        Ok(())
    }

    pub(super) fn handle_host_tool_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
        operation_id: Option<String>,
        skill: Option<String>,
    ) {
        match &result {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value.clone())),
            Err(error) => self.client_write(client_id, error_response(request_id, error)),
        }
        if let (Some(operation_id), Some(skill)) = (operation_id, skill) {
            let succeeded = result
                .as_ref()
                .ok()
                .and_then(|value| value.get("succeeded"))
                .and_then(Value::as_bool)
                .unwrap_or(false);
            self.broadcast_authenticated(event(
                "agentSkillInstallProgress",
                json!({
                    "operationId": operation_id,
                    "skill": skill,
                    "phase": if succeeded { "completed" } else { "failed" },
                    "message": result
                        .as_ref()
                        .ok()
                        .and_then(|value| value.get("summary"))
                        .and_then(Value::as_str)
                        .unwrap_or("Skill Install Failed"),
                }),
            ));
        }
    }
}

pub(super) fn validate_agent_quota_settings(
    settings: &RuntimeAgentQuotaSettings,
) -> HostResult<()> {
    let mut aliases = std::collections::HashSet::new();
    let mut profiles = std::collections::HashSet::new();
    for profile in &settings.claude_profiles {
        let alias = profile.alias.trim();
        let profile_name = profile.profile.trim();
        if alias.is_empty() || profile_name.is_empty() {
            return Err(HostError::format(
                "Claude aliases and profiles are required.",
            ));
        }
        if !aliases.insert(alias) || !profiles.insert(profile_name) {
            return Err(HostError::format(
                "Claude aliases and profiles must be unique.",
            ));
        }
    }
    for name in [
        &settings.environment.kimi_api_key,
        &settings.environment.zai_api_key,
        &settings.environment.zai_base_url,
        &settings.environment.minimax_api_key,
        &settings.environment.minimax_api_host,
    ] {
        if !valid_environment_name(name) {
            return Err(HostError::format(format!(
                "Invalid environment variable name: {name}."
            )));
        }
    }
    Ok(())
}

fn valid_environment_name(value: &str) -> bool {
    let mut chars = value.chars();
    chars
        .next()
        .is_some_and(|first| first == '_' || first.is_ascii_alphabetic())
        && chars.all(|char| char == '_' || char.is_ascii_alphanumeric())
}

fn runtime_value<T, E>(result: Result<T, E>) -> HostResult<Value>
where
    T: Serialize,
    E: std::fmt::Display,
{
    let value = result.map_err(|error| HostError::state(error.to_string()))?;
    serde_json::to_value(value).map_err(|error| HostError::state(error.to_string()))
}

pub(super) fn required_non_blank(payload: &Value, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::format(format!("{key} must be a non-empty string.")))
}

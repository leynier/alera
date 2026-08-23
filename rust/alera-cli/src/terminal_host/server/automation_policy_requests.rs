use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationAgentPolicy, AutomationDefinition,
    AutomationProjectPolicy, AutomationTarget, ProjectKind,
};
use chrono::Utc;
use serde_json::{json, Map, Value};
use std::path::Path;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::terminal_startup_commands::agent_profile_id;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn automation_policy_request(
        &self,
        client_id: u64,
        payload: &Value,
        actor: &AutomationActor,
    ) -> HostResult<Value> {
        let actor = self
            .resolve_policy_actor(client_id, payload, actor.clone())
            .await?;
        let kind = payload
            .get("kind")
            .and_then(Value::as_str)
            .unwrap_or("show");
        let policy = payload.get("policy");
        match kind {
            "agent" => {
                require_policy_admin(&actor)?;
                let profile_id = payload
                    .get("profileId")
                    .and_then(Value::as_str)
                    .ok_or_else(|| HostError::format("agent policy requires profileId"))?;
                if let Some(value) = policy {
                    let policy = decode_agent_policy(value, profile_id)?;
                    let saved = self
                        .runtime_store
                        .set_automation_agent_policy(policy)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    return serde_json::to_value(saved)
                        .map_err(|error| HostError::state(error.to_string()));
                }
                let policy = self
                    .runtime_store
                    .automation_agent_policy(profile_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                serde_json::to_value(policy).map_err(|error| HostError::state(error.to_string()))
            }
            "project" => {
                require_policy_admin(&actor)?;
                let project_id = payload
                    .get("projectId")
                    .and_then(Value::as_str)
                    .ok_or_else(|| HostError::format("project policy requires projectId"))?;
                if let Some(value) = policy {
                    let mut policy = decode_project_policy(value, project_id)?;
                    policy.repo_declared = self.repository_declared_for_project(project_id).await?;
                    let saved = self
                        .runtime_store
                        .set_automation_project_policy(policy)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    return serde_json::to_value(saved)
                        .map_err(|error| HostError::state(error.to_string()));
                }
                let policy = self.effective_project_policy(project_id).await?;
                serde_json::to_value(policy).map_err(|error| HostError::state(error.to_string()))
            }
            "show" => {
                let mut result = Map::new();
                if let Some(profile_id) = payload.get("profileId").and_then(Value::as_str) {
                    let policy = self
                        .runtime_store
                        .automation_agent_policy(profile_id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    result.insert(
                        "agent".to_string(),
                        serde_json::to_value(policy)
                            .map_err(|error| HostError::state(error.to_string()))?,
                    );
                }
                if let Some(project_id) = payload.get("projectId").and_then(Value::as_str) {
                    let policy = self.effective_project_policy(project_id).await?;
                    result.insert(
                        "project".to_string(),
                        serde_json::to_value(policy)
                            .map_err(|error| HostError::state(error.to_string()))?,
                    );
                }
                if result.is_empty() {
                    return Err(HostError::format(
                        "policy show requires profileId or projectId",
                    ));
                }
                if let Some(profile_id) = payload.get("profileId").and_then(Value::as_str) {
                    let policy = self
                        .runtime_store
                        .automation_agent_policy(profile_id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    let project = if let Some(project_id) =
                        payload.get("projectId").and_then(Value::as_str)
                    {
                        Some(self.effective_project_policy(project_id).await?)
                    } else {
                        None
                    };
                    result.insert(
                        "effective".to_string(),
                        json!({"targetProfile": policy, "project": project}),
                    );
                }
                Ok(Value::Object(result))
            }
            _ => Err(HostError::format(
                "automation policy kind must be show, agent, or project",
            )),
        }
    }

    pub(super) async fn resolve_policy_actor(
        &self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<AutomationActor> {
        let Some(run_id) = payload.get("run").and_then(Value::as_str) else {
            return Ok(actor);
        };
        let identity = super::automation_run_target_requests::requested_target_identity(payload)?;
        self.verify_live_target_identity(client_id, &identity)
            .await?;
        let run = self
            .runtime_store
            .find_automation_run(run_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation run not found: {run_id}")))?;
        if run
            .target_identity
            .as_ref()
            .is_none_or(|bound| !bound.matches(&identity))
        {
            return Err(HostError::state(
                "automation run target identity does not match the live run",
            ));
        }
        if actor.kind == AutomationActorKind::LocalCli
            && run.actor_kind == Some(AutomationActorKind::ManagedAgent)
        {
            return Ok(AutomationActor {
                kind: AutomationActorKind::ManagedAgent,
                id: run.actor_id,
                label: Some("managed automation agent".to_string()),
            });
        }
        Ok(actor)
    }

    pub(super) async fn ensure_agent_policy(
        &self,
        definition: &AutomationDefinition,
        actor: &AutomationActor,
        execute: bool,
    ) -> HostResult<()> {
        if execute {
            let Some(profile_id) = self
                .target_profile_id(definition)
                .await?
                .as_deref()
                .map(str::to_string)
            else {
                return Err(HostError::state(
                    "automation target must resolve to an agent profile",
                ));
            };
            let policy = self
                .runtime_store
                .automation_agent_policy(&profile_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            if !policy.may_execute {
                return Err(HostError::state(format!(
                    "agent profile {profile_id} is not opted in to automation execution"
                )));
            }
        } else if actor.kind == AutomationActorKind::ManagedAgent {
            let Some(profile_id) = actor.id.as_deref() else {
                return Err(HostError::state(
                    "managed agent identity has no editing profile",
                ));
            };
            let policy = self
                .runtime_store
                .automation_agent_policy(profile_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            let allowed = policy.may_activate_or_edit_active;
            if !allowed {
                return Err(HostError::state(format!(
                    "agent policy for profile {profile_id} does not allow managed agents to activate or edit active automations"
                )));
            }
        }

        let source_workspace_id = match &definition.target {
            AutomationTarget::ExistingTab { workspace_id, .. }
            | AutomationTarget::FreshTab { workspace_id, .. } => workspace_id,
            AutomationTarget::ManagedWorkspace {
                source_workspace_id,
                ..
            } => source_workspace_id,
        };
        let Some(workspace) = self
            .runtime_store
            .find_workspace(source_workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Err(HostError::state("automation target workspace is missing"));
        };
        let Some(project) = self
            .runtime_store
            .find_project(&workspace.project_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Err(HostError::state("automation target project is missing"));
        };
        if matches!(definition.target, AutomationTarget::ManagedWorkspace { .. })
            && project.kind == ProjectKind::Folder
        {
            return Err(HostError::state(
                "managed workspace automations require a git repository project",
            ));
        }
        let project_policy = self
            .runtime_store
            .automation_project_policy(&workspace.project_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if !repository_declares_automation(&workspace.path, &project.repo_path) {
            return Err(HostError::state(format!(
                "repository {} has no automation declaration in alera.toml",
                workspace.project_id
            )));
        }
        if project_policy.restrictive && !project_policy.local_approved {
            return Err(HostError::state(format!(
                "project policy for {} requires local approval",
                workspace.project_id
            )));
        }
        Ok(())
    }

    pub(super) async fn target_profile_id(
        &self,
        definition: &AutomationDefinition,
    ) -> HostResult<Option<String>> {
        match &definition.target {
            AutomationTarget::ExistingTab { tab_id, .. } => {
                let tab = self
                    .runtime_store
                    .find_workspace_tab(tab_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| HostError::state("automation existing tab is missing"))?;
                Ok(agent_profile_id(&tab).map(str::to_string))
            }
            AutomationTarget::FreshTab {
                agent_profile_id, ..
            }
            | AutomationTarget::ManagedWorkspace {
                agent_profile_id, ..
            } => Ok(Some(agent_profile_id.clone())),
        }
    }

    pub(super) async fn effective_project_policy(
        &self,
        project_id: &str,
    ) -> HostResult<AutomationProjectPolicy> {
        let mut policy = self
            .runtime_store
            .automation_project_policy(project_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        policy.repo_declared = self.repository_declared_for_project(project_id).await?;
        Ok(policy)
    }

    async fn repository_declared_for_project(&self, project_id: &str) -> HostResult<bool> {
        let Some(project) = self
            .runtime_store
            .find_project(project_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(false);
        };
        Ok(repository_declares_automation("", &project.repo_path))
    }
}

fn require_policy_admin(actor: &AutomationActor) -> HostResult<()> {
    if actor.kind == AutomationActorKind::ManagedAgent {
        return Err(HostError::state(
            "managed agents cannot administer automation policies",
        ));
    }
    Ok(())
}

pub(super) fn require_human_automation_actor(actor: &AutomationActor) -> HostResult<()> {
    if actor.kind == AutomationActorKind::ManagedAgent {
        return Err(HostError::state(
            "managed agents cannot approve automation revisions",
        ));
    }
    Ok(())
}

fn repository_declares_automation(workspace_path: &str, project_repo_path: &str) -> bool {
    let candidates = [
        Path::new(workspace_path).join("alera.toml"),
        Path::new(project_repo_path).join("alera.toml"),
    ];
    candidates.iter().any(|path| {
        let Ok(contents) = std::fs::read_to_string(path) else {
            return false;
        };
        // toml 1.x FromStr for Value parses a single value, not a document.
        // A file like `automation_declared = true` must go through from_str.
        let Ok(value) = toml::from_str::<toml::Value>(&contents) else {
            return false;
        };
        let Some(root) = value.as_table() else {
            return false;
        };
        root.get("automation_declared")
            .and_then(toml::Value::as_bool)
            .unwrap_or(false)
            || root
                .get("automation")
                .and_then(toml::Value::as_table)
                .is_some_and(|table| {
                    table
                        .get("declared")
                        .or_else(|| table.get("enabled"))
                        .and_then(toml::Value::as_bool)
                        .unwrap_or(false)
                })
    })
}

fn decode_agent_policy(value: &Value, profile_id: &str) -> HostResult<AutomationAgentPolicy> {
    let object = policy_object(value, "agent")?;
    let mut object = object;
    object.insert(
        "profileId".to_string(),
        Value::String(profile_id.to_string()),
    );
    object
        .entry("updatedAt".to_string())
        .or_insert_with(|| json!(Utc::now()));
    serde_json::from_value(Value::Object(object))
        .map_err(|error| HostError::format(format!("invalid agent policy: {error}")))
}

fn decode_project_policy(value: &Value, project_id: &str) -> HostResult<AutomationProjectPolicy> {
    let object = policy_object(value, "project")?;
    let mut object = object;
    object.insert(
        "projectId".to_string(),
        Value::String(project_id.to_string()),
    );
    object
        .entry("updatedAt".to_string())
        .or_insert_with(|| json!(Utc::now()));
    serde_json::from_value(Value::Object(object))
        .map_err(|error| HostError::format(format!("invalid project policy: {error}")))
}

fn policy_object(value: &Value, kind: &str) -> HostResult<Map<String, Value>> {
    value
        .as_object()
        .cloned()
        .ok_or_else(|| HostError::format(format!("{kind} policy must be a JSON object")))
}

#[cfg(test)]
mod tests {
    use super::repository_declares_automation;
    use std::fs;
    use std::path::Path;

    fn declare(dir: &Path, contents: &str) {
        fs::write(dir.join("alera.toml"), contents).unwrap();
    }

    #[test]
    fn root_automation_declared_flag_is_recognized() {
        let dir = tempfile::tempdir().unwrap();
        declare(dir.path(), "automation_declared = true\n");
        assert!(repository_declares_automation(
            dir.path().to_str().unwrap(),
            "/missing"
        ));
    }

    #[test]
    fn nested_automation_declared_flag_is_recognized() {
        let dir = tempfile::tempdir().unwrap();
        declare(dir.path(), "[automation]\ndeclared = true\n");
        assert!(repository_declares_automation(
            "",
            dir.path().to_str().unwrap()
        ));
    }

    #[test]
    fn missing_or_false_declaration_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        assert!(!repository_declares_automation(
            dir.path().to_str().unwrap(),
            dir.path().to_str().unwrap()
        ));
        declare(dir.path(), "automation_declared = false\n");
        assert!(!repository_declares_automation(
            dir.path().to_str().unwrap(),
            dir.path().to_str().unwrap()
        ));
    }
}

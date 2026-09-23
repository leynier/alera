use crate::automation_declaration::repository_declares_automation;
use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationAgentPolicy, AutomationDefinition,
    AutomationProjectPolicy, AutomationTarget, ProjectKind,
};
use chrono::Utc;
use serde_json::{json, Map, Value};

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
                let profile_id = optional_id(payload, "profileId");
                let project_id = optional_id(payload, "projectId");
                if profile_id.is_none() && project_id.is_none() {
                    return self.list_all_automation_policies().await;
                }
                let mut result = Map::new();
                if let Some(profile_id) = profile_id {
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
                if let Some(project_id) = project_id {
                    let policy = self.effective_project_policy(project_id).await?;
                    result.insert(
                        "project".to_string(),
                        serde_json::to_value(policy)
                            .map_err(|error| HostError::state(error.to_string()))?,
                    );
                }
                if let Some(profile_id) = profile_id {
                    let policy = self
                        .runtime_store
                        .automation_agent_policy(profile_id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    let project = if let Some(project_id) = project_id {
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

    /// Agent and target checks for Active/Paused edits and for execution.
    /// Repository declaration and restrictive local approval gate execution
    /// only (`execute = true`). Do not call this for draft trash/restore.
    pub(super) async fn ensure_agent_policy(
        &self,
        definition: &AutomationDefinition,
        actor: &AutomationActor,
        execute: bool,
    ) -> HostResult<()> {
        self.check_agent_policy(definition, actor, execute, false)
            .await
    }

    pub(super) async fn ensure_dispatch_policy(
        &self,
        definition: &AutomationDefinition,
        actor: &AutomationActor,
    ) -> HostResult<()> {
        // SSH declaration inspection is part of the bounded checkout worker.
        self.check_agent_policy(definition, actor, true, true).await
    }

    async fn check_agent_policy(
        &self,
        definition: &AutomationDefinition,
        actor: &AutomationActor,
        execute: bool,
        defer_ssh_declaration: bool,
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

        let location = self.automation_target_location(definition).await?;
        let project = &location.project;
        if matches!(definition.target, AutomationTarget::ManagedWorkspace { .. })
            && project.kind == ProjectKind::Folder
        {
            return Err(HostError::state(
                "managed workspace automations require a git repository project",
            ));
        }
        if !execute {
            return Ok(());
        }
        let project_policy = self
            .runtime_store
            .automation_project_policy(&project.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let declared = if definition.target.project_checkout().is_some()
            && location.host_id != alera_core::runtime::LOCAL_HOST_ID
        {
            if defer_ssh_declaration {
                if project_policy.restrictive && !project_policy.local_approved {
                    return Err(HostError::state(format!(
                        "project policy for {} requires local approval",
                        project.id
                    )));
                }
                return Ok(());
            }
            let inspection = crate::remote_project_checkout::inspect_remote(
                &self.runtime_store,
                &location.host_id,
                &location.path,
                project.kind,
                &crate::ssh_remote::LiveSshRemoteHost,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
            if inspection.path != location.path {
                return Err(HostError::state(
                    "The registered SSH checkout changed; refresh its registration",
                ));
            }
            inspection.automation_declared.ok_or_else(|| {
                HostError::state(
                    "Update the SSH runtime to verify project checkout automation authorization",
                )
            })?
        } else {
            let path = location.path.clone();
            let repository = project.repo_path.clone();
            tokio::task::spawn_blocking(move || repository_declares_automation(&path, &repository))
                .await
                .map_err(|error| HostError::state(error.to_string()))?
        };
        if !declared {
            return Err(HostError::state(format!(
                "repository {} has no automation declaration in alera.toml",
                project.id
            )));
        }
        if project_policy.restrictive && !project_policy.local_approved {
            return Err(HostError::state(format!(
                "project policy for {} requires local approval",
                project.id
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
            }
            | AutomationTarget::ProjectCheckout {
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

    async fn list_all_automation_policies(&self) -> HostResult<Value> {
        let agents = self
            .runtime_store
            .list_automation_agent_policies()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let projects = self
            .runtime_store
            .list_automation_project_policies()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let mut projects_json = Vec::with_capacity(projects.len());
        for mut policy in projects {
            policy.repo_declared = self
                .repository_declared_for_project(&policy.project_id)
                .await?;
            projects_json.push(
                serde_json::to_value(policy)
                    .map_err(|error| HostError::state(error.to_string()))?,
            );
        }
        Ok(json!({
            "agents": agents,
            "projects": projects_json,
        }))
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

fn optional_id<'a>(payload: &'a Value, key: &str) -> Option<&'a str> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
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

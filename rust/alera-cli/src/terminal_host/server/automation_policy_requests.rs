use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationTarget, ProjectKind,
};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::terminal_startup_commands::agent_profile_id;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn automation_policy_request(
        &self,
        _client_id: u64,
        _payload: &Value,
        _actor: &AutomationActor,
    ) -> HostResult<Value> {
        Err(HostError::state("Automation policies were removed. Use automation.readiness to check technical requirements."))
    }

    pub(super) async fn resolve_policy_actor(
        &self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<AutomationActor> {
        let Some(run_id) = payload.get("run").and_then(Value::as_str) else {
            if actor.kind == AutomationActorKind::LocalCli {
                if let Some(session) = payload["terminalHandle"]
                    .as_str()
                    .and_then(|id| self.sessions.get(id))
                {
                    if let Some(tab) = self
                        .runtime_store
                        .find_workspace_tab(&session.tab_id)
                        .await
                        .ok()
                        .flatten()
                    {
                        if let Some(profile_id) =
                            super::terminal_startup_commands::agent_profile_id(&tab)
                        {
                            if let Some(profile) = self
                                .runtime_store
                                .find_agent_profile(profile_id)
                                .await
                                .ok()
                                .flatten()
                            {
                                return Ok(AutomationActor {
                                    kind: AutomationActorKind::ManagedAgent,
                                    id: Some(profile.id),
                                    label: Some(profile.name),
                                });
                            }
                        }
                    }
                }
            }
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

    /// Validates target structure for authored definitions and execution.
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
        // Remote checkout availability is verified by the bounded worker.
        self.check_agent_policy(definition, actor, true, true).await
    }

    async fn check_agent_policy(
        &self,
        definition: &AutomationDefinition,
        _actor: &AutomationActor,
        execute: bool,
        _defer_ssh_declaration: bool,
    ) -> HostResult<()> {
        let location = self.automation_target_location(definition).await?;
        if location.workspace.as_ref().is_some_and(|workspace| {
            workspace.status != alera_core::runtime::WorkspaceStatus::Active
                || workspace.is_archived
        }) {
            return Err(HostError::state(
                "Choose an active workspace for this automation",
            ));
        }
        let project = &location.project;
        if matches!(
            definition.target,
            AutomationTarget::ManagedWorkspace { .. } | AutomationTarget::ProjectWorktree { .. }
        ) && project.kind == ProjectKind::Folder
        {
            return Err(HostError::state(
                "managed workspace automations require a git repository project",
            ));
        }
        if !execute {
            return Ok(());
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
            }
            | AutomationTarget::ProjectWorktree {
                agent_profile_id, ..
            } => Ok(Some(agent_profile_id.clone())),
        }
    }
}

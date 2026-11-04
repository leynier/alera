use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationTarget, ProjectKind,
};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::terminal_startup_commands::agent_profile_id;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn resolve_request_actor(
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

    /// Validates the target structure for authored definitions and execution:
    /// a workspace target must be active, and worktree targets need a git project.
    pub(super) async fn ensure_target_valid(
        &self,
        definition: &AutomationDefinition,
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
        if definition.target.worktree().is_some() && location.project.kind == ProjectKind::Folder {
            return Err(HostError::state(
                "worktree automations require a git repository project",
            ));
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
                    .map_err(|error| HostError::state(error.to_string()))?;
                let bound = || {
                    definition
                        .bound_target
                        .as_ref()
                        .and_then(|binding| binding.agent_profile_id.clone())
                };
                match tab {
                    Some(tab) => Ok(agent_profile_id(&tab).map(str::to_string).or_else(bound)),
                    None => match bound() {
                        Some(profile) => Ok(Some(profile)),
                        None => Err(HostError::state("automation existing tab is missing")),
                    },
                }
            }
            AutomationTarget::FreshTab {
                agent_profile_id, ..
            }
            | AutomationTarget::Worktree {
                agent_profile_id, ..
            }
            | AutomationTarget::ProjectCheckout {
                agent_profile_id, ..
            } => Ok(Some(agent_profile_id.clone())),
            // An agent chat run uses the chat's own agent, not a profile.
            AutomationTarget::AgentChat { .. } => Ok(None),
        }
    }
}

impl ServerActor {
    /// Why an agent chat target cannot run: its chat is gone or archived.
    pub(super) async fn agent_chat_target_issue(
        &self,
        spec: alera_core::runtime::AutomationAgentChatSpec<'_>,
    ) -> Option<String> {
        if self.agent_chat_runtime.is_none() {
            return Some("Agent chats are unavailable on this runtime".into());
        }
        let chat_id = spec.chat_id?;
        match self.runtime_store.agent_chat(chat_id).await {
            Ok(Some(chat)) if chat.archived => Some("The scheduled task's chat is archived".into()),
            Ok(Some(chat)) if chat.workspace_id != spec.workspace_id => {
                Some("The scheduled task's chat moved to another workspace".into())
            }
            Ok(Some(_)) => None,
            Ok(None) => Some("The scheduled task's chat no longer exists".into()),
            Err(error) => Some(error.to_string()),
        }
    }
}

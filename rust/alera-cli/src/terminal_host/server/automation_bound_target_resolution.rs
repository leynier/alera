//! Decides where a run goes before its attempt starts. Under a reuse policy
//! the binding is read fresh from the store, never from the run's frozen
//! definition, because takeover, tab removal and workspace retirement edit it
//! between runs.

use alera_core::runtime::{
    AutomationBoundTarget, AutomationDefinition, AutomationReusePolicy, AutomationRun,
    AutomationTarget, Workspace, WorkspaceStatus, WorkspaceTabRecord, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::Value;

use super::agent_native_session::native_session_resume;
use super::requests::terminal_session_id_from_tab;
use super::terminal_startup_commands::agent_profile_id;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) const WAITING_FOR_BOUND_CONVERSATION: &str = "waitingForBoundConversation";
pub(super) const WAITING_FOR_REMOTE_HOST: &str = "waitingForRemoteHost";

#[derive(Debug, Clone)]
pub(super) enum BoundTargetPlan {
    /// Today's path: create the target the definition names.
    CreateNew,
    /// The binding pointed at something that no longer fits; it was cleared
    /// and the run creates a new target.
    Recreate { reason: &'static str },
    PasteIntoConversation {
        workspace: Workspace,
        tab: WorkspaceTabRecord,
        session_id: String,
    },
    RelaunchConversation {
        workspace: Workspace,
        tab: WorkspaceTabRecord,
        native_session_id: Option<String>,
    },
    NewTabInWorkspace {
        workspace: Workspace,
        profile_id: String,
        rebind_tab: bool,
    },
    Busy {
        session_id: Option<String>,
        code: &'static str,
    },
}

impl BoundTargetPlan {
    /// The bound workspace a reuse plan delivers to; `None` when the run
    /// creates its target or waits.
    pub(super) fn reused_workspace(&self) -> Option<&Workspace> {
        match self {
            Self::PasteIntoConversation { workspace, .. }
            | Self::RelaunchConversation { workspace, .. }
            | Self::NewTabInWorkspace { workspace, .. } => Some(workspace),
            Self::CreateNew | Self::Recreate { .. } | Self::Busy { .. } => None,
        }
    }
}

impl ServerActor {
    pub(super) async fn plan_bound_target(
        &self,
        definition: &AutomationDefinition,
        run: &AutomationRun,
    ) -> HostResult<BoundTargetPlan> {
        let policy = definition.reuse_policy;
        if policy == AutomationReusePolicy::NewEachRun {
            return match &definition.target {
                AutomationTarget::ExistingTab {
                    workspace_id,
                    tab_id,
                    conversation_id,
                } => {
                    self.plan_strict_existing_tab(workspace_id, tab_id, conversation_id.as_deref())
                        .await
                }
                _ => Ok(BoundTargetPlan::CreateNew),
            };
        }
        let stored = self
            .runtime_store
            .find_automation(&definition.id)
            .await
            .map_err(state_error)?
            .and_then(|current| current.bound_target);
        let binding = match stored {
            Some(binding) => binding,
            None => match self.seed_existing_tab_binding(definition, run).await? {
                Some(binding) => binding,
                None => return Ok(BoundTargetPlan::CreateNew),
            },
        };
        let existing_tab = matches!(definition.target, AutomationTarget::ExistingTab { .. });
        let workspace = self
            .runtime_store
            .find_workspace(&binding.workspace_id)
            .await
            .map_err(state_error)?;
        let gone = match &workspace {
            None => Some("workspaceGone"),
            Some(workspace)
                if workspace.is_archived || workspace.status != WorkspaceStatus::Active =>
            {
                Some("workspaceArchived")
            }
            Some(workspace) if !binding_fits_target(&definition.target, workspace) => {
                Some("targetChanged")
            }
            Some(_) => None,
        };
        if let Some(reason) = gone {
            self.clear_binding(&definition.id, reason).await?;
            if existing_tab {
                return Err(HostError::state(
                    "automation existing tab workspace changed",
                ));
            }
            return Ok(BoundTargetPlan::Recreate { reason });
        }
        let workspace = workspace.expect("checked above");
        if workspace.host_id != LOCAL_HOST_ID
            && !self
                .host_links
                .attached_host_ids()
                .contains(&workspace.host_id)
        {
            return Ok(BoundTargetPlan::Busy {
                session_id: None,
                code: WAITING_FOR_REMOTE_HOST,
            });
        }
        let profile_id = binding
            .agent_profile_id
            .clone()
            .or_else(|| definition.target.agent_profile_id().map(str::to_string));
        let new_tab = |rebind_tab: bool| match profile_id.clone() {
            Some(profile_id) => Ok(BoundTargetPlan::NewTabInWorkspace {
                workspace: workspace.clone(),
                profile_id,
                rebind_tab,
            }),
            None if existing_tab => Err(HostError::state("automation existing tab is missing")),
            None => Err(HostError::state(
                "automation bound workspace has no agent profile to open",
            )),
        };
        if policy == AutomationReusePolicy::ReuseWorkspace {
            return new_tab(false);
        }
        let tab = match binding.tab_id.as_deref() {
            Some(tab_id) => self
                .runtime_store
                .find_workspace_tab(tab_id)
                .await
                .map_err(state_error)?
                .filter(|tab| tab.workspace_id == workspace.id),
            None => None,
        };
        let Some(tab) = tab else {
            return new_tab(true);
        };
        if tab.payload["automationTakenOver"] == true {
            self.release_binding_tab(&definition.id, "takenOver")
                .await?;
            return new_tab(true);
        }
        if binding
            .conversation_id
            .as_deref()
            .is_some_and(|expected| tab.payload["conversationId"].as_str() != Some(expected))
        {
            self.release_binding_tab(&definition.id, "conversationChanged")
                .await?;
            return new_tab(true);
        }
        let session_id = terminal_session_id_from_tab(&tab).unwrap_or_else(|| tab.id.clone());
        let owned = tab.payload["automationOwned"] == true;
        if self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.running())
        {
            if self.session_serves_another_run(&session_id, &run.id).await {
                return Ok(BoundTargetPlan::Busy {
                    session_id: Some(session_id),
                    code: WAITING_FOR_BOUND_CONVERSATION,
                });
            }
            if self.agent_presence.is_injection_ready(&session_id) {
                return Ok(BoundTargetPlan::PasteIntoConversation {
                    workspace,
                    tab,
                    session_id,
                });
            }
            if self.agent_presence.has(&session_id) {
                return Ok(BoundTargetPlan::Busy {
                    session_id: Some(session_id),
                    code: WAITING_FOR_BOUND_CONVERSATION,
                });
            }
            if owned {
                let native_session_id = native_id(&tab);
                return Ok(BoundTargetPlan::RelaunchConversation {
                    workspace,
                    tab,
                    native_session_id,
                });
            }
            self.release_binding_tab(&definition.id, "agentExited")
                .await?;
            return new_tab(true);
        }
        let native_session_id = native_id(&tab);
        if native_session_id.is_some() || owned {
            return Ok(BoundTargetPlan::RelaunchConversation {
                workspace,
                tab,
                native_session_id,
            });
        }
        self.release_binding_tab(&definition.id, "terminalGone")
            .await?;
        new_tab(true)
    }

    /// The pre-reuse contract of an existing-tab target: every identity check
    /// is an error that blocks the definition, and a busy agent parks the run.
    async fn plan_strict_existing_tab(
        &self,
        workspace_id: &str,
        tab_id: &str,
        conversation_id: Option<&str>,
    ) -> HostResult<BoundTargetPlan> {
        let tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("automation existing tab is missing"))?;
        if tab.workspace_id != workspace_id {
            return Err(HostError::state(
                "automation existing tab workspace changed",
            ));
        }
        let session_id = terminal_session_id_from_tab(&tab)
            .ok_or_else(|| HostError::state("automation existing tab has no terminal identity"))?;
        let Some(expected) = conversation_id else {
            return Err(HostError::state(
                "automation conversation continuity cannot be proven",
            ));
        };
        if tab.payload.get("conversationId").and_then(Value::as_str) != Some(expected) {
            return Err(HostError::state("automation conversation identity changed"));
        }
        if !self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.running())
        {
            return Err(HostError::state(
                "automation existing tab has no live PTY after restart",
            ));
        }
        let workspace = self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("automation existing tab workspace changed"))?;
        if !self.agent_presence.is_injection_ready(&session_id) {
            return Ok(BoundTargetPlan::Busy {
                session_id: Some(session_id),
                code: WAITING_FOR_BOUND_CONVERSATION,
            });
        }
        Ok(BoundTargetPlan::PasteIntoConversation {
            workspace,
            tab,
            session_id,
        })
    }

    /// An existing-tab target that reuses its conversation starts bound to
    /// the tab it names.
    async fn seed_existing_tab_binding(
        &self,
        definition: &AutomationDefinition,
        run: &AutomationRun,
    ) -> HostResult<Option<AutomationBoundTarget>> {
        let AutomationTarget::ExistingTab {
            workspace_id,
            tab_id,
            conversation_id,
        } = &definition.target
        else {
            return Ok(None);
        };
        let profile = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(state_error)?
            .and_then(|tab| agent_profile_id(&tab).map(str::to_string));
        let binding = AutomationBoundTarget {
            workspace_id: workspace_id.clone(),
            tab_id: Some(tab_id.clone()),
            conversation_id: conversation_id.clone(),
            agent_profile_id: profile,
            bound_run_id: run.id.clone(),
            bound_at: Utc::now(),
            last_run_id: None,
            last_verified_at: None,
        };
        self.runtime_store
            .bind_automation_target(&definition.id, &binding, "seededFromTarget")
            .await
            .map_err(state_error)?;
        self.broadcast_automation_changed(Some(&definition.id));
        Ok(Some(binding))
    }

    async fn session_serves_another_run(&self, session_id: &str, run_id: &str) -> bool {
        self.runtime_store
            .list_active_automation_runs()
            .await
            .unwrap_or_default()
            .iter()
            .any(|active| {
                active.id != run_id
                    && active.started_at.is_some()
                    && active.session_id.as_deref() == Some(session_id)
            })
    }

    async fn clear_binding(&self, automation_id: &str, reason: &str) -> HostResult<()> {
        if self
            .runtime_store
            .clear_automation_bound_target(automation_id, reason)
            .await
            .map_err(state_error)?
        {
            self.broadcast_automation_changed(Some(automation_id));
        }
        Ok(())
    }

    async fn release_binding_tab(&self, automation_id: &str, reason: &str) -> HostResult<()> {
        if self
            .runtime_store
            .release_automation_bound_tab(automation_id, reason)
            .await
            .map_err(state_error)?
        {
            self.broadcast_automation_changed(Some(automation_id));
        }
        Ok(())
    }
}

/// Whether a bound workspace still belongs to the target the definition
/// names. Editing the target clears the binding on save; this also catches
/// a workspace that moved underneath it.
fn binding_fits_target(target: &AutomationTarget, workspace: &Workspace) -> bool {
    if let Some(workspace_id) = target.workspace_id() {
        return workspace.id == workspace_id;
    }
    if let Some((project_id, host_id)) = target.project_checkout() {
        return workspace.project_id == project_id && workspace.host_id == host_id;
    }
    if let Some(spec) = target.worktree() {
        return spec
            .project_id
            .is_none_or(|project_id| workspace.project_id == project_id)
            && spec
                .parent_workspace_id
                .is_none_or(|parent| workspace.parent_workspace_id.as_deref() == Some(parent));
    }
    false
}

fn native_id(tab: &WorkspaceTabRecord) -> Option<String> {
    native_session_resume(tab).map(|resume| resume.session_id.to_string())
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

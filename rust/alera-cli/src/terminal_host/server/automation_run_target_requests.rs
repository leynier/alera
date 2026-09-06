use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationRun, AutomationRunStatus,
    AutomationTargetIdentity,
};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::automation_dispatch::render_workspace_name;
use super::requests::terminal_session_id_from_tab;
use super::terminal_startup_commands::agent_profile_id;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn verify_lifecycle_target_identity(
        &self,
        client_id: u64,
        run_id: &str,
        identity: &AutomationTargetIdentity,
        actor: &AutomationActor,
    ) -> HostResult<()> {
        self.runtime_store
            .verify_automation_run_target(run_id, identity)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let live_result = self.verify_live_target_identity(client_id, identity).await;
        if live_result.is_ok() || actor.kind == AutomationActorKind::ManagedAgent {
            return live_result;
        }
        // A queued run has no PTY yet, and a restarted existing-tab run may
        // have no live session. Human lifecycle operations still bind to the
        // durable target identity above; only the managed agent requires a
        // live PTY for its execution protocol. Do not turn a live identity
        // mismatch or an unauthorized caller into a durable-only bypass.
        if is_durable_lifecycle_fallback(&live_result)
            && self.clients.get(&client_id).is_some_and(|client| {
                client.authenticated
                    && (client.kind == super::ClientKind::Mobile
                        || (client.kind == super::ClientKind::Local
                            && client.local_role == super::client_delivery::LocalClientRole::App))
            })
        {
            return Ok(());
        }
        live_result
    }

    pub(super) async fn cleanup_automation_owned_target(
        &mut self,
        run: &AutomationRun,
        status: AutomationRunStatus,
    ) {
        if status != AutomationRunStatus::Success {
            return;
        }
        let Ok(Some(automation)) = self.runtime_store.find_automation(&run.automation_id).await
        else {
            return;
        };
        let mut taken_over = run.taken_over;
        if run.owned_tab {
            taken_over |= !self
                .automation_tab_is_owned(run.tab_id.as_deref(), &run.id)
                .await;
        }
        if run.setup_tab_id.is_some() {
            taken_over |= !self
                .automation_tab_is_owned(run.setup_tab_id.as_deref(), &run.id)
                .await;
        }
        let safe_workspace_cleanup = !taken_over
            && run.owned_workspace
            && self
                .automation_workspace_is_untouched(run, &automation)
                .await;
        let workspace_cleanup_requested = run.owned_workspace
            && automation.cleanup_policy
                == Some(alera_core::runtime::AutomationCleanupPolicy::OnSuccess);
        let can_remove_owned_tabs =
            !taken_over && (!workspace_cleanup_requested || safe_workspace_cleanup);
        if can_remove_owned_tabs && run.owned_tab {
            if let Some(tab_id) = &run.tab_id {
                self.terminate_sessions_for_tab(tab_id).await;
                let _ = self.runtime_store.remove_workspace_tab(tab_id).await;
            }
        }
        if can_remove_owned_tabs && run.setup_tab_id.is_some() {
            if let Some(tab_id) = &run.setup_tab_id {
                self.terminate_sessions_for_tab(tab_id).await;
                let _ = self.runtime_store.remove_workspace_tab(tab_id).await;
            }
        }
        if taken_over {
            let _ = self
                .runtime_store
                .insert_automation_audit_event(
                    Some(&run.automation_id),
                    Some(&run.id),
                    "cleanupPreserved",
                    AutomationActor {
                        kind: AutomationActorKind::ManagedAgent,
                        id: run.actor_id.clone(),
                        label: Some("automation cleanup guard".to_string()),
                    },
                    None,
                    Value::String("automation target was taken over by a user".to_string()),
                )
                .await;
        } else if run.owned_workspace
            && automation.cleanup_policy
                == Some(alera_core::runtime::AutomationCleanupPolicy::OnSuccess)
            && !safe_workspace_cleanup
        {
            let _ = self
                .runtime_store
                .insert_automation_audit_event(
                    Some(&run.automation_id),
                    Some(&run.id),
                    "cleanupPreserved",
                    AutomationActor {
                        kind: AutomationActorKind::ManagedAgent,
                        id: run.actor_id.clone(),
                        label: Some("automation cleanup guard".to_string()),
                    },
                    None,
                    Value::String(
                        "managed workspace ownership or cleanliness could not be proven"
                            .to_string(),
                    ),
                )
                .await;
        }
        if automation.cleanup_policy
            != Some(alera_core::runtime::AutomationCleanupPolicy::OnSuccess)
        {
            return;
        }
        if safe_workspace_cleanup {
            if let Some(workspace_id) = &run.workspace_id {
                let has_live_session = self
                    .sessions
                    .values()
                    .any(|session| session.workspace_id == *workspace_id && session.running());
                let has_live_browser = self.browser.has_pages_for_workspace(workspace_id);
                if has_live_session
                    || has_live_browser
                    || self.mutation_queue.has_runtime_mutations()
                {
                    let reason = if has_live_session {
                        "managed workspace still has a live terminal session or process"
                    } else if has_live_browser {
                        "managed workspace still has a live browser session"
                    } else {
                        "another runtime mutation is in progress"
                    };
                    let _ = self
                        .runtime_store
                        .insert_automation_audit_event(
                            Some(&run.automation_id),
                            Some(&run.id),
                            "cleanupPreserved",
                            AutomationActor {
                                kind: AutomationActorKind::ManagedAgent,
                                id: run.actor_id.clone(),
                                label: Some("automation cleanup guard".to_string()),
                            },
                            None,
                            Value::String(reason.to_string()),
                        )
                        .await;
                    return;
                }
                let _ = crate::managed_workspace::remove_managed_workspace(
                    &self.runtime_store,
                    crate::managed_workspace::ManagedWorkspaceRemoveRequest {
                        id: workspace_id.clone(),
                        delete_branch: Some(true),
                        active_workspace_id: None,
                        close_sessions: false,
                    },
                )
                .await;
            }
        }
    }

    async fn automation_tab_is_owned(&self, tab_id: Option<&str>, run_id: &str) -> bool {
        let Some(tab_id) = tab_id else {
            return true;
        };
        self.runtime_store
            .find_workspace_tab(tab_id)
            .await
            .ok()
            .flatten()
            .is_some_and(|tab| {
                tab.payload.get("automationRunId").and_then(Value::as_str) == Some(run_id)
                    && tab.payload.get("automationOwned").and_then(Value::as_bool) == Some(true)
            })
    }

    async fn automation_workspace_is_untouched(
        &self,
        run: &AutomationRun,
        automation: &alera_core::runtime::AutomationDefinition,
    ) -> bool {
        let Some(workspace_id) = run.workspace_id.as_deref() else {
            return false;
        };
        let Some(workspace) = self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .ok()
            .flatten()
        else {
            return false;
        };
        if run.workspace_branch.as_deref() != workspace.branch.as_deref()
            || workspace.status != alera_core::runtime::WorkspaceStatus::Active
        {
            return false;
        }
        let alera_core::runtime::AutomationTarget::ManagedWorkspace {
            source_workspace_id,
            name_template,
            ..
        } = &automation.target
        else {
            return false;
        };
        if workspace.parent_workspace_id.as_deref() != Some(source_workspace_id.as_str())
            || workspace.name != render_workspace_name(name_template, automation, run)
            || workspace.created_at < run.created_at
        {
            return false;
        }
        let tabs = match self.runtime_store.list_workspace_tabs(workspace_id).await {
            Ok(tabs) => tabs,
            Err(_) => return false,
        };
        if tabs.iter().any(|tab| {
            Some(tab.id.as_str()) != run.tab_id.as_deref()
                && Some(tab.id.as_str()) != run.setup_tab_id.as_deref()
        }) {
            return false;
        }
        alera_core::git::current_branch(&workspace.path)
            .ok()
            .as_deref()
            == run.workspace_branch.as_deref()
            && alera_core::git::is_worktree_clean(&workspace.path).unwrap_or(false)
    }

    pub(super) async fn resolve_execution_actor(
        &self,
        run_id: &str,
        actor: AutomationActor,
        identity: &AutomationTargetIdentity,
    ) -> HostResult<AutomationActor> {
        let run = self
            .runtime_store
            .find_automation_run(run_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation run not found: {run_id}")))?;
        if actor.kind == AutomationActorKind::LocalCli
            && run.actor_kind == Some(AutomationActorKind::ManagedAgent)
        {
            let bound = run
                .target_identity
                .as_ref()
                .ok_or_else(|| HostError::state("automation run has no target identity"))?;
            if !bound.matches(identity) {
                return Err(HostError::state(
                    "automation run target identity does not match the live run",
                ));
            }
            return Ok(AutomationActor {
                kind: AutomationActorKind::ManagedAgent,
                id: bound.profile_id.clone(),
                label: Some("managed automation agent".to_string()),
            });
        }
        Ok(actor)
    }

    pub(super) async fn verify_live_target_identity(
        &self,
        client_id: u64,
        identity: &AutomationTargetIdentity,
    ) -> HostResult<()> {
        let session_id = identity.session_id.clone().or_else(|| {
            identity.tab_id.as_deref().and_then(|tab_id| {
                self.sessions
                    .iter()
                    .find(|(_, session)| session.tab_id == tab_id)
                    .map(|(session_id, _)| session_id.clone())
            })
        });
        let Some(session_id) = session_id else {
            return Err(HostError::state(
                "automation target has no live terminal session",
            ));
        };
        let session = self
            .sessions
            .get(&session_id)
            .ok_or_else(|| HostError::state("automation target session is no longer live"))?;
        let attached = session.clients.contains(&client_id);
        let client = self.clients.get(&client_id);
        let cli_has_terminal_proof = client.is_some_and(|client| {
            client.kind == super::ClientKind::Local
                && client.local_role == super::client_delivery::LocalClientRole::Cli
                && identity.terminal_handle.as_deref() == Some(session_id.as_str())
        });
        if !attached
            && !cli_has_terminal_proof
            && !client.is_some_and(|client| {
                client.kind == super::ClientKind::Mobile
                    || (client.kind == super::ClientKind::Local
                        && client.local_role == super::client_delivery::LocalClientRole::App)
            })
        {
            return Err(HostError::state(
                "automation caller is not authorized for the target terminal",
            ));
        }
        if identity
            .terminal_handle
            .as_deref()
            .is_some_and(|handle| handle != session_id.as_str())
            || identity
                .workspace_id
                .as_deref()
                .is_some_and(|workspace| workspace != session.workspace_id)
            || identity
                .tab_id
                .as_deref()
                .is_some_and(|tab| tab != session.tab_id)
        {
            return Err(HostError::state(
                "automation target identity does not match the live terminal",
            ));
        }
        if let Some(tab_id) = identity.tab_id.as_deref() {
            let tab = self
                .runtime_store
                .find_workspace_tab(tab_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| HostError::state("automation target tab is missing"))?;
            if identity
                .workspace_id
                .as_deref()
                .is_some_and(|workspace| workspace != tab.workspace_id)
            {
                return Err(HostError::state(
                    "automation target workspace does not match the live tab",
                ));
            }
            if identity
                .profile_id
                .as_deref()
                .is_some_and(|profile| agent_profile_id(&tab) != Some(profile))
                || identity
                    .conversation_id
                    .as_deref()
                    .is_some_and(|conversation| {
                        tab.payload.get("conversationId").and_then(Value::as_str)
                            != Some(conversation)
                    })
            {
                return Err(HostError::state(
                    "automation target profile or conversation does not match the live tab",
                ));
            }
            if let Some(session_id) = identity.session_id.as_deref() {
                let tab_session_id = terminal_session_id_from_tab(&tab);
                if tab_session_id.as_deref() != Some(session_id) {
                    return Err(HostError::state(
                        "automation target session does not match the live tab",
                    ));
                }
            }
        }
        Ok(())
    }
}

pub(super) fn actor_for_circuit_reset(run: &AutomationRun) -> AutomationActor {
    AutomationActor {
        kind: AutomationActorKind::ManagedAgent,
        id: run.actor_id.clone(),
        label: Some("Alera Automation Circuit Breaker".to_string()),
    }
}

pub(super) fn requested_target_identity(payload: &Value) -> HostResult<AutomationTargetIdentity> {
    let source = payload
        .get("targetIdentity")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_else(|| payload.as_object().cloned().unwrap_or_default());
    let string = |key: &str| {
        source
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
    };
    let identity = AutomationTargetIdentity {
        workspace_id: string("workspaceId"),
        tab_id: string("tabId"),
        session_id: string("sessionId"),
        profile_id: string("profileId"),
        conversation_id: string("conversationId"),
        terminal_handle: string("terminalHandle"),
    };
    if identity.is_empty() {
        return Err(HostError::format(
            "exact automation target identity is required",
        ));
    }
    Ok(identity)
}

fn is_durable_lifecycle_fallback(result: &HostResult<()>) -> bool {
    result.as_ref().err().is_some_and(|error| {
        matches!(
            error.wire_message().as_str(),
            "automation target has no live terminal session"
                | "automation target session is no longer live"
        )
    })
}

#[cfg(test)]
mod tests {
    use super::{is_durable_lifecycle_fallback, requested_target_identity};
    use crate::terminal_host::host_error::HostError;
    use serde_json::json;

    #[test]
    fn durable_lifecycle_fallback_only_accepts_missing_live_sessions() {
        assert!(is_durable_lifecycle_fallback(&Err(HostError::state(
            "automation target has no live terminal session",
        ))));
        assert!(is_durable_lifecycle_fallback(&Err(HostError::state(
            "automation target session is no longer live",
        ))));
        assert!(!is_durable_lifecycle_fallback(&Err(HostError::state(
            "automation caller is not authorized for the target terminal",
        ))));
        assert!(!is_durable_lifecycle_fallback(&Ok(())));
    }

    #[test]
    fn target_identity_requires_a_nonempty_identity() {
        assert!(requested_target_identity(&json!({})).is_err());
        assert!(requested_target_identity(&json!({
            "targetIdentity": {"tabId": "tab-1", "sessionId": "session-1"}
        }))
        .is_ok());
    }
}

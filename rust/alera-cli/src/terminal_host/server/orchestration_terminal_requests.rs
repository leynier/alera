use alera_core::runtime::OrchestrationDispatchStatus;
use serde_json::{json, Value};
use std::collections::BTreeSet;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;

use super::orchestration_validation::{optional_string, require_string, state_error};
use super::ServerActor;

impl ServerActor {
    pub(super) fn orchestration_terminals(&self, payload: &Value) -> Value {
        let workspace = optional_string(payload, "workspace");
        let terminals: Vec<Value> = self
            .sessions
            .iter()
            .filter(|(_, session)| {
                workspace
                    .as_ref()
                    .is_none_or(|workspace| &session.workspace_id == workspace)
            })
            .map(|(session_id, session)| {
                let presence = self.agent_presence.get(session_id);
                json!({
                    "handle": session_id,
                    "workspaceId": session.workspace_id,
                    "tabId": session.tab_id,
                    "running": session.running(),
                    "agentType": presence.map(|entry| entry.agent_type.clone()),
                    "agentState": presence.map(|entry| entry.state.as_str()),
                    "stateStartedAt": presence.map(|entry| entry.state_started_at),
                    "updatedAt": presence.map(|entry| entry.updated_at),
                    "prompt": presence.map(|entry| entry.prompt.clone()),
                    "toolName": presence.and_then(|entry| entry.tool_name.clone()),
                    "toolInput": presence.and_then(|entry| entry.tool_input.clone()),
                    "lastAssistantMessage": presence.and_then(|entry| entry.last_assistant_message.clone()),
                    "interrupted": presence.and_then(|entry| entry.interrupted),
                })
            })
            .collect();
        json!({
            "kind": "terminals",
            "items": terminals,
            "terminals": terminals,
            "filters": { "workspace": workspace },
        })
    }

    pub(super) async fn orchestration_terminal_show(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let handle = require_string(payload, "handle")?;
        let session = self
            .sessions
            .get(&handle)
            .ok_or_else(|| HostError::state(format!("terminal not found: {handle}")))?;
        let presence = self.agent_presence.get(&handle);
        let active_dispatch = self
            .runtime_store
            .active_orchestration_dispatch_for_handle(&handle)
            .await
            .map_err(state_error)?;
        let dispatch = match active_dispatch {
            Some(dispatch) => Some(dispatch),
            None => self
                .runtime_store
                .latest_orchestration_dispatch_for_handle(&handle)
                .await
                .map_err(state_error)?,
        };
        let spawn_failure = self
            .runtime_store
            .find_workspace_tab(&session.tab_id)
            .await
            .map_err(state_error)?
            .and_then(|tab| {
                let recorded = tab
                    .payload
                    .pointer("/orchestrationSpawn/startupFailureRecorded")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                recorded.then(|| {
                    tab.payload
                        .pointer("/orchestrationSpawn/startupFailureReason")
                        .and_then(Value::as_str)
                        .unwrap_or("agent startup failed")
                        .to_string()
                })
            });
        let startup_state = match dispatch.as_ref().map(|value| value.status) {
            _ if !session.running() => "failed",
            Some(OrchestrationDispatchStatus::AwaitingAcceptance) => {
                "dispatch_submitted_unconfirmed"
            }
            Some(OrchestrationDispatchStatus::Dispatched) => "accepted",
            Some(OrchestrationDispatchStatus::Completed) => "completed",
            Some(OrchestrationDispatchStatus::StartupFailed) => "failed",
            Some(OrchestrationDispatchStatus::Stalled) => "stalled",
            _ if spawn_failure.is_some() => "failed",
            _ if presence.is_some_and(|entry| entry.state == AgentPresenceState::Done) => {
                "agent_ready"
            }
            _ if presence.is_some() => "agent_detected",
            _ => "process_started",
        };
        Ok(json!({
            "handle": handle,
            "workspaceId": session.workspace_id,
            "tabId": session.tab_id,
            "running": session.running(),
            "agentType": presence.map(|entry| entry.agent_type.clone()),
            "agentState": presence.map(|entry| entry.state.as_str()),
            "startupState": startup_state,
            "startupError": dispatch
                .as_ref()
                .and_then(|value| value.startup_error.clone())
                .or(spawn_failure),
            "dispatch": dispatch,
        }))
    }

    pub(super) async fn orchestration_terminal_prune(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let workspace = optional_string(payload, "workspace");
        let apply = payload
            .get("apply")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let mut handles: BTreeSet<String> = self
            .sessions
            .iter()
            .filter(|(_, session)| {
                !session.running()
                    && workspace
                        .as_ref()
                        .is_none_or(|workspace| &session.workspace_id == workspace)
            })
            .map(|(handle, _)| handle.clone())
            .collect();
        handles.extend(
            self.retained_failed_spawn_handles(workspace.as_deref())
                .await?,
        );
        let handles: Vec<String> = handles.into_iter().collect();
        let mut removed = Vec::new();
        if apply {
            for handle in &handles {
                if self.prune_stopped_terminal(handle).await? {
                    removed.push(handle.clone());
                }
            }
            self.schedule_shutdown_if_idle();
        }
        Ok(json!({
            "dryRun": !apply,
            "workspaceId": workspace,
            "candidates": handles,
            "removed": removed,
        }))
    }

    async fn prune_stopped_terminal(&mut self, handle: &str) -> HostResult<bool> {
        if self
            .sessions
            .get(handle)
            .is_some_and(|session| session.running())
        {
            return Ok(false);
        }
        if !self.sessions.contains_key(handle) {
            let Some(tab) = self
                .runtime_store
                .find_workspace_tab(handle)
                .await
                .map_err(state_error)?
            else {
                return Ok(false);
            };
            let retained = tab
                .payload
                .pointer("/orchestrationSpawn/retainedAfterFailure")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            if tab.kind != "terminal" || !retained {
                return Ok(false);
            }
            self.runtime_store
                .remove_workspace_tab(&tab.id)
                .await
                .map_err(state_error)?;
            self.store.delete(handle).await.map_err(state_error)?;
            self.remove_dispatch_context(handle);
            self.broadcast_authenticated(crate::terminal_host::protocol::event(
                "workspaceTabsChanged",
                json!({}),
            ));
            return Ok(true);
        }
        self.cleanup_orchestration_for_closed_session(handle, "terminal pruned")
            .await;
        if self.remove_terminal_session_tab(handle).await? {
            return Ok(true);
        }

        self.flush_all_output(handle);
        self.await_output_writes(handle).await;
        let Some(mut session) = self.sessions.remove(handle) else {
            return Ok(false);
        };
        session.terminate(true, &self.store).await;
        Ok(true)
    }

    async fn retained_failed_spawn_handles(
        &self,
        workspace: Option<&str>,
    ) -> HostResult<Vec<String>> {
        let workspace_ids = match workspace {
            Some(workspace) => vec![workspace.to_string()],
            None => self
                .runtime_store
                .list_all_workspaces()
                .await
                .map_err(state_error)?
                .into_iter()
                .map(|workspace| workspace.id)
                .collect(),
        };
        let mut handles = Vec::new();
        for workspace_id in workspace_ids {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace_id)
                .await
                .map_err(state_error)?;
            handles.extend(tabs.into_iter().filter_map(|tab| {
                let retained = tab
                    .payload
                    .pointer("/orchestrationSpawn/retainedAfterFailure")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                if tab.kind != "terminal" || !retained {
                    return None;
                }
                let handle = tab
                    .payload
                    .get("terminalSessionId")
                    .and_then(Value::as_str)
                    .unwrap_or(&tab.id)
                    .to_string();
                (!self
                    .sessions
                    .get(&handle)
                    .is_some_and(|session| session.running()))
                .then_some(handle)
            }));
        }
        Ok(handles)
    }
}

use alera_core::runtime::OrchestrationDispatchStatus;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;

use super::orchestration_validation::{require_string, state_error};
use super::ServerActor;

impl ServerActor {
    pub(super) fn orchestration_terminals(&self) -> Value {
        let terminals: Vec<Value> = self
            .sessions
            .iter()
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
        json!({ "kind": "terminals", "items": terminals, "terminals": terminals, "filters": {} })
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
        let startup_state = match dispatch.as_ref().map(|value| value.status) {
            _ if !session.running() => "failed",
            Some(OrchestrationDispatchStatus::AwaitingAcceptance) => {
                "dispatch_submitted_unconfirmed"
            }
            Some(OrchestrationDispatchStatus::Dispatched) => "accepted",
            Some(OrchestrationDispatchStatus::Completed) => "completed",
            Some(OrchestrationDispatchStatus::StartupFailed) => "failed",
            Some(OrchestrationDispatchStatus::Stalled) => "stalled",
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
            "startupError": dispatch.as_ref().and_then(|value| value.startup_error.clone()),
            "dispatch": dispatch,
        }))
    }
}

//! `agentPresence.link`: binds a running agent to a tab again after its hooks
//! stopped reaching that tab.

use serde_json::{json, Value};

use crate::agent_status::{event_agent_pid, is_supported_hook_agent, AgentHookEvent};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_hook_links::AgentHookLink;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_session_resume::{
    ccs_profile_from_config_dir, native_session_id, usable_native_session_id,
};
use crate::terminal_host::orchestration::claude_subagent_roster::ClaudeSubagentRoster;
use crate::terminal_host::session::process_is_terminal_multiplexer;

use super::ServerActor;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct AgentLinkRequest {
    pub tab_id: String,
    pub agent_type: String,
    pub native_session_id: Option<String>,
    pub agent_pid: Option<u32>,
    pub state: AgentPresenceState,
    pub source_terminal_session_id: Option<String>,
    pub ccs_profile: Option<String>,
}

pub(super) fn parse_agent_link_request(payload: &Value) -> HostResult<AgentLinkRequest> {
    let tab_id =
        optional_string(payload, "tabId").ok_or_else(|| HostError::format("tabId is required."))?;
    let agent_type = optional_string(payload, "agentType")
        .ok_or_else(|| HostError::format("agentType is required."))?;
    if !is_supported_hook_agent(&agent_type) {
        return Err(HostError::format(format!(
            "Unsupported agent type: {agent_type}."
        )));
    }
    let native_session_id = match optional_string(payload, "nativeSessionId") {
        Some(id) => Some(
            usable_native_session_id(&id)
                .ok_or_else(|| HostError::format("nativeSessionId is not a usable session id."))?
                .to_string(),
        ),
        None => None,
    };
    let agent_pid = match payload.get("agentPid").filter(|value| !value.is_null()) {
        Some(value) => Some(
            value
                .as_u64()
                .and_then(|pid| u32::try_from(pid).ok())
                .filter(|pid| *pid > 0)
                .ok_or_else(|| HostError::format("agentPid must be a positive process id."))?,
        ),
        None => None,
    };
    let state = match optional_string(payload, "state") {
        Some(state) => AgentPresenceState::parse(&state).ok_or_else(|| {
            HostError::format("state must be one of working, waiting, blocked, done.")
        })?,
        None => AgentPresenceState::Working,
    };
    let ccs_profile = optional_string(payload, "claudeConfigDir")
        .filter(|_| agent_type == "claude")
        .and_then(|dir| ccs_profile_from_config_dir(&dir).map(str::to_string));
    Ok(AgentLinkRequest {
        tab_id,
        agent_type,
        native_session_id,
        agent_pid,
        state,
        source_terminal_session_id: optional_string(payload, "sourceTerminalSessionId"),
        ccs_profile,
    })
}

impl ServerActor {
    pub(super) async fn link_agent_presence(&mut self, payload: &Value) -> HostResult<Value> {
        let request = parse_agent_link_request(payload)?;
        let Some((handle, workspace_id, process_group)) = self
            .sessions
            .values()
            .find(|session| session.tab_id == request.tab_id && session.running())
            .map(|session| {
                (
                    session.id.clone(),
                    session.workspace_id.clone(),
                    session.agent_process_group(),
                )
            })
        else {
            return Err(HostError::state(format!(
                "Tab {} has no running terminal on this runtime.",
                request.tab_id
            )));
        };

        // The previous identity is what made the host drop this agent's
        // hooks, so the link starts from a clean presence.
        if self
            .agent_presence
            .agent_type(&handle)
            .is_some_and(|current| current != request.agent_type)
        {
            self.agent_presence.remove(&handle);
        }
        let now = chrono::Utc::now();
        let state_started_at = self
            .agent_presence
            .get(&handle)
            .filter(|presence| presence.state == request.state)
            .map(|presence| presence.state_started_at)
            .unwrap_or(now);
        self.orchestration_agent_status(&json!({
            "entries": [{
                "terminalSessionId": handle,
                "workspaceId": workspace_id,
                "tabId": request.tab_id,
                "agentType": request.agent_type,
                "state": request.state.as_str(),
                "stateStartedAt": state_started_at,
                "updatedAt": now,
            }],
        }))
        .await?;
        let multiplexed = process_group.is_some_and(process_is_terminal_multiplexer);
        if let Some(presence) = self.agent_presence.get_mut(&handle) {
            presence.native_session_id = request.native_session_id.clone();
            presence.agent_pid = request.agent_pid;
            presence.process_group = if multiplexed { None } else { process_group };
            presence.local_hook = !multiplexed;
            presence.turn_id = None;
            presence.inferred_idle = false;
            presence.claude_subagents = ClaudeSubagentRoster::default();
        }

        if let Some(session_id) = request.native_session_id.as_deref() {
            self.store_tab_native_session(
                &request.tab_id,
                &request.agent_type,
                session_id,
                request.ccs_profile.as_deref(),
            )
            .await;
        }

        let identified = request.native_session_id.is_some() || request.agent_pid.is_some();
        let rerouted_from = match request.source_terminal_session_id {
            Some(source) if source != handle && identified => {
                self.agent_hook_links.link(AgentHookLink {
                    source_terminal_session_id: source.clone(),
                    agent_type: request.agent_type.clone(),
                    native_session_id: request.native_session_id.clone(),
                    agent_pid: request.agent_pid,
                    target_terminal_session_id: handle.clone(),
                });
                Some(source)
            }
            Some(source) if source == handle => {
                self.agent_hook_links.unlink_target(&handle);
                None
            }
            _ => None,
        };

        Ok(json!({
            "terminalSessionId": handle,
            "workspaceId": workspace_id,
            "tabId": request.tab_id,
            "agentType": request.agent_type,
            "state": request.state.as_str(),
            "nativeSessionId": request.native_session_id,
            "agentPid": request.agent_pid,
            "reroutedFrom": rerouted_from,
        }))
    }

    /// Hands a hook whose launch environment names another terminal to the tab
    /// the agent was linked to. Relayed hooks keep the satellite's identity.
    pub(super) fn reroute_linked_hook(&mut self, event: &mut AgentHookEvent) {
        let sessions = &self.sessions;
        self.agent_hook_links.retain_targets(|target| {
            sessions
                .get(target)
                .is_some_and(|session| session.running())
        });
        let Some(target) = self.agent_hook_links.target_for(
            &event.terminal_session_id,
            &event.agent_type,
            native_session_id(&event.payload),
            event_agent_pid(&event.payload),
        ) else {
            return;
        };
        let Some(session) = self.sessions.get(&target) else {
            return;
        };
        event.terminal_session_id = target;
        event.workspace_id = session.workspace_id.clone();
        event.tab_id = session.tab_id.clone();
    }
}

fn optional_string(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

#[cfg(test)]
#[path = "agent_presence_link_tests.rs"]
mod tests;

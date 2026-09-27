use serde_json::json;

use crate::agent_status::{
    event_agent_pid, event_runs_in_multiplexer, event_turn_id, hook_event_closes_session,
    hook_event_resets_session, hook_identifies_child_agent, normalize_hook_event,
    resolve_agent_status_identity, AgentHookEvent, AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
};
use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};
use crate::terminal_host::orchestration::agent_session_resume::native_session_id;
use crate::terminal_host::session::{
    process_alive, process_group_alive, process_is_terminal_multiplexer,
};

use super::terminal_startup_commands::tab_agent_type;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn handle_agent_hook_event(
        &mut self,
        mut event: AgentHookEvent,
        relayed: bool,
    ) {
        let Ok(settings) = self.runtime_store.agent_status_hook_settings().await else {
            return;
        };
        let Some(session) = self.sessions.get(&event.terminal_session_id) else {
            return;
        };
        if event.agent_type == "fx" && event.workspace_id.is_empty() && event.tab_id.is_empty() {
            event.workspace_id = session.workspace_id.clone();
            event.tab_id = session.tab_id.clone();
        }
        if session.tab_id != event.tab_id {
            return;
        }
        // Published before this runtime's own settings are consulted: a hub
        // that proxies the terminal decides with the settings the user keeps
        // there, which this host may not share.
        self.broadcast_authenticated_local(crate::terminal_host::protocol::event(
            super::remote_agent_presence_relay::AGENT_HOOK_EVENT,
            super::remote_agent_presence_relay::hook_event_payload(&event),
        ));
        if session.workspace_id != event.workspace_id {
            let Ok(Some(tab)) = self.runtime_store.find_workspace_tab(&session.tab_id).await else {
                return;
            };
            if !tab.payload["handoffSourceWorkspaceIds"]
                .as_array()
                .is_some_and(|ids| ids.contains(&json!(event.workspace_id)))
            {
                return;
            }
            // A live process keeps its launch environment after ownership moves.
            event.workspace_id = session.workspace_id.clone();
        }
        let pending_prompt = self
            .runtime_store
            .find_workspace_tab(&session.tab_id)
            .await
            .ok()
            .flatten()
            .and_then(|tab| tab.payload.get("pendingAgentPrompt").cloned())
            .is_some_and(|pending| {
                pending.get("agent").and_then(serde_json::Value::as_str)
                    == Some(event.agent_type.as_str())
            });
        let home_session = alera_core::runtime::is_voice_home_workspace_id(&session.workspace_id);
        if !settings.is_enabled(&event.agent_type) && !pending_prompt && !home_session {
            return;
        }
        let now = chrono::Utc::now();
        let previous = self.agent_presence.get(&event.terminal_session_id);
        if hook_from_nested_conversation(previous, &event, now, relayed) {
            return;
        }
        let child = hook_identifies_child_agent(&event);
        if child && (hook_event_resets_session(&event) || hook_event_closes_session(&event)) {
            return;
        }
        if hook_event_closes_session(&event) && !closes_current_conversation(previous, &event) {
            return;
        }
        self.observe_hook_native_session(&event).await;
        self.observe_hook_title(&event).await;
        if hook_event_resets_session(&event) {
            if self
                .agent_presence
                .get(&event.terminal_session_id)
                .is_none()
            {
                return;
            }
            let _ = self
                .orchestration_agent_status(&json!({
                    "entries": [{
                        "terminalSessionId": event.terminal_session_id,
                        "removed": true,
                    }],
                }))
                .await;
            return;
        }
        if hook_event_closes_session(&event) {
            let previous = self.agent_presence.get(&event.terminal_session_id);
            let previous_agent = previous.map(|presence| presence.agent_type.clone());
            let previous_is_none = previous.is_none();
            let identity = resolve_agent_status_identity(
                previous,
                &event.agent_type,
                AgentPresenceState::Done,
                now,
                AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
            );
            if identity.should_ignore_event {
                return;
            }
            if self.voice.home_session_id.as_deref() == Some(event.terminal_session_id.as_str()) {
                let matches_home = if let Some(agent) = previous_agent {
                    agent == event.agent_type
                } else {
                    let tab_id = self
                        .sessions
                        .get(&event.terminal_session_id)
                        .map(|session| session.tab_id.clone());
                    match tab_id {
                        Some(tab_id) => self
                            .runtime_store
                            .find_workspace_tab(&tab_id)
                            .await
                            .ok()
                            .flatten()
                            .and_then(|tab| tab_agent_type(&tab).map(str::to_string))
                            .is_some_and(|agent| agent == event.agent_type),
                        None => false,
                    }
                };
                if matches_home {
                    self.voice.home_cli_exited = true;
                }
            }
            if previous_is_none {
                return;
            }
            let _ = self
                .orchestration_agent_status(&json!({
                    "entries": [{
                        "terminalSessionId": event.terminal_session_id,
                        "removed": true,
                    }],
                }))
                .await;
            return;
        }
        let previous = self.agent_presence.get(&event.terminal_session_id);
        let Some(normalized) = normalize_hook_event(&event, previous) else {
            return;
        };
        if child && !child_event_applies(previous, normalized.state) {
            return;
        }
        if normalized.state == AgentPresenceState::Done && reports_an_older_turn(previous, &event) {
            return;
        }
        let identity = resolve_agent_status_identity(
            previous,
            &event.agent_type,
            normalized.state,
            now,
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        if identity.should_ignore_event {
            return;
        }
        let state_started_at = previous
            .filter(|entry| entry.state == normalized.state)
            .map(|entry| entry.state_started_at)
            .unwrap_or(now);
        let _ = self
            .orchestration_agent_status(&json!({
                "entries": [{
                    "terminalSessionId": event.terminal_session_id,
                    "workspaceId": event.workspace_id,
                    "tabId": event.tab_id,
                    "agentType": identity.effective_agent_type,
                    "state": normalized.state.as_str(),
                    "stateStartedAt": state_started_at,
                    "updatedAt": now,
                    "prompt": normalized.prompt,
                    "toolName": normalized.tool_name,
                    "toolInput": normalized.tool_input,
                    "lastAssistantMessage": normalized.last_assistant_message,
                    "interrupted": normalized.interrupted,
                    "inferredIdle": normalized.inferred_idle,
                }],
            }))
            .await;
        if !relayed && !child {
            self.record_local_hook_liveness(&event, normalized.state);
        }
        self.deliver_pending_agent_prompt(&event.terminal_session_id)
            .await;
    }

    /// Remembers which conversation and which foreground process group the
    /// presence belongs to, so the reconciliation sweep can tell when that
    /// agent is gone even though no hook said so.
    fn record_local_hook_liveness(&mut self, event: &AgentHookEvent, state: AgentPresenceState) {
        let process_group = self
            .sessions
            .get(&event.terminal_session_id)
            .and_then(|session| session.agent_process_group());
        let session_id = native_session_id(&event.payload).map(str::to_string);
        let turn_id = event_turn_id(event).map(str::to_string);
        let multiplexed = event_runs_in_multiplexer(&event.payload)
            || process_group.is_some_and(process_is_terminal_multiplexer);
        let Some(presence) = self.agent_presence.get_mut(&event.terminal_session_id) else {
            return;
        };
        // Inside a multiplexer the PTY's process group and output belong to
        // its client: detaching would read as an exit, a hidden window as
        // silence. Leave that presence to the agent's own hooks.
        presence.local_hook = !multiplexed;
        if multiplexed {
            presence.process_group = None;
        } else if process_group.is_some() {
            presence.process_group = process_group;
        }
        if let Some(pid) = event_agent_pid(&event.payload) {
            presence.agent_pid = Some(pid);
        }
        if session_id.is_some() {
            presence.native_session_id = session_id;
        }
        if turn_id.is_some() && state != AgentPresenceState::Done {
            presence.turn_id = turn_id;
        }
    }
}

/// An agent that the tab's agent runs as a tool (`codex exec`, `claude -p`)
/// inherits the tab's environment and reports through the same hooks, and
/// must not flip the tab's state or rebind the conversation it resumes.
///
/// When both sides name their process (Claude's `CLAUDE_PID`), another live
/// agent process is nested whatever the tab's state. Otherwise, while the
/// tab's conversation is mid-turn, a different conversation id is nested,
/// unless the process group that turn ran in is gone (the agent was
/// relaunched). Sub-agent hooks are part of the tab's agent and pass; the
/// caller limits what they may change.
fn hook_from_nested_conversation(
    previous: Option<&AgentPresence>,
    event: &AgentHookEvent,
    now: chrono::DateTime<chrono::Utc>,
    relayed: bool,
) -> bool {
    let Some(previous) = previous else {
        return false;
    };
    if hook_identifies_child_agent(event) {
        return false;
    }
    if !relayed {
        if let (Some(current), Some(incoming)) =
            (previous.agent_pid, event_agent_pid(&event.payload))
        {
            return current != incoming && process_alive(current);
        }
        if previous
            .process_group
            .is_some_and(|group| !process_group_alive(group))
        {
            return false;
        }
    }
    if previous.state == AgentPresenceState::Done
        || now.signed_duration_since(previous.updated_at) > AGENT_STATUS_IDENTITY_STALE_THRESHOLD
    {
        return false;
    }
    matches!(
        (previous.native_session_id.as_deref(), native_session_id(&event.payload)),
        (Some(current), Some(incoming)) if current != incoming
    )
}

/// Codex ends a replaced thread only when it unloads it, well after `/new`
/// started the next conversation, so a session end must name the current one.
fn closes_current_conversation(previous: Option<&AgentPresence>, event: &AgentHookEvent) -> bool {
    match (
        previous.and_then(|entry| entry.native_session_id.as_deref()),
        native_session_id(&event.payload),
    ) {
        (Some(current), Some(incoming)) => current == incoming,
        _ => true,
    }
}

/// A sub-agent can ask for attention, and keeps a running turn fresh, but it
/// can neither end the turn nor reopen one: background sub-agents keep
/// working after the main turn reported `done`.
fn child_event_applies(previous: Option<&AgentPresence>, state: AgentPresenceState) -> bool {
    match state {
        AgentPresenceState::Done => false,
        AgentPresenceState::Working => previous
            .is_some_and(|entry| entry.state != AgentPresenceState::Done && !entry.inferred_idle),
        AgentPresenceState::Waiting | AgentPresenceState::Blocked => true,
    }
}

fn reports_an_older_turn(previous: Option<&AgentPresence>, event: &AgentHookEvent) -> bool {
    matches!(
        (previous.and_then(|entry| entry.turn_id.as_deref()), event_turn_id(event)),
        (Some(current), Some(incoming)) if current != incoming
    )
}

#[cfg(test)]
#[path = "agent_hook_events_tests.rs"]
mod tests;

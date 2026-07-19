use serde_json::json;

use crate::agent_status::{normalize_hook_event, AgentHookEvent};

use super::ServerActor;

impl ServerActor {
    pub(super) async fn handle_agent_hook_event(&mut self, event: AgentHookEvent) {
        let Ok(settings) = self.runtime_store.agent_status_hook_settings().await else {
            return;
        };
        if !settings.is_enabled(&event.agent_type) {
            return;
        }
        let Some(session) = self.sessions.get(&event.terminal_session_id) else {
            return;
        };
        if session.workspace_id != event.workspace_id || session.tab_id != event.tab_id {
            return;
        }
        let previous = self.agent_presence.get(&event.terminal_session_id);
        let Some(normalized) = normalize_hook_event(&event, previous) else {
            return;
        };
        if normalized.resets_session || normalized.closes_session {
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
        let now = chrono::Utc::now();
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
                    "agentType": event.agent_type,
                    "state": normalized.state.as_str(),
                    "stateStartedAt": state_started_at,
                    "updatedAt": now,
                    "prompt": normalized.prompt,
                    "toolName": normalized.tool_name,
                    "toolInput": normalized.tool_input,
                    "lastAssistantMessage": normalized.last_assistant_message,
                    "interrupted": normalized.interrupted,
                }],
            }))
            .await;
    }
}

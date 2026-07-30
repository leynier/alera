use serde_json::json;

use crate::agent_status::{
    hook_event_closes_session, hook_event_resets_session, normalize_hook_event, AgentHookEvent,
};

use super::ServerActor;

impl ServerActor {
    pub(super) async fn handle_agent_hook_event(&mut self, event: AgentHookEvent) {
        let Ok(settings) = self.runtime_store.agent_status_hook_settings().await else {
            return;
        };
        let Some(session) = self.sessions.get(&event.terminal_session_id) else {
            return;
        };
        if session.workspace_id != event.workspace_id || session.tab_id != event.tab_id {
            return;
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
        if !settings.is_enabled(&event.agent_type) && !pending_prompt {
            return;
        }
        if hook_event_resets_session(&event) || hook_event_closes_session(&event) {
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
        self.deliver_pending_agent_prompt(&event.terminal_session_id)
            .await;
    }
}

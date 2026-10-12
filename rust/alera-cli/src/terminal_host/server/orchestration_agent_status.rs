//! Agent status forwarding into orchestration and the terminal list group
//! sends resolve against.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::group_resolution::GroupResolutionTerminal;

use super::ServerActor;

impl ServerActor {
    pub(super) async fn orchestration_agent_status(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let Some(entries) = payload.get("entries").and_then(Value::as_array) else {
            return Err(HostError::format("entries must be an array."));
        };
        let mut became_ready = Vec::new();
        for entry in entries {
            let Some(handle) = entry
                .get("terminalSessionId")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
            else {
                continue;
            };
            let removed = entry
                .get("removed")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            if removed {
                self.cleanup_orchestration_for_closed_session(handle, "agent status was removed")
                    .await;
                continue;
            }
            let Some(state) = entry
                .get("state")
                .and_then(Value::as_str)
                .and_then(AgentPresenceState::parse)
            else {
                continue;
            };
            let agent_type = entry
                .get("agentType")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
                .to_string();
            let started_at = self.agent_presence_timestamp(entry);
            let previous = self.agent_presence.get(handle);
            let changed = previous.is_none_or(|previous| {
                previous.state != state || previous.state_started_at != started_at
            });
            let updated_at = entry
                .get("updatedAt")
                .and_then(Value::as_str)
                .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())
                .map(|value| value.with_timezone(&chrono::Utc))
                .unwrap_or_else(chrono::Utc::now);
            let presence = AgentPresence {
                agent_type: agent_type.clone(),
                state,
                state_started_at: started_at,
                updated_at,
                prompt: entry
                    .get("prompt")
                    .and_then(Value::as_str)
                    .map(str::to_string)
                    .or_else(|| previous.map(|value| value.prompt.clone()))
                    .unwrap_or_default(),
                tool_name: optional_status_string(entry, "toolName")
                    .or_else(|| previous.and_then(|value| value.tool_name.clone())),
                tool_input: optional_status_string(entry, "toolInput")
                    .or_else(|| previous.and_then(|value| value.tool_input.clone())),
                last_assistant_message: optional_status_string(entry, "lastAssistantMessage")
                    .or_else(|| previous.and_then(|value| value.last_assistant_message.clone())),
                interrupted: entry
                    .get("interrupted")
                    .and_then(Value::as_bool)
                    .or_else(|| previous.and_then(|value| value.interrupted)),
                native_session_id: previous.and_then(|value| value.native_session_id.clone()),
                process_group: previous.and_then(|value| value.process_group),
                agent_pid: previous.and_then(|value| value.agent_pid),
                turn_id: previous.and_then(|value| value.turn_id.clone()),
                local_hook: previous.is_some_and(|value| value.local_hook),
                inferred_idle: entry
                    .get("inferredIdle")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                claude_subagents: previous
                    .map(|value| value.claude_subagents.clone())
                    .unwrap_or_default(),
            };
            let accepts_injection = presence.accepts_injection();
            self.agent_presence.update_full(handle, presence);
            self.queue_agent_push(handle, &agent_type, state, started_at, changed)
                .await;
            if let Ok(Some(dispatch)) = self
                .runtime_store
                .active_orchestration_dispatch_for_handle(handle)
                .await
            {
                self.record_dispatch_activity(&dispatch).await;
            }
            if accepts_injection && self.voice_home_ready_transition(handle, changed) {
                became_ready.push(handle.to_string());
            }
        }
        for handle in became_ready {
            self.dispatch_pending_agent_spawn(&handle).await;
            self.deliver_home_ready_queues(&handle).await;
        }
        self.broadcast_agent_presence_changed();
        Ok(json!({}))
    }

    async fn dispatch_pending_agent_spawn(&mut self, handle: &str) {
        let Some(session) = self.sessions.get(handle) else {
            return;
        };
        let tab_id = session.tab_id.clone();
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(&tab_id).await else {
            return;
        };
        let Some(pending) = tab.payload.get("pendingOrchestration").cloned() else {
            return;
        };
        if pending.is_null() {
            return;
        }
        let Some(task) = pending.get("task").and_then(Value::as_str) else {
            return;
        };
        let Some(from) = pending.get("from").and_then(Value::as_str) else {
            return;
        };
        let dispatch_payload = json!({
            "task": task,
            "to": handle,
            "from": from,
            "inject": true,
            "forceSubmit": pending
                .get("agent")
                .and_then(Value::as_str)
                .and_then(adapter_for)
                .is_some_and(|adapter| adapter.force_submit),
            "agentProfile": pending.get("profile").cloned(),
            "agentQuotaGroup": pending.get("quotaGroup").cloned(),
            "terminalPolicy": "keep-open",
        });
        if self.orchestration_dispatch(&dispatch_payload).await.is_ok() {
            tab.payload["pendingOrchestration"] = Value::Null;
            tab.updated_at = chrono::Utc::now();
            let workspace_id = tab.workspace_id.clone();
            let tab_id = tab.id.clone();
            // Dropping this leaves the tab claiming a dispatch it already
            // consumed, so a restart replays the prompt.
            if let Err(error) = self.runtime_store.upsert_workspace_tab(tab).await {
                tracing::error!(
                    tab_id = %tab_id,
                    "failed to clear the pending orchestration payload: {error}"
                );
            }
            self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        }
    }

    // --- terminals ---------------------------------------------------------

    pub(super) fn group_resolution_terminals(&self) -> Vec<GroupResolutionTerminal> {
        self.sessions
            .iter()
            .filter(|(_, session)| session.running())
            .map(|(session_id, session)| GroupResolutionTerminal {
                handle: session_id.clone(),
                workspace_id: Some(session.workspace_id.clone()),
            })
            .collect()
    }
}

fn optional_status_string(entry: &Value, key: &str) -> Option<String> {
    entry
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

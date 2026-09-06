use alera_core::runtime::WorkspaceTabRecord;
use serde_json::Value;

use crate::agent_status::AgentHookEvent;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;

use super::agent_title_state::AgentTitleState;
use super::ServerActor;

#[derive(Default)]
struct TitleActivity {
    work_started: bool,
    session_started: bool,
}

pub(super) fn conversation_id(payload: &Value) -> Option<&str> {
    [
        "conversation_id",
        "conversationId",
        "session_id",
        "sessionId",
        "sessionID",
        "thread_id",
        "threadId",
    ]
    .iter()
    .find_map(|key| {
        payload
            .get(key)
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
    })
}

impl ServerActor {
    pub(super) async fn initialize_agent_title_if_new(
        &self,
        tab: &mut WorkspaceTabRecord,
    ) -> HostResult<()> {
        if self
            .runtime_store
            .find_workspace_tab(&tab.id)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .is_none()
        {
            super::agent_title_state::initialize(tab, "");
        }
        Ok(())
    }

    pub(super) async fn observe_hook_title(&mut self, event: &AgentHookEvent) {
        if event.payload["agentTitleIgnore"] == true {
            return;
        }
        let normalized = crate::agent_status::normalize_hook_event(event, None);
        let identity = crate::agent_status::resolve_agent_status_identity(
            self.agent_presence.get(&event.terminal_session_id),
            &event.agent_type,
            normalized
                .as_ref()
                .map_or(AgentPresenceState::Done, |s| s.state),
            chrono::Utc::now(),
            crate::agent_status::AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        // Compatibility hooks can carry a different native ID as well as an alias.
        if identity.should_ignore_event || identity.effective_agent_type != event.agent_type {
            return;
        }
        // Child-agent hooks can share the parent's PTY identity.
        if ["parent_session_id", "parentSessionId", "parentThreadId"]
            .iter()
            .any(|key| {
                event
                    .payload
                    .get(key)
                    .and_then(Value::as_str)
                    .is_some_and(|id| !id.is_empty())
            })
        {
            return;
        }
        if crate::agent_status::hook_event_closes_session(event) {
            self.close_agent_title_conversation(event).await;
            return;
        }
        // Do not inherit an activity prompt from a previous turn or conversation.
        let prompt = normalized
            .as_ref()
            .map(|status| status.prompt.as_str())
            .unwrap_or("");
        let session_started = super::agent_title_state::hook_starts_conversation(event);
        let work_started = normalized
            .as_ref()
            .is_some_and(|status| status.state == AgentPresenceState::Working)
            && !session_started;
        self.observe_agent_title_event(
            &event.tab_id,
            &event.agent_type,
            conversation_id(&event.payload),
            prompt,
            TitleActivity {
                work_started: work_started || !prompt.is_empty(),
                session_started,
            },
        )
        .await;
    }

    pub(super) async fn observe_agent_title(
        &mut self,
        tab_id: &str,
        agent: &str,
        native_id: Option<&str>,
        prompt: &str,
        work_started: bool,
    ) {
        self.observe_agent_title_event(
            tab_id,
            agent,
            native_id,
            prompt,
            TitleActivity {
                work_started,
                ..Default::default()
            },
        )
        .await;
    }

    async fn observe_agent_title_event(
        &mut self,
        tab_id: &str,
        agent: &str,
        native_id: Option<&str>,
        prompt: &str,
        activity: TitleActivity,
    ) {
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(tab_id).await else {
            return;
        };
        let session_id =
            super::requests::terminal_session_id_from_tab(&tab).unwrap_or_else(|| tab.id.clone());
        let cursor = self
            .sessions
            .get(&session_id)
            .map(|s| s.output_stream_range().1)
            .unwrap_or(0);
        let mut state = AgentTitleState::read(&tab).unwrap_or_else(|| AgentTitleState::new(false));
        let previous = state.clone();
        let previous_id = state.conversation_id.clone();
        if activity.session_started {
            state.resume(agent, native_id, cursor);
        }
        if !state.observe(agent, native_id, prompt, cursor) {
            return;
        }
        if previous_id != state.conversation_id {
            self.cancel_agent_title_job(tab_id);
            tab.payload["agentTitleStatus"] = Value::String("idle".into());
        } else if tab.payload["agentTitleStatus"] == "generating"
            && !self.agent_title_jobs.contains_key(tab_id)
        {
            // A host restart must not replay an already-attempted generation.
            tab.payload["agentTitleStatus"] = Value::String("failed".into());
        }
        if state == previous && !(activity.work_started && state.eligible && !state.attempted) {
            return;
        }
        state.write(&mut tab);
        if self
            .runtime_store
            .upsert_workspace_tab(tab.clone())
            .await
            .is_err()
        {
            return;
        }
        self.broadcast_workspace_tabs_changed(Some(&tab.workspace_id));
        if activity.work_started {
            let _ = self.queue_agent_title(tab, state, None).await;
        }
    }

    async fn close_agent_title_conversation(&mut self, event: &AgentHookEvent) {
        let tab_id = &event.tab_id;
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(tab_id).await else {
            return;
        };
        let Some(mut state) = AgentTitleState::read(&tab) else {
            return;
        };
        if state.closed
            || state.agent.as_deref() != Some(event.agent_type.as_str())
            || matches!((state.native_id.as_deref(), conversation_id(&event.payload)), (Some(current), Some(incoming)) if current != incoming)
        {
            return;
        }
        self.cancel_agent_title_job(tab_id);
        tab.payload["agentTitleStatus"] = Value::String("idle".into());
        state.closed = true;
        state.write(&mut tab);
        let workspace_id = tab.workspace_id.clone();
        if self.runtime_store.upsert_workspace_tab(tab).await.is_ok() {
            self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        }
    }
}

use serde_json::Value;

use super::ServerActor;

impl ServerActor {
    /// Types a prompt into an agent that reported it is idle.
    ///
    /// fx has no interactive initial-prompt argument. Its lifecycle receiver
    /// reports the first idle state after the TUI is ready, which makes this
    /// PTY paste deterministic. Older tabs may also still carry the payload.
    pub(super) async fn deliver_pending_agent_prompt(&mut self, session_id: &str) {
        if !self.agent_presence.is_injection_ready(session_id) {
            return;
        }
        if self.voice.home_session_id.as_deref() == Some(session_id)
            && (self.voice.home_inject.is_some() || self.voice.home_needs_fresh_ready)
        {
            return;
        }
        let Some(session) = self.sessions.get(session_id) else {
            return;
        };
        if session.initial_agent_prompt_delivered {
            return;
        }
        let tab_id = session.tab_id.clone();
        let instance_id = session.instance_id();
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(&tab_id).await else {
            return;
        };
        let Some(pending) = tab.payload.get("pendingAgentPrompt").cloned() else {
            return;
        };
        let Some(prompt) = pending.get("prompt").and_then(Value::as_str) else {
            return;
        };
        let matches_agent = pending
            .get("agent")
            .and_then(Value::as_str)
            .is_some_and(|agent| self.agent_presence.agent_type(session_id) == Some(agent));
        if !matches_agent {
            return;
        }
        let bytes =
            crate::terminal_host::orchestration::agent_prompt_injection::build_agent_prompt_paste_bytes(
                prompt,
            );
        let Some(session) = self.sessions.get_mut(session_id) else {
            return;
        };
        if session
            .queue_write_deferred(
                crate::terminal_host::session::PtyWriteCompletion::OrchestrationPaste {
                    session_instance_id: instance_id,
                    message_ids: Vec::new(),
                    force_submit: true,
                },
                &bytes,
                std::time::Duration::from_millis(
                    crate::terminal_host::orchestration::message_delivery::DEFERRED_ENTER_DELAY_MS,
                ),
                crate::terminal_host::orchestration::agent_prompt_injection::AGENT_PROMPT_SUBMIT,
            )
            .is_err()
        {
            return;
        }
        if self.voice.home_session_id.as_deref() == Some(session_id) {
            self.voice.home_needs_fresh_ready = true;
        }
        session.initial_agent_prompt_delivered = true;
        tab.payload["pendingAgentPrompt"] = Value::Null;
        tab.updated_at = chrono::Utc::now();
        let workspace_id = tab.workspace_id.clone();
        if let Err(error) = self.runtime_store.upsert_workspace_tab(tab).await {
            tracing::error!(tab_id = %tab_id, "failed to clear pending agent prompt: {error}");
        }
        self.broadcast_workspace_tabs_changed(Some(&workspace_id));
    }
}

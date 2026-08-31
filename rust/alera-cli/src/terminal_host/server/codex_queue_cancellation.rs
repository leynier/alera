use super::codex_queue::store_error;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::CodexChatDeliveryState;
use serde_json::{json, Value};

impl ServerActor {
    pub(super) async fn codex_queue_close_snapshot(
        &self,
        state: &CodexChatDeliveryState,
    ) -> HostResult<Value> {
        let mut snapshot = state.snapshot();
        snapshot["otherQueues"] = json!(self
            .runtime_store
            .list_codex_chat_states()
            .await
            .map_err(store_error)?
            .iter()
            .filter(|other| other.tab_id == state.tab_id
                && other.thread_id != state.thread_id
                && (other.has_pending() || other.history_locked()))
            .map(|other| json!({"threadId":other.thread_id,"revision":other.revision}))
            .collect::<Vec<_>>());
        Ok(snapshot)
    }

    pub(super) async fn cancel_codex_tab_queues(
        &mut self,
        state: CodexChatDeliveryState,
        payload: &Value,
    ) -> HostResult<Value> {
        let mut states: Vec<_> = self
            .runtime_store
            .list_codex_chat_states()
            .await
            .map_err(store_error)?
            .into_iter()
            .filter(|other| {
                other.tab_id == state.tab_id
                    && other.thread_id != state.thread_id
                    && (other.has_pending() || other.history_locked())
            })
            .collect();
        let expected = payload
            .get("otherQueues")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        if states.len() != expected.len()
            || states.iter().any(|other| {
                !expected.iter().any(|item| {
                    item["threadId"] == other.thread_id && item["revision"] == other.revision
                })
            })
        {
            return Err(HostError::state(
                "A queue from another conversation in this tab changed. Confirm closing again.",
            ));
        }
        states.push(state);
        if states.iter().any(|state| {
            state.history_locked()
                || state
                    .messages
                    .iter()
                    .any(|entry| matches!(entry.status.as_str(), "sending" | "uncertain"))
        }) {
            return Err(HostError::state(
                "Confirm outstanding deliveries and finish history edits before closing this tab.",
            ));
        }
        let mut canceled = Vec::new();
        for state in &mut states {
            state.paused = true;
            for entry in &mut state.messages {
                if !matches!(entry.status.as_str(), "accepted" | "removed") {
                    canceled.push(entry.payload.clone());
                    entry.status = "removed".into();
                    entry.payload = json!({});
                }
            }
            if !state.thread_id.is_empty() {
                self.save_codex_delivery(state).await?;
            }
        }
        for payload in canceled {
            if let Err(error) = self.release_codex_attachments(&payload).await {
                tracing::warn!("Could not release canceled Codex attachments: {error}");
            }
        }
        Ok(states.last().unwrap().snapshot())
    }
}

use chrono::Utc;
use serde_json::{json, Value};

use alera_core::runtime::OrchestrationMessageType;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::inbox_requests::inbox_error;
use super::orchestration_validation::require_string;
use super::ServerActor;

/// Inbox writes that change existing questions: cancel, mark read, purge.
impl ServerActor {
    pub(super) async fn inbox_cancel(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let question_id = require_string(payload, "questionId")?;
        // A batch being pasted still reads as queued until its Enter lands;
        // cancelling then would report a question the agent already received.
        let recipient = self
            .runtime_store
            .orchestration_message_by_id(&question_id)
            .await
            .map_err(inbox_error)?
            .map(|question| question.to_handle);
        if recipient.is_some_and(|handle| self.orchestration_delivery_in_flight.contains(&handle)) {
            return Err(HostError::conflict(
                "inbox_not_cancellable",
                "The question is being delivered to the agent right now.",
                json!({}),
            ));
        }
        let mut cancellation = self.inbox_origin(client_id);
        cancellation["at"] = json!(Utc::now());
        let message = self
            .runtime_store
            .cancel_inbox_question(&question_id, cancellation)
            .await
            .map_err(inbox_error)?;
        let inbox = message.from_handle.clone();
        self.notify_message_arrived(&inbox, OrchestrationMessageType::Status)
            .await;
        Ok(json!({ "message": message, "revision": self.inbox_revision().await? }))
    }

    pub(super) async fn inbox_mark_read(&self, payload: &Value) -> HostResult<Value> {
        let marked = if payload.get("threadId").is_some() || payload.get("questionId").is_some() {
            let thread_id = self.requested_thread_id(payload).await?;
            self.mark_thread_read(&thread_id).await?
        } else {
            let ids: Vec<String> = payload
                .get("ids")
                .and_then(Value::as_array)
                .ok_or_else(|| HostError::format("threadId or ids is required."))?
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect();
            self.runtime_store
                .mark_inbox_messages_read(&ids)
                .await
                .map_err(inbox_error)?
        };
        Ok(json!({ "marked": marked, "revision": self.inbox_revision().await? }))
    }

    pub(super) async fn inbox_purge(&mut self, payload: &Value) -> HostResult<Value> {
        let inbox = require_string(payload, "inbox")?;
        let deleted = self
            .runtime_store
            .purge_inbox(&inbox)
            .await
            .map_err(inbox_error)?;
        self.notify_message_arrived(&inbox, OrchestrationMessageType::Status)
            .await;
        Ok(json!({ "deleted": deleted, "revision": self.inbox_revision().await? }))
    }
}

use alera_core::runtime::ConversationFilter;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::inbox_requests::inbox_error;
use super::orchestration_validation::{optional_string, require_string};
use super::ServerActor;

impl ServerActor {
    /// Read-only view of what agents say to each other. It never marks
    /// anything read, because an agent's `read` flag means it consumed the
    /// message.
    pub(super) async fn inbox_conversations(&self, payload: &Value) -> HostResult<Value> {
        let filter = ConversationFilter {
            workspace_id: optional_string(payload, "workspaceId"),
            participant: optional_string(payload, "participant"),
            before_sequence: payload.get("before").and_then(Value::as_i64),
            limit: payload.get("limit").and_then(Value::as_i64).unwrap_or(50),
        };
        let page = self
            .runtime_store
            .conversation_threads(filter.clone())
            .await
            .map_err(inbox_error)?;
        Ok(json!({
            "kind": "conversations",
            "items": page.items,
            "nextBefore": page.next_before,
            "filters": {
                "workspaceId": filter.workspace_id,
                "participant": filter.participant,
            },
            "revision": self.conversation_revision().await?,
        }))
    }

    pub(super) async fn inbox_conversation(&self, payload: &Value) -> HostResult<Value> {
        let thread_id = require_string(payload, "threadId")?;
        let messages = self
            .runtime_store
            .conversation_thread(&thread_id)
            .await
            .map_err(inbox_error)?;
        if messages.is_empty() {
            return Err(HostError::conflict(
                "inbox_thread_not_found",
                format!("No conversation {thread_id}"),
                json!({}),
            ));
        }
        Ok(json!({
            "threadId": thread_id,
            "messages": messages,
            "revision": self.conversation_revision().await?,
        }))
    }

    async fn conversation_revision(&self) -> HostResult<i64> {
        self.runtime_store
            .conversation_revision()
            .await
            .map_err(inbox_error)
    }

    pub(super) async fn broadcast_conversation_change(&self) {
        if let Ok(Some(revision)) = self.runtime_store.take_conversation_change().await {
            self.broadcast_authenticated(event(
                "conversationsChanged",
                json!({ "revision": revision }),
            ));
        }
    }
}

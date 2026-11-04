use alera_core::runtime::{AgentChatReadOutcome, AgentChatReceipt};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{CallerCtx, ReceiptKey};
use super::events::ChatRuntimeEvent;
use super::ids::receipt_scope;
use super::runtime_handle::AgentChatRuntime;
use super::session_ops::receipt_conflict;

impl AgentChatRuntime {
    pub(crate) async fn mark_read(
        &self,
        chat_id: &str,
        cursor: i64,
        ctx: CallerCtx,
        key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        let (response, changed) = if let Some(key) = key {
            let receipt = AgentChatReceipt {
                caller_scope: receipt_scope(&ctx.scope, &key.verb),
                request_id: key.request_id,
                digest: key.digest,
                receipt: Value::Null,
            };
            match self
                .store()
                .mark_agent_chat_read_with_receipt(chat_id, cursor, &receipt)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                AgentChatReadOutcome::Applied(response) => (response, true),
                AgentChatReadOutcome::Replay(response) => (response, false),
                AgentChatReadOutcome::ReceiptConflict => return Err(receipt_conflict()),
            }
        } else {
            let cursor = self
                .store()
                .mark_agent_chat_read(chat_id, cursor)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            (json!({"cursor":cursor,"readCursor":cursor}), true)
        };
        if changed {
            let workspace_id = self
                .store()
                .agent_chat(chat_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .map(|chat| chat.workspace_id);
            self.publish_runtime_event(ChatRuntimeEvent::ChatsChanged { workspace_id })
                .await;
        }
        Ok(response)
    }
}

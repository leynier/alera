//! `chatOrchestration.updateTitle` (`agentChatTitleGenerationV1`): rename or
//! regenerate a chat's title. A bound agent acts on its own chat, or on a
//! chat it owns through delegation; it never replaces a title a person set.

use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::ChatOp;

use super::authorization::{require_lineage_for_chat, OrchestrationCaller};
use super::queries::runtime_receipt_key;
use super::service::ChatOrchestrationService;

/// The chat a title request acts on: the named one, or the bound caller's.
pub(super) fn title_target(
    caller: &OrchestrationCaller,
    chat_id: Option<&str>,
) -> HostResult<String> {
    chat_id
        .map(str::to_owned)
        .or_else(|| caller.bound.as_ref().map(|bound| bound.chat_id.clone()))
        .ok_or_else(|| HostError::format("chatId is required"))
}

impl ChatOrchestrationService {
    pub(super) async fn update_title(
        &self,
        chat_id: Option<String>,
        request_id: String,
        title: Option<String>,
        payload: &Value,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        if let Some(response) = self
            .check_receipt(caller, "updateTitle", &request_id, payload)
            .await?
        {
            return Ok(response);
        }
        let chat_id = title_target(caller, chat_id.as_deref())?;
        require_lineage_for_chat(caller, &self.store, &chat_id).await?;
        let person = caller.bound.is_none();
        let operation = match title {
            Some(title) if person => ChatOp::Rename { title },
            Some(title) => ChatOp::RenameByAgent { title },
            None => ChatOp::RegenerateTitle {
                replace_user_title: person,
            },
        };
        let key = runtime_receipt_key(
            &caller.ctx.scope,
            "updateTitle",
            &request_id,
            &chat_id,
            &operation,
        );
        let result = self
            .runtime
            .command(&chat_id, operation, caller.ctx.clone(), Some(key))
            .await?;
        self.record_receipt(caller, "updateTitle", &request_id, payload, result.clone())
            .await?;
        Ok(result)
    }
}

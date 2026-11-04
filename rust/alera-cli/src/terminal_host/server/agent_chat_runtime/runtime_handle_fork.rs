//! Receipt replay before loading a source chat, including after deletion.

use alera_core::runtime::AgentChatReceiptCheck;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{CallerCtx, ChatOp, ReceiptKey};
use super::ids::{new_id, receipt_scope};
use super::runtime_handle::AgentChatRuntime;
use super::session_ops::receipt_conflict;

impl AgentChatRuntime {
    async fn history_receipt_replay(
        &self,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> HostResult<Option<Value>> {
        let Some(key) = key else {
            return Ok(None);
        };
        match self
            .store()
            .check_agent_chat_receipt(
                &receipt_scope(&ctx.scope, &key.verb),
                &key.request_id,
                &key.digest,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            AgentChatReceiptCheck::New => Ok(None),
            AgentChatReceiptCheck::Replay(response) => Ok(Some(response)),
            AgentChatReceiptCheck::Conflict => Err(receipt_conflict()),
        }
    }

    pub(crate) async fn fork(
        &self,
        chat_id: &str,
        turn_id: &str,
        title: Option<String>,
        ctx: CallerCtx,
        key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        if let Some(response) = self.history_receipt_replay(&ctx, key.as_ref()).await? {
            return Ok(response);
        }
        self.command(
            chat_id,
            ChatOp::Fork {
                turn_id: turn_id.into(),
                new_chat_id: uuid::Uuid::new_v4().to_string(),
                new_tab_id: new_id("tab"),
                title,
            },
            ctx,
            key,
        )
        .await
    }

    /// `agentChat.mergeBack`: hands a fork's work since the fork point to
    /// the chat it was forked from, for that chat's next turn.
    pub(crate) async fn merge_back(
        &self,
        chat_id: &str,
        ctx: CallerCtx,
        key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        if let Some(response) = self.history_receipt_replay(&ctx, key.as_ref()).await? {
            return Ok(response);
        }
        let source = self
            .command(chat_id, ChatOp::MergeBackSource, ctx.clone(), None)
            .await?;
        let field = |key: &str| source[key].as_str().unwrap_or_default().to_owned();
        let target = field("sourceChatId");
        self.command(
            &target,
            ChatOp::ReceiveMergeBack(super::session_merge_back::MergeBackInput {
                from_chat_id: chat_id.to_owned(),
                from_title: field("title"),
                text: field("text"),
            }),
            ctx,
            key,
        )
        .await
    }

    pub(crate) async fn rewind(
        &self,
        chat_id: &str,
        turn_id: &str,
        ctx: CallerCtx,
        key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        if let Some(response) = self.history_receipt_replay(&ctx, key.as_ref()).await? {
            return Ok(response);
        }
        self.command(
            chat_id,
            ChatOp::Rewind {
                turn_id: turn_id.into(),
            },
            ctx,
            key,
        )
        .await
    }

    pub(crate) async fn delete(
        &self,
        chat_id: &str,
        ctx: CallerCtx,
        key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        if let Some(response) = self.history_receipt_replay(&ctx, key.as_ref()).await? {
            return Ok(response);
        }
        self.command(chat_id, ChatOp::Delete, ctx, key).await
    }
}

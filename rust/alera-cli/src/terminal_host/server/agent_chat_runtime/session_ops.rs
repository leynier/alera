//! Command dispatch: an idempotency check before every mutation, then the
//! operation, then one commit that carries the change and its receipt.

use alera_core::runtime::{AgentChatDeleteOutcome, AgentChatReceipt, AgentChatReceiptCheck};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, unsupported, CallerCtx, ChatEnvelope, ChatOp, ReceiptKey};
use super::events::ChatRuntimeEvent;
use super::ids::receipt_scope;
use super::session::ChatSession;

pub(crate) fn receipt_conflict() -> HostError {
    conflict(
        "request_conflict",
        "This requestId was already used for a different request.",
    )
}

impl ChatSession {
    pub(super) fn ensure_mode_ceiling(
        &self,
        runtime_mode_ceiling: &str,
        requested_mode: Option<&str>,
    ) -> HostResult<()> {
        let current = super::super::chat_orchestration::authorization::mode_rank(
            &self.header.session.runtime_mode,
        )
        .ok_or_else(|| HostError::format("unknown runtime mode"))?;
        let ceiling =
            super::super::chat_orchestration::authorization::mode_rank(runtime_mode_ceiling)
                .ok_or_else(|| HostError::format("unknown runtime mode ceiling"))?;
        if current > ceiling {
            return Err(conflict(
                "mode_ceiling",
                "The chat runtime mode exceeds the caller's mode ceiling.",
            ));
        }
        if let Some(requested_mode) = requested_mode {
            let requested =
                super::super::chat_orchestration::authorization::mode_rank(requested_mode)
                    .ok_or_else(|| HostError::format("unknown requested runtime mode"))?;
            if requested > ceiling {
                return Err(conflict(
                    "mode_ceiling",
                    "The requested chat runtime mode exceeds the caller's mode ceiling.",
                ));
            }
        }
        Ok(())
    }

    pub(super) async fn handle_envelope(&mut self, envelope: ChatEnvelope) {
        let ChatEnvelope {
            op,
            ctx,
            receipt_key,
            reply,
        } = envelope;
        if let Some(key) = &receipt_key {
            match Self::check_receipt(self.deps.store.clone(), &ctx, key).await {
                Ok(Some(response)) => {
                    let _ = reply.send(Ok(response));
                    return;
                }
                Ok(None) => {}
                Err(error) => {
                    let _ = reply.send(Err(error));
                    return;
                }
            }
        }
        if let Err(error) = self.guard_native_operation(&op, &ctx, receipt_key.as_ref()) {
            let _ = reply.send(Err(error));
            return;
        }
        if let Some(result) = self
            .dispatch_native_history(&op, &ctx, receipt_key.as_ref())
            .await
        {
            let _ = reply.send(result);
            return;
        }
        let history_result = match &op {
            ChatOp::Fork {
                turn_id,
                new_chat_id,
                new_tab_id,
                title,
            } => Some(
                self.fork_history(
                    turn_id,
                    new_chat_id,
                    new_tab_id,
                    title.as_deref(),
                    &ctx,
                    receipt_key.as_ref(),
                )
                .await,
            ),
            ChatOp::Rewind { turn_id } => Some(
                self.rewind_history(turn_id, &ctx, receipt_key.as_ref())
                    .await,
            ),
            ChatOp::Delete => Some(self.delete_history(&ctx, receipt_key.as_ref()).await),
            _ => None,
        };
        if let Some(result) = history_result {
            let _ = reply.send(result);
            return;
        }
        if matches!(op, ChatOp::Close) && self.never_sent() {
            match self.discard_draft(&ctx, receipt_key.as_ref()).await {
                Ok(Some(response)) => {
                    let _ = reply.send(Ok(response));
                    return;
                }
                Err(error) => {
                    let _ = reply.send(Err(error));
                    return;
                }
                Ok(None) => {}
            }
        }
        let mutates = op.mutates();
        let snapshot_response = match &op {
            ChatOp::Configure(_)
            | ChatOp::Recover { .. }
            | ChatOp::NativeFileCheckpoints { .. } => true,
            ChatOp::WithinCeiling { operation, .. } => {
                matches!(operation.as_ref(), ChatOp::Configure(_))
            }
            _ => false,
        };
        let result = self.dispatch(op, &ctx).await;
        let result = match result {
            Ok(mut response) if mutates => {
                if snapshot_response {
                    // Snapshot helpers already flushed the projection. The receipt
                    // commit adds one cursor step, which its replay must also carry.
                    if receipt_key.is_some() {
                        response["cursor"] = json!(self.committed.cursor + 1);
                    }
                    response = json!({"snapshot": response});
                }
                if let Some(key) = &receipt_key {
                    self.receipt = Some(AgentChatReceipt {
                        caller_scope: receipt_scope(&ctx.scope, &key.verb),
                        request_id: key.request_id.clone(),
                        digest: key.digest.clone(),
                        receipt: response.clone(),
                    });
                }
                match self.flush().await {
                    Ok(()) => Ok(response),
                    Err(error) => Err(HostError::state(format!(
                        "The chat change could not be saved: {error}"
                    ))),
                }
            }
            other => {
                if mutates {
                    let _ = self.flush().await;
                }
                other
            }
        };
        let _ = reply.send(result);
    }

    pub(crate) async fn check_receipt(
        store: alera_core::runtime::RuntimeStore,
        ctx: &CallerCtx,
        key: &ReceiptKey,
    ) -> HostResult<Option<Value>> {
        let scope = receipt_scope(&ctx.scope, &key.verb);
        let request_id = key.request_id.clone();
        let digest = key.digest.clone();
        match store
            .check_agent_chat_receipt(&scope, &request_id, &digest)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            AgentChatReceiptCheck::New => Ok(None),
            AgentChatReceiptCheck::Replay(response) => Ok(Some(response)),
            AgentChatReceiptCheck::Conflict => Err(receipt_conflict()),
        }
    }

    async fn dispatch(&mut self, op: ChatOp, ctx: &CallerCtx) -> HostResult<Value> {
        let archived_allowed = matches!(
            op,
            ChatOp::Snapshot
                | ChatOp::History { .. }
                | ChatOp::ApprovalHistory { .. }
                | ChatOp::TurnDiff { .. }
                | ChatOp::NativeHistoryOperation { .. }
                | ChatOp::Rename { .. }
                | ChatOp::Reopen { .. }
                | ChatOp::Close
                | ChatOp::Stop
                | ChatOp::CancelMessage { .. }
                | ChatOp::WithinCeiling { .. }
                | ChatOp::Shutdown
        );
        if self.header.archived && !archived_allowed {
            return Err(conflict(
                "chatArchived",
                "This chat is closed. Reopen it first.",
            ));
        }
        match op {
            ChatOp::Snapshot => self.snapshot().await,
            ChatOp::History { before, limit } => self.history(&before, limit).await,
            ChatOp::ApprovalHistory { before, limit } => {
                self.approval_history(before.as_deref(), limit).await
            }
            ChatOp::TurnDiff { turn_id } => self.turn_diff(&turn_id).await,
            ChatOp::NativeHistoryOperation { operation_id } => {
                self.native_history_operation_status(operation_id.as_deref())
                    .await
            }
            ChatOp::NativeFileCheckpoints { enabled } => {
                self.configure_file_checkpoints(enabled).await
            }
            ChatOp::Send(input) => self.send(input, ctx).await,
            ChatOp::SendDecliningRequests { input, request_ids } => {
                self.send_declining(input, &request_ids, ctx).await
            }
            ChatOp::SendWithinCeiling {
                mut input,
                runtime_mode_ceiling,
            } => {
                self.ensure_mode_ceiling(&runtime_mode_ceiling, None)?;
                input.runtime_mode_ceiling = Some(runtime_mode_ceiling);
                self.send(input, ctx).await
            }
            ChatOp::WithinCeiling {
                runtime_mode_ceiling,
                operation,
            } => {
                let requested_mode = match operation.as_ref() {
                    ChatOp::Interrupt { .. }
                    | ChatOp::Respond { .. }
                    | ChatOp::CancelMessage { .. } => None,
                    ChatOp::Configure(input) => input.runtime_mode.as_deref(),
                    _ => {
                        return Err(unsupported(
                            "The requested operation is not allowed for this chat binding.",
                        ));
                    }
                };
                self.ensure_mode_ceiling(&runtime_mode_ceiling, requested_mode)?;
                match *operation {
                    ChatOp::Interrupt { turn_id } => self.interrupt(turn_id.as_deref()).await,
                    ChatOp::Respond {
                        runtime_request_id,
                        response,
                    } => self.respond(&runtime_request_id, response, ctx).await,
                    ChatOp::Configure(input) => self.configure(input).await,
                    ChatOp::CancelMessage { client_message_id } => {
                        self.cancel_message(&client_message_id).await
                    }
                    _ => Err(unsupported(
                        "The requested operation is not allowed for this chat binding.",
                    )),
                }
            }
            ChatOp::QueueCancel { queue_id } => Ok(self.cancel_queued(&queue_id)),
            ChatOp::QueueEdit { queue_id, text } => self.edit_queued(&queue_id, text),
            ChatOp::QueueReorder { queue_id, index } => self.reorder_queued(&queue_id, index),
            ChatOp::QueuePromoteToSteer { queue_id, turn_id } => {
                self.promote_queue_to_steer(&queue_id, &turn_id, ctx).await
            }
            ChatOp::CancelMessage { client_message_id } => {
                self.cancel_message(&client_message_id).await
            }
            ChatOp::Interrupt { turn_id } => self.interrupt(turn_id.as_deref()).await,
            ChatOp::AwaitBackgroundTasks { task_ids, awaited } => {
                self.await_background_tasks(task_ids, awaited).await
            }
            ChatOp::Respond {
                runtime_request_id,
                response,
            } => self.respond(&runtime_request_id, response, ctx).await,
            ChatOp::Configure(input) => self.configure(input).await,
            ChatOp::Rename { title } => self.rename(title).await,
            ChatOp::Recover { mode } => self.recover(mode.as_deref()).await,
            ChatOp::Close => self.close_chat().await,
            ChatOp::Reopen { tab_id } => self.reopen(tab_id).await,
            ChatOp::Stop => {
                self.stop_provider("stopped", "The workspace was put to sleep.")
                    .await;
                Ok(json!({"stopped": true}))
            }
            ChatOp::Shutdown => {
                self.shutdown().await;
                Ok(json!({"stopped": true}))
            }
            ChatOp::Fork { .. }
            | ChatOp::Rewind { .. }
            | ChatOp::Delete
            | ChatOp::NativeRewind { .. }
            | ChatOp::NativeRewindFiles { .. }
            | ChatOp::NativeHistoryReconcile { .. } => Err(unsupported(
                "History operations require receipt-aware dispatch.",
            )),
        }
    }

    async fn discard_draft(
        &mut self,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> HostResult<Option<Value>> {
        self.flush().await.map_err(HostError::state)?;
        let response = json!({"chatId":self.header.chat_id,"tabId":self.header.tab_id,"archived":false,"discarded":true});
        let receipt = key.map(|key| AgentChatReceipt {
            caller_scope: receipt_scope(&ctx.scope, &key.verb),
            request_id: key.request_id.clone(),
            digest: key.digest.clone(),
            receipt: response.clone(),
        });
        match self
            .deps
            .store
            .discard_agent_chat_if_never_sent(
                &self.header.chat_id,
                self.committed.cursor,
                receipt.as_ref(),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            AgentChatDeleteOutcome::Deleted => {
                self.closed = true;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::Deleted {
                        chat_id: self.header.chat_id.clone(),
                        workspace_id: self.header.workspace_id.clone(),
                        discarded: true,
                    })
                    .await;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::ChatsChanged {
                        workspace_id: Some(self.header.workspace_id.clone()),
                    })
                    .await;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::TabsChanged {
                        workspace_id: self.header.workspace_id.clone(),
                    })
                    .await;
                Ok(Some(response))
            }
            AgentChatDeleteOutcome::NotNeverSent => Ok(None),
            AgentChatDeleteOutcome::Replay(value) => Ok(Some(value)),
            AgentChatDeleteOutcome::ReceiptConflict => Err(receipt_conflict()),
        }
    }

    async fn rename(&mut self, title: String) -> HostResult<Value> {
        let title = title.trim().chars().take(200).collect::<String>();
        if title.is_empty() {
            return Err(HostError::format("title must not be empty"));
        }
        self.header.title_source = "user".into();
        if title != self.header.title {
            self.header.title = title.clone();
            if !self.header.archived {
                if let Ok(Some(workspace_id)) =
                    self.deps.tabs.rename_tab(&self.header.tab_id, &title).await
                {
                    self.notify_tabs(workspace_id);
                }
            }
            self.notify_chats();
        }
        Ok(json!({"title": title}))
    }

    pub(super) fn notify_chats(&mut self) {
        let notice = ChatRuntimeEvent::ChatsChanged {
            workspace_id: Some(self.header.workspace_id.clone()),
        };
        if !self.notices.contains(&notice) {
            self.notices.push(notice);
        }
    }

    pub(super) fn notify_tabs(&mut self, workspace_id: String) {
        let notice = ChatRuntimeEvent::TabsChanged { workspace_id };
        if !self.notices.contains(&notice) {
            self.notices.push(notice);
        }
    }
}

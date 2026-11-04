//! Finalizes acknowledged operations without repeating external provider calls.

use alera_core::runtime::{
    AgentChatNativeOperation, AgentChatNativeOperationCompleteOutcome, AgentChatReceipt,
    AgentChatReceiptCheck, AGENT_CHAT_NATIVE_REWIND, AGENT_CHAT_NATIVE_REWIND_FILES,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, CallerCtx, ReceiptKey};
use super::events::ChatRuntimeEvent;
use super::header::Header;
use super::ids::{process_epoch, receipt_scope};
use super::session::{ChatSession, CLOSE_TIMEOUT};
use super::session_native_history::{native_outcome, native_pending_error};
use super::session_native_history_recovery::{
    native_operation_freezes, native_operation_public_summary,
};
use super::session_ops::receipt_conflict;

impl ChatSession {
    pub(super) async fn publish_native_operation(&mut self) -> HostResult<()> {
        let value = self
            .native_operation
            .as_ref()
            .filter(|op| native_operation_freezes(op))
            .map(native_operation_public_summary)
            .unwrap_or(Value::Null);
        self.header
            .extra
            .insert("pendingNativeOperation".into(), value);
        self.notify_chats();
        self.flush().await.map_err(HostError::state)
    }

    pub(super) async fn quiesce_native_history(&mut self) {
        self.cancel_startup().await;
        self.events_armed = false;
        self.revoke_launch_credentials("nativeHistoryOperation")
            .await;
        if let Some(mut provider) = self.provider.take() {
            let _ = tokio::time::timeout(CLOSE_TIMEOUT, provider.close()).await;
        }
        self.live_caps = None;
        self.set_status("stopped");
        self.refresh_capabilities();
        self.process_epoch = process_epoch();
        self.native_ids.clear();
        // Losing the process also makes a failed acknowledgment write
        // uncertain. This recovery never issues another native request.
        let _ = self.load_native_history_recovery().await;
    }

    pub(super) async fn complete_native_operation(
        &mut self,
        op: &AgentChatNativeOperation,
        observations: Option<&Value>,
        reconcile_receipt: Option<&AgentChatReceipt>,
        fallback: bool,
    ) -> HostResult<Value> {
        self.quiesce_native_history().await;
        self.publish_native_operation().await?;
        let result = if op.kind == AGENT_CHAT_NATIVE_REWIND {
            let mut next = self.header.clone();
            next.cursor = self
                .committed
                .cursor
                .checked_add(1)
                .ok_or_else(|| HostError::state("The chat cursor is exhausted."))?;
            next.session.generation = self
                .generation
                .checked_add(1)
                .ok_or_else(|| HostError::state("The chat generation is exhausted."))?;
            next.session.status = "stopped".into();
            next.session.active_turn_id = None;
            next.session.error_message = None;
            next.turns.clear();
            next.pending_requests.clear();
            next.queue.clear();
            next.usage = None;
            next.recovery = None;
            next.session.extra.remove("historyOperation");
            next.extra
                .insert("pendingNativeOperation".into(), Value::Null);
            let mut snapshot = next.to_snapshot();
            if fallback {
                snapshot["nativeOperationReconcile"] = json!({"action":"continueFromTranscript"});
            }
            self.deps
                .store
                .complete_agent_chat_native_rewind(
                    &op.chat_id,
                    &op.operation_id,
                    op.revision,
                    self.committed.cursor,
                    &snapshot,
                    reconcile_receipt,
                )
                .await
        } else if op.kind == AGENT_CHAT_NATIVE_REWIND_FILES {
            let observations = if fallback {
                json!({"action":"continueFromCurrentFiles"})
            } else {
                observations.cloned().unwrap_or_else(|| json!({}))
            };
            self.deps
                .store
                .complete_agent_chat_native_files(
                    &op.chat_id,
                    &op.operation_id,
                    op.revision,
                    self.committed.cursor,
                    &observations,
                    reconcile_receipt,
                )
                .await
        } else {
            return Err(native_pending_error(op, true));
        }
        .map_err(|_| native_pending_error(op, false))?;
        match result {
            AgentChatNativeOperationCompleteOutcome::Committed {
                record,
                event,
                response,
            } => {
                self.header =
                    Header::from_snapshot(record.snapshot.clone()).map_err(HostError::state)?;
                self.committed = self.header.clone();
                self.generation = record.generation;
                self.native_thread = record.native_thread_id;
                self.process_epoch = process_epoch();
                self.native_ids.clear();
                self.open_requests.clear();
                self.items.clear();
                self.pending = Default::default();
                self.receipt = None;
                self.message_receipts.clear();
                self.provider_turn_id = None;
                self.deferred_turn = None;
                self.native_fork = None;
                self.fork_source_turn_id = None;
                self.startup_forking = false;
                self.has_items = record.snapshot["items"]
                    .as_array()
                    .is_some_and(|items| !items.is_empty());
                self.handoff_pending = self.has_items && self.native_thread.is_none();
                self.native_operation = None;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::Changed {
                        chat_id: record.chat_id.clone(),
                        workspace_id: record.workspace_id.clone(),
                        cursor: event.cursor,
                        delta: event.delta,
                    })
                    .await;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::ChatsChanged {
                        workspace_id: Some(record.workspace_id),
                    })
                    .await;
                Ok(response)
            }
            AgentChatNativeOperationCompleteOutcome::Replay(response) => Ok(response),
            AgentChatNativeOperationCompleteOutcome::ReceiptConflict => Err(receipt_conflict()),
            AgentChatNativeOperationCompleteOutcome::CursorConflict { current } => {
                Err(HostError::conflict(
                    "cursorConflict",
                    "The chat changed while completing the native operation.",
                    json!({"cursor":current}),
                ))
            }
            AgentChatNativeOperationCompleteOutcome::RevisionConflict { current } => {
                Err(HostError::conflict(
                    "nativeOperationRevisionConflict",
                    "The native operation changed.",
                    json!({"revision":current}),
                ))
            }
        }
    }

    pub(super) async fn reconcile_native_history(
        &mut self,
        operation_id: &str,
        expected_revision: Option<i64>,
        action: &str,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> HostResult<Value> {
        if !matches!(
            action,
            "finishAcknowledged"
                | "restartFromTranscript"
                | "cancelUnstarted"
                | "continueFromCurrentFiles"
        ) {
            return Err(HostError::format(
                "Unknown native history reconciliation action.",
            ));
        }
        let mut op = self
            .deps
            .store
            .agent_chat_native_operation(&self.header.chat_id, operation_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                conflict(
                    "nativeOperationNotFound",
                    "The native operation does not exist.",
                )
            })?;
        if !matches!(
            op.kind.as_str(),
            AGENT_CHAT_NATIVE_REWIND | AGENT_CHAT_NATIVE_REWIND_FILES
        ) {
            return Err(native_pending_error(&op, op.state == "uncertain"));
        }
        if expected_revision.is_some_and(|revision| revision != op.revision) {
            return Err(HostError::conflict(
                "nativeOperationRevisionConflict",
                "The native operation changed.",
                json!({"revision":op.revision}),
            ));
        }
        if op.state == "executing" && self.provider.is_none() {
            op = self
                .transition_native_operation(&op, "uncertain", Some(&json!({"reason":"unknown"})))
                .await?;
        }
        let key =
            key.ok_or_else(|| HostError::format("requestId is required for reconciliation"))?;
        let mut receipt = AgentChatReceipt {
            caller_scope: receipt_scope(&ctx.scope, &key.verb),
            request_id: key.request_id.clone(),
            digest: key.digest.clone(),
            receipt: Value::Null,
        };
        let final_result = if !native_operation_freezes(&op) {
            op.result.clone()
        } else if action == "cancelUnstarted" && op.state == "prepared" {
            let op = native_outcome(
                self.deps
                    .store
                    .transition_agent_chat_native_operation(
                        &op.chat_id,
                        &op.operation_id,
                        op.revision,
                        "cancelled",
                        None,
                    )
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?,
            )?;
            self.quiesce_native_history().await;
            self.native_operation = None;
            self.set_status("stopped");
            self.publish_native_operation().await?;
            op.result
        } else {
            let fallback = op.state == "uncertain"
                && ((action == "restartFromTranscript" && op.kind == AGENT_CHAT_NATIVE_REWIND)
                    || (action == "continueFromCurrentFiles"
                        && op.kind == AGENT_CHAT_NATIVE_REWIND_FILES));
            if !fallback && !(action == "finishAcknowledged" && op.state == "acknowledged") {
                return Err(native_pending_error(
                    &op,
                    op.state == "uncertain" || op.state == "executing",
                ));
            }
            Some(
                self.complete_native_operation(&op, None, Some(&receipt), fallback)
                    .await?,
            )
        };
        let operation = self
            .deps
            .store
            .agent_chat_native_operation(&self.header.chat_id, operation_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .unwrap_or(op);
        let response = json!({"snapshot":self.snapshot().await?,
            "operation":native_operation_public_summary(&operation),"result":final_result});
        // This fills the receipt for prepared cancellation; specialized
        // completions already committed the same wrapper atomically.
        receipt.receipt = response.clone();
        match self
            .deps
            .store
            .record_agent_chat_receipt(Some(&self.header.chat_id), &receipt)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            AgentChatReceiptCheck::New => Ok(response),
            AgentChatReceiptCheck::Replay(response) => Ok(response),
            AgentChatReceiptCheck::Conflict => Err(receipt_conflict()),
        }
    }
}

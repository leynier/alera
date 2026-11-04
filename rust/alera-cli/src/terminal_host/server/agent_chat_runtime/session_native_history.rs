//! Native history uses durable intent and acknowledgment before local mutation.

use std::time::Duration;

use alera_core::runtime::{
    AgentChatNativeOperation, AgentChatNativeOperationInput, AgentChatNativeOperationOutcome,
    AgentChatNativeOperationReceipt, AGENT_CHAT_NATIVE_REWIND, AGENT_CHAT_NATIVE_REWIND_FILES,
};
use alera_provider_protocol::{
    NativeRewindFilesInput, NativeRollbackBoundary, NativeRollbackInput,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, unsupported, CallerCtx, ReceiptKey};
use super::ids::new_id;
use super::session::ChatSession;
use super::session_native_history_recovery::native_operation_public_summary;
use super::session_ops::receipt_conflict;

const NATIVE_HISTORY_TIMEOUT: Duration = Duration::from_secs(30);

pub(super) fn native_pending_error(op: &AgentChatNativeOperation, uncertain: bool) -> HostError {
    HostError::conflict(
        if uncertain {
            "nativeOperationUncertain"
        } else {
            "nativeOperationPending"
        },
        "Reconcile the pending native operation before changing this chat.",
        json!({"operation":native_operation_public_summary(op)}),
    )
}

pub(super) fn native_outcome(
    op: AgentChatNativeOperationOutcome,
) -> HostResult<AgentChatNativeOperation> {
    match op {
        AgentChatNativeOperationOutcome::Applied(op)
        | AgentChatNativeOperationOutcome::Existing(op) => Ok(*op),
        AgentChatNativeOperationOutcome::ReceiptConflict => Err(receipt_conflict()),
        AgentChatNativeOperationOutcome::CursorConflict { current } => Err(HostError::conflict(
            "cursorConflict",
            "The chat changed before the native operation.",
            json!({"cursor":current}),
        )),
        AgentChatNativeOperationOutcome::RevisionConflict { current } => Err(HostError::conflict(
            "nativeOperationRevisionConflict",
            "The native operation changed.",
            json!({"revision":current}),
        )),
        AgentChatNativeOperationOutcome::Busy { .. } => Err(conflict(
            "nativeOperationPending",
            "The chat has pending work.",
        )),
        AgentChatNativeOperationOutcome::Replay(_) => Err(conflict(
            "nativeOperationPending",
            "The operation already completed. Refresh this chat.",
        )),
    }
}

impl ChatSession {
    pub(super) async fn native_rewind(
        &mut self,
        turn_id: &str,
        files: bool,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> HostResult<Value> {
        self.require_idle("rewinding native history")?;
        if self.header.archived {
            return Err(conflict(
                "chatArchived",
                "Reopen this chat before rewinding it.",
            ));
        }
        let caps = self
            .provider
            .as_ref()
            .map(|provider| provider.native_history_capabilities())
            .ok_or_else(|| {
                unsupported("Resume the agent before using a native history operation.")
            })?;
        if (files && !caps.rewind_files) || (!files && !caps.rollback_before_turn) {
            return Err(unsupported(
                "This agent has no verified support for this native operation.",
            ));
        }
        let key =
            key.ok_or_else(|| HostError::format("requestId is required for native history"))?;
        self.flush().await.map_err(HostError::state)?;
        let native = self
            .native_thread
            .clone()
            .filter(|id| !id.starts_with("pending:"))
            .ok_or_else(|| {
                unsupported("The current native session identity has not been observed.")
            })?;
        let boundary = self
            .current_native_boundary(if files { "userTurn" } else { "turn" }, turn_id)
            .await?;
        let input = AgentChatNativeOperationInput {
            operation_id: new_id("operation"),
            chat_id: self.header.chat_id.clone(),
            expected_cursor: self.committed.cursor,
            expected_generation: self.generation,
            expected_native_thread_id: native,
            process_epoch: self.process_epoch.clone(),
            kind: if files {
                AGENT_CHAT_NATIVE_REWIND_FILES
            } else {
                AGENT_CHAT_NATIVE_REWIND
            }
            .into(),
            turn_id: turn_id.into(),
            actor: ctx.actor.clone(),
            boundary: if files {
                json!({"type":"message","id":boundary})
            } else {
                json!({"type":"beforeTurn","value":boundary})
            },
        };
        let receipt = AgentChatNativeOperationReceipt {
            caller_scope: ctx.scope.clone(),
            verb: key.verb.clone(),
            request_id: key.request_id.clone(),
            digest: key.digest.clone(),
        };
        let outcome = self
            .deps
            .store
            .begin_agent_chat_native_operation(&input, &receipt)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let op = match outcome {
            AgentChatNativeOperationOutcome::Replay(value) => return Ok(value),
            AgentChatNativeOperationOutcome::Existing(op) => {
                self.native_operation = Some(*op);
                return Err(native_pending_error(
                    self.native_operation.as_ref().unwrap(),
                    false,
                ));
            }
            outcome => native_outcome(outcome)?,
        };
        self.native_operation = Some(op.clone());
        self.events_armed = false;
        let op = self
            .transition_native_operation(&op, "executing", None)
            .await?;
        if self.publish_native_operation().await.is_err() {
            let _ = self
                .transition_native_operation(&op, "uncertain", Some(&json!({"reason":"unknown"})))
                .await;
            self.quiesce_native_history().await;
            return Err(native_pending_error(
                self.native_operation.as_ref().unwrap_or(&op),
                true,
            ));
        }
        let acknowledgment = if files {
            self.call_native_file_rewind(&op).await
        } else {
            self.call_native_conversation_rewind(&op).await
        };
        let (ack, observations) = match acknowledgment {
            Ok(evidence) => evidence,
            Err(()) => {
                let _ = self
                    .transition_native_operation(
                        &op,
                        "uncertain",
                        Some(&json!({"reason":"providerError"})),
                    )
                    .await;
                self.quiesce_native_history().await;
                let _ = self.publish_native_operation().await;
                return Err(native_pending_error(
                    self.native_operation.as_ref().unwrap_or(&op),
                    true,
                ));
            }
        };
        let op = match self
            .transition_native_operation(&op, "acknowledged", Some(&ack))
            .await
        {
            Ok(op) => op,
            Err(_) => {
                // A failed acknowledgment write cannot justify another external call.
                let _ = self
                    .transition_native_operation(
                        &op,
                        "uncertain",
                        Some(&json!({"reason":"unknown"})),
                    )
                    .await;
                self.quiesce_native_history().await;
                let _ = self.publish_native_operation().await;
                return Err(native_pending_error(
                    self.native_operation.as_ref().unwrap_or(&op),
                    true,
                ));
            }
        };
        self.complete_native_operation(&op, observations.as_ref(), None, false)
            .await
    }

    pub(super) async fn transition_native_operation(
        &mut self,
        op: &AgentChatNativeOperation,
        state: &str,
        evidence: Option<&Value>,
    ) -> HostResult<AgentChatNativeOperation> {
        let outcome = self
            .deps
            .store
            .transition_agent_chat_native_operation(
                &op.chat_id,
                &op.operation_id,
                op.revision,
                state,
                evidence,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let op = match outcome {
            AgentChatNativeOperationOutcome::Applied(op) => *op,
            AgentChatNativeOperationOutcome::Existing(op) => {
                return Err(native_pending_error(&op, false));
            }
            outcome => native_outcome(outcome)?,
        };
        self.native_operation = Some(op.clone());
        Ok(op)
    }

    async fn call_native_conversation_rewind(
        &mut self,
        op: &AgentChatNativeOperation,
    ) -> Result<(Value, Option<Value>), ()> {
        let boundary =
            NativeRollbackBoundary::BeforeTurn(op.boundary["value"].as_str().ok_or(())?.into());
        let input = NativeRollbackInput {
            thread_id: op.chat_id.clone(),
            boundary: boundary.clone(),
        };
        let provider = self.provider.as_mut().ok_or(())?;
        let result = tokio::time::timeout(NATIVE_HISTORY_TIMEOUT, provider.rollback_session(input))
            .await
            .map_err(|_| ())?
            .map_err(|_| ())?;
        if result.thread_id != op.chat_id
            || result.native_thread_id != op.native_thread_id
            || result.boundary != boundary
        {
            return Err(());
        }
        Ok((
            json!({"threadId":op.native_thread_id,"nativeThreadId":result.native_thread_id,"boundary":result.boundary}),
            None,
        ))
    }

    async fn call_native_file_rewind(
        &mut self,
        op: &AgentChatNativeOperation,
    ) -> Result<(Value, Option<Value>), ()> {
        let uuid = op.boundary["id"].as_str().ok_or(())?.to_owned();
        let provider = self.provider.as_mut().ok_or(())?;
        let result = tokio::time::timeout(
            NATIVE_HISTORY_TIMEOUT,
            provider.rewind_files(NativeRewindFilesInput {
                thread_id: op.chat_id.clone(),
                native_user_message_id: uuid.clone(),
            }),
        )
        .await
        .map_err(|_| ())?
        .map_err(|_| ())?;
        if result.thread_id != op.chat_id
            || result.native_thread_id != op.native_thread_id
            || result.native_user_message_id != uuid
            || result.error.is_some()
            || result.can_rewind != Some(true)
        {
            return Err(());
        }
        let ack = json!({"threadId":op.native_thread_id,"nativeThreadId":result.native_thread_id,"nativeUserMessageId":uuid});
        let observations = result
            .files_changed
            .as_ref()
            .filter(|files| !files.is_empty())
            .map(|files| {
                json!({
                    "filesystemChangesReverted":true,"observedFileCount":files.len(),
                    "observationId":op.operation_id,
                })
            })
            .unwrap_or_else(|| json!({}));
        Ok((ack, Some(observations)))
    }
}

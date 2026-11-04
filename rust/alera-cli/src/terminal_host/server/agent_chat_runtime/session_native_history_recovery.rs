//! Safe status and restart recovery for durable provider history mutations.

use alera_core::runtime::{
    AgentChatNativeOperation, AgentChatNativeOperationOutcome, AGENT_CHAT_NATIVE_REWIND,
    AGENT_CHAT_NATIVE_REWIND_FILES,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::session::ChatSession;

fn native_operation_requires_restart_reconciliation(
    operation: &AgentChatNativeOperation,
    process_epoch: &str,
) -> bool {
    // An older host must not mutate an operation from a newer protocol.
    matches!(
        operation.kind.as_str(),
        AGENT_CHAT_NATIVE_REWIND | AGENT_CHAT_NATIVE_REWIND_FILES
    ) && operation.state == "executing"
        && operation.process_epoch != process_epoch
}

pub(super) fn native_operation_freezes(operation: &AgentChatNativeOperation) -> bool {
    !matches!(
        operation.state.as_str(),
        "completed" | "cancelled" | "reconciled"
    )
}

#[cfg(test)]
pub(super) fn native_operation_transition_allowed(from: &str, to: &str) -> bool {
    matches!(
        (from, to),
        ("prepared", "executing" | "cancelled")
            | ("executing", "acknowledged" | "uncertain")
            | ("acknowledged", "completed")
            | ("uncertain", "reconciled")
    )
}

pub(super) fn native_operation_recovery(operation: &AgentChatNativeOperation) -> Value {
    let state = operation.state.as_str();
    let known_kind = matches!(
        operation.kind.as_str(),
        AGENT_CHAT_NATIVE_REWIND | AGENT_CHAT_NATIVE_REWIND_FILES
    );
    let message = match state {
        "prepared" => {
            "The history operation has not called the provider. Cancel it before continuing."
        }
        "executing" => "The history operation is being sent to the provider.",
        "acknowledged" => {
            "The provider acknowledged the operation. Finish reconciling without calling it again."
        }
        "uncertain" => {
            "The provider outcome is unknown. Choose an explicit fallback before continuing."
        }
        "completed" => "The history operation completed.",
        "cancelled" => "The unstarted history operation was cancelled.",
        "reconciled" => "The history operation was reconciled with an explicit fallback.",
        _ => "The stored history operation needs attention before this chat can continue.",
    };
    json!({
        "needsReconciliation": native_operation_freezes(operation),
        "canCancelUnstarted": known_kind && state == "prepared",
        "canFinishAcknowledged": known_kind && state == "acknowledged" && operation.ack.is_some(),
        "canRestartFromTranscript": state == "uncertain" && operation.kind == AGENT_CHAT_NATIVE_REWIND,
        "canContinueFromCurrentFiles": state == "uncertain" && operation.kind == AGENT_CHAT_NATIVE_REWIND_FILES,
        "message": message,
    })
}

pub(super) fn native_operation_public_summary(operation: &AgentChatNativeOperation) -> Value {
    let state = match operation.state.as_str() {
        known @ ("prepared" | "executing" | "acknowledged" | "uncertain" | "completed"
        | "cancelled" | "reconciled") => known,
        _ => "unknown",
    };
    let kind = match operation.kind.as_str() {
        AGENT_CHAT_NATIVE_REWIND => AGENT_CHAT_NATIVE_REWIND,
        AGENT_CHAT_NATIVE_REWIND_FILES => AGENT_CHAT_NATIVE_REWIND_FILES,
        _ => "unknown",
    };
    json!({
        "operationId": operation.operation_id,
        "state": state,
        "kind": kind,
        "recovery": native_operation_recovery(operation),
    })
}

impl ChatSession {
    pub(super) async fn load_native_history_recovery(&mut self) -> Result<(), String> {
        for _ in 0..3 {
            let operation = self
                .deps
                .store
                .pending_agent_chat_native_operation(&self.header.chat_id)
                .await
                .map_err(|error| error.to_string())?;
            let Some(operation) = operation else {
                self.native_operation = None;
                return Ok(());
            };
            if !native_operation_requires_restart_reconciliation(&operation, &self.process_epoch) {
                self.native_operation = Some(operation);
                return Ok(());
            }
            match self
                .deps
                .store
                .transition_agent_chat_native_operation(
                    &self.header.chat_id,
                    &operation.operation_id,
                    operation.revision,
                    "uncertain",
                    Some(&json!({"reason":"runtimeRestarted"})),
                )
                .await
                .map_err(|error| error.to_string())?
            {
                AgentChatNativeOperationOutcome::Applied(operation)
                | AgentChatNativeOperationOutcome::Existing(operation) => {
                    if native_operation_requires_restart_reconciliation(
                        &operation,
                        &self.process_epoch,
                    ) {
                        continue;
                    }
                    self.native_operation =
                        native_operation_freezes(&operation).then_some(*operation);
                    return Ok(());
                }
                AgentChatNativeOperationOutcome::RevisionConflict { .. }
                | AgentChatNativeOperationOutcome::Busy { .. } => continue,
                _ => {
                    return Err(
                        "The native history operation could not be reconciled after restart."
                            .into(),
                    );
                }
            }
        }
        Err("The native history operation kept changing during restart recovery.".into())
    }

    pub(super) async fn native_history_operation_status(
        &mut self,
        operation_id: Option<&str>,
    ) -> HostResult<Value> {
        let operation = if let Some(operation_id) = operation_id {
            self.deps
                .store
                .agent_chat_native_operation(&self.header.chat_id, operation_id)
                .await
        } else {
            self.deps
                .store
                .pending_agent_chat_native_operation(&self.header.chat_id)
                .await
        }
        .map_err(|_| HostError::state("The native history operation could not be read."))?;
        Ok(json!({"operation": operation.as_ref().map(native_operation_public_summary)}))
    }
}

#[cfg(test)]
#[path = "session_native_history_recovery_tests.rs"]
mod tests;

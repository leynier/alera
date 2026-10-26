//! Context transfers of delegated work (`agentChatTransfersV1`): the brief a
//! child chat received and the settled results its parent was woken with,
//! each recorded in the chat that received it, plus `chatOrchestration.transfers`
//! (T3 Code's `t3_thread_transfers`). Recording is best effort: the task
//! ledger stays the source of truth, so a chat that cannot take the record
//! (an older satellite, a chat archived meanwhile) only loses the row.

use alera_core::runtime::{ChatOrchestrationTaskStatus, RuntimeStore};
use serde_json::{json, Value};

use super::authorization::OrchestrationCaller;
use super::runtime::ChatOrchestrationRuntime;
use super::service::ChatOrchestrationService;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::session_transfers::{
    ContextTransfer, TransferKind, TransferStatus, TRANSFERS_KEY,
};
use crate::terminal_host::server::agent_chat_runtime::{CallerCtx, ChatOp};

async fn record(runtime: &dyn ChatOrchestrationRuntime, transfer: ContextTransfer) {
    let chat_id = transfer.target_chat_id.clone();
    if let Err(error) = runtime
        .command(
            &chat_id,
            ChatOp::RecordTransfer(transfer),
            CallerCtx::runtime(),
            None,
        )
        .await
    {
        tracing::warn!(%chat_id, error = %error.wire_message(), "context transfer not recorded");
    }
}

/// The brief of `task_id` reached `child_chat_id` through `turn_id`.
pub(super) async fn record_delegated_brief(
    runtime: &dyn ChatOrchestrationRuntime,
    parent_chat_id: &str,
    child_chat_id: &str,
    task_id: &str,
    turn_id: Option<&str>,
) {
    let mut transfer = ContextTransfer::new(
        TransferKind::SubagentSpawn,
        parent_chat_id,
        child_chat_id,
        TransferStatus::Consumed,
    );
    transfer.task_id = Some(task_id.into());
    transfer.target_turn_id = turn_id.map(str::to_owned);
    record(runtime, transfer).await;
}

/// The settled tasks among `task_ids` were delivered to `parent_chat_id` by
/// a wake that started `turn_id` (none while the wake waits in the queue).
pub(super) async fn record_delegated_results(
    store: &RuntimeStore,
    runtime: &dyn ChatOrchestrationRuntime,
    parent_chat_id: &str,
    task_ids: &[String],
    turn_id: Option<&str>,
) {
    for task_id in task_ids {
        let Ok(Some(task)) = store.chat_orchestration_task(task_id).await else {
            continue;
        };
        let failed = match task.status {
            ChatOrchestrationTaskStatus::Completed => false,
            ChatOrchestrationTaskStatus::Failed
            | ChatOrchestrationTaskStatus::Interrupted
            | ChatOrchestrationTaskStatus::Cancelled => true,
            _ => continue,
        };
        let Some(child_chat_id) = task.child_chat_id.as_deref() else {
            continue;
        };
        let mut transfer = ContextTransfer::new(
            TransferKind::SubagentResult,
            child_chat_id,
            parent_chat_id,
            TransferStatus::Consumed,
        );
        transfer.task_id = Some(task.task_id.clone());
        transfer.source_title = task.title.clone();
        transfer.source_turn_id = task.child_turn_id.clone();
        transfer.target_turn_id = turn_id.map(str::to_owned);
        if failed {
            transfer.error = Some(
                task.error
                    .clone()
                    .unwrap_or_else(|| "The delegated task did not complete.".into()),
            );
        }
        record(runtime, transfer).await;
    }
}

/// The fields `chatOrchestration.transfers` lists for one record.
fn transfer_summary(record: &Value) -> Value {
    let mut summary = json!({});
    for key in [
        "transferId",
        "kind",
        "sourceChatId",
        "targetChatId",
        "status",
        "sourceTitle",
        "taskId",
        "error",
        "createdAt",
        "consumedAt",
    ] {
        if let Some(value) = record.get(key).filter(|value| !value.is_null()) {
            summary[key] = value.clone();
        }
    }
    summary
}

impl ChatOrchestrationService {
    /// `chatOrchestration.transfers`: the context moved into a chat, newest
    /// first. A bound agent reads its own chat when it names none.
    pub(super) async fn transfers(
        &self,
        chat_id: Option<String>,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let chat_id = chat_id
            .or_else(|| caller.bound.as_ref().map(|bound| bound.chat_id.clone()))
            .ok_or_else(|| HostError::format("chatId is required"))?;
        let snapshot = self.runtime.snapshot(&chat_id).await?;
        let transfers: Vec<Value> = snapshot
            .get(TRANSFERS_KEY)
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .rev()
            .map(transfer_summary)
            .collect();
        Ok(json!({"chatId": chat_id, "transfers": transfers}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_summary_keeps_only_the_listed_fields() {
        let summary = transfer_summary(&json!({
            "transferId": "t", "kind": "mergeBack", "sourceChatId": "a",
            "targetChatId": "b", "status": "pending", "itemId": "item",
            "from": {"provider": "codex"}, "error": null,
        }));
        assert_eq!(
            summary,
            json!({"transferId": "t", "kind": "mergeBack", "sourceChatId": "a", "targetChatId": "b", "status": "pending"})
        );
    }
}

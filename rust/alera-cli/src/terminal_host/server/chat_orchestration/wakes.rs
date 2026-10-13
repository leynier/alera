use std::sync::Arc;

use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};

use super::runtime::ChatOrchestrationRuntime;
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::server::agent_chat_runtime::commands::{CallerCtx, SendInput};

use super::service::OrchestrationEventSink;

/// Seals and delivers one durable cohort only while the parent has no active
/// turn or pending request. A queued result is still a successful delivery:
/// the chat runtime owns it durably and will not interrupt the parent's turn.
pub(crate) async fn deliver_next_wake(
    store: &RuntimeStore,
    runtime: &dyn ChatOrchestrationRuntime,
    parent_chat_id: &str,
    events: &Arc<dyn OrchestrationEventSink>,
) -> HostResult<bool> {
    let snapshot = runtime.snapshot(parent_chat_id).await?;
    let session = snapshot.get("session").cloned().unwrap_or(Value::Null);
    if session
        .get("activeTurnId")
        .is_some_and(|value| !value.is_null())
        || snapshot
            .get("pendingRequests")
            .and_then(Value::as_array)
            .is_some_and(|requests| !requests.is_empty())
    {
        return Ok(false);
    }
    let Some(wake) = store
        .seal_chat_orchestration_wake(parent_chat_id)
        .await
        .map_err(|error| crate::terminal_host::host_error::HostError::state(error.to_string()))?
    else {
        return Ok(false);
    };
    let task_ids: Vec<String> = wake
        .entries
        .iter()
        .map(|entry| entry.task_id.clone())
        .collect();
    let text = format!(
        "Orchestration updates are available for task IDs: {}. Read each task for its result.",
        task_ids.join(", ")
    );
    let send = runtime
        .send(
            parent_chat_id,
            SendInput {
                client_message_id: wake.client_message_id.clone(),
                text,
                attachments: Vec::new(),
                delivery: "queue".into(),
                model: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: Some(json!({
                    "kind": "orchestrationWake",
                    "taskIds": task_ids,
                })),
            },
            CallerCtx {
                scope: format!("chat:{parent_chat_id}"),
                actor: format!("agent:{parent_chat_id}"),
                mobile: false,
            },
        )
        .await;
    match send {
        Ok(_) => {
            let delivered = store
                .ack_chat_orchestration_wake(parent_chat_id, wake.generation)
                .await
                .map_err(|error| {
                    crate::terminal_host::host_error::HostError::state(error.to_string())
                })?;
            for entry in delivered.entries {
                events
                    .changed(json!({
                        "taskId": entry.task_id,
                        "parentChatId": parent_chat_id,
                    }))
                    .await;
            }
            Ok(true)
        }
        Err(_) => Ok(false),
    }
}

use std::time::Duration;

use alera_core::runtime::{
    ChatOrchestrationTask, ChatOrchestrationTaskFilter, ChatOrchestrationTaskStatus,
    ChatOrchestrationTaskTransition, RuntimeStore, CHAT_ORCHESTRATION_RESULT_MAX_BYTES,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::models::{ListInput, WaitInput, WaitUntil};

/// The public task result is intentionally smaller than the durable store
/// limit. The complete transcript remains in the child chat and `read` is the
/// explicit path for more context.
pub(crate) const PUBLIC_RESULT_MAX_BYTES: usize = 8 * 1024;

pub(crate) fn truncate_result(text: &str) -> (String, bool) {
    let max = PUBLIC_RESULT_MAX_BYTES.min(CHAT_ORCHESTRATION_RESULT_MAX_BYTES);
    if text.len() <= max {
        return (text.to_owned(), false);
    }
    let mut end = max;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    (text[..end].to_owned(), true)
}

pub(crate) fn task_value(task: &ChatOrchestrationTask) -> Value {
    let (brief, brief_truncated) = truncate_result(&task.brief);
    let (result_text, result_truncated) = task
        .result_text
        .as_deref()
        .map(truncate_result)
        .unwrap_or_else(|| (String::new(), task.result_truncated));
    let mut value = json!({
        "taskId": task.task_id,
        "kind": task.kind,
        "status": task.status,
        "parentTaskId": task.parent_task_id,
        "rootTaskId": task.root_task_id,
        "depth": task.depth,
        "parentChatId": task.parent_chat_id,
        "rootChatId": task.root_chat_id,
        "childChatId": task.child_chat_id,
        "workspaceId": task.workspace_id,
        "projectId": task.project_id,
        "hostId": task.host_id,
        "target": task.target,
        "title": task.title,
        "role": task.role,
        "brief": brief,
        "briefTruncated": brief_truncated,
        "notify": task.notify,
        "attention": task.needs_attention(),
        "resultDelivery": task.result_delivery,
        "actor": task.caller_scope,
        "createdAt": task.created_at,
        "updatedAt": task.updated_at,
        "completedAt": task.settled_at,
    });
    if task.needs_attention() {
        value["attentionKind"] = json!(if task.status == ChatOrchestrationTaskStatus::NeedsInput {
            "needs_input"
        } else {
            "failed"
        });
    }
    if let Some(options) = &task.launch_options {
        for key in ["provider", "providerInstanceId", "model", "runtimeMode"] {
            if let Some(option) = options.get(key) {
                value[key] = option.clone();
            }
        }
    }
    if !result_text.is_empty() || task.result_text.is_some() {
        value["result"] = json!({
            "text": result_text,
            "truncated": result_truncated || task.result_truncated,
            "turnId": task.child_turn_id,
        });
    }
    if task.error.is_some() || task.error_code.is_some() {
        value["error"] = json!({"code": task.error_code, "message": task.error});
    }
    value
}

pub(crate) fn task_page_value(page: &alera_core::runtime::ChatOrchestrationTaskPage) -> Value {
    json!({
        "tasks": page.tasks.iter().map(task_value).collect::<Vec<_>>(),
        "nextCursor": page.next_before_sequence,
    })
}

pub(crate) async fn list_tasks(store: &RuntimeStore, input: &ListInput) -> HostResult<Value> {
    let page = store
        .list_chat_orchestration_tasks(&ChatOrchestrationTaskFilter {
            parent_chat_id: input.parent_chat_id.clone(),
            root_chat_id: None,
            child_chat_id: input.child_chat_id.clone(),
            project_id: input.project_id.clone(),
            workspace_id: input.workspace_id.clone(),
            host_id: input.host_id.clone(),
            parent_task_id: None,
            root_task_id: input.root_task_id.clone(),
            caller_scope: None,
            statuses: input.statuses.clone(),
            attention: input.attention,
            before_sequence: input.cursor,
            limit: input.limit,
        })
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    Ok(task_page_value(&page))
}

pub(crate) async fn task_value_for(
    store: &RuntimeStore,
    task_id: &str,
    acknowledge: bool,
) -> HostResult<Value> {
    let task = store
        .chat_orchestration_task(task_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .ok_or_else(|| HostError::conflict("task_not_found", "Task not found.", json!({})))?;
    let task = if acknowledge {
        store
            .acknowledge_chat_orchestration_result(task_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
    } else {
        task
    };
    Ok(json!({"task": task_value(&task)}))
}

pub(crate) async fn wait_for_tasks(store: &RuntimeStore, input: &WaitInput) -> HostResult<Value> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(input.wait_seconds);
    loop {
        let mut tasks = Vec::with_capacity(input.task_ids.len());
        for task_id in &input.task_ids {
            let task = store
                .chat_orchestration_task(task_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| {
                    HostError::conflict("task_not_found", "Task not found.", json!({}))
                })?;
            tasks.push(task);
        }
        let settled = tasks
            .iter()
            .filter(|task| task.status.is_terminal())
            .count();
        let done = match input.until {
            WaitUntil::All => settled == tasks.len(),
            WaitUntil::Any => settled > 0,
        };
        if done || tokio::time::Instant::now() >= deadline {
            let refreshed =
                futures_util::future::try_join_all(input.task_ids.iter().map(|task_id| async {
                    store
                        .chat_orchestration_task(task_id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?
                        .ok_or_else(|| {
                            HostError::conflict("task_not_found", "Task not found.", json!({}))
                        })
                }))
                .await?;
            return Ok(json!({
                "tasks": refreshed.iter().map(task_value).collect::<Vec<_>>(),
                "timedOut": !done,
            }));
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

pub(crate) fn transition_status(
    from: ChatOrchestrationTaskStatus,
    to: ChatOrchestrationTaskStatus,
    child_chat_id: Option<String>,
    child_turn_id: Option<String>,
    result_text: Option<String>,
    error_code: Option<String>,
    error: Option<String>,
) -> ChatOrchestrationTaskTransition {
    let mut transition = ChatOrchestrationTaskTransition::new([from], to);
    transition.child_chat_id = child_chat_id;
    transition.child_turn_id = child_turn_id;
    transition.result_text = result_text;
    transition.error_code = error_code;
    transition.error = error;
    transition
}

pub(crate) fn parse_turn_status(snapshot: &Value, turn_id: &str) -> Option<String> {
    snapshot
        .get("turns")
        .and_then(Value::as_array)
        .and_then(|turns| turns.iter().rev().find(|turn| turn["turnId"] == turn_id))
        .and_then(|turn| turn.get("status"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

pub(crate) fn matching_turn(snapshot: &Value, client_message_id: &str) -> Option<(String, String)> {
    let item = snapshot
        .get("items")
        .and_then(Value::as_array)?
        .iter()
        .rev()
        .find(|item| item["clientMessageId"] == client_message_id)?;
    let item_id = item.get("itemId")?.as_str()?.to_owned();
    let turn_id = item.get("turnId")?.as_str()?.to_owned();
    Some((item_id, turn_id))
}

pub(crate) fn final_assistant_text(snapshot: &Value, turn_id: &str) -> Option<String> {
    snapshot
        .get("items")
        .and_then(Value::as_array)
        .and_then(|items| {
            items.iter().rev().find(|item| {
                item["turnId"] == turn_id
                    && item["type"] == "assistant_message"
                    && item.get("text").and_then(Value::as_str).is_some()
            })
        })
        .and_then(|item| item.get("text").and_then(Value::as_str))
        .map(ToOwned::to_owned)
}

use alera_provider_protocol::{NativeTask, ProviderError};
use serde_json::Value;

pub(crate) fn native_task(params: &Value) -> Result<Option<NativeTask>, ProviderError> {
    if let Some(thread) = params.get("thread") {
        let parent = thread
            .get("parentThreadId")
            .and_then(Value::as_str)
            .or_else(|| {
                thread
                    .pointer("/source/subAgent/thread_spawn/parent_thread_id")
                    .and_then(Value::as_str)
            });
        if let (Some(parent), Some(child)) = (parent, thread.get("id").and_then(Value::as_str)) {
            let task = NativeTask {
                parent_native_thread_id: Some(parent.into()),
                child_native_thread_ids: vec![child.into()],
                ..Default::default()
            };
            task.validate()?;
            return Ok(Some(task));
        }
    }
    let Some(item) = params.get("item") else {
        return Ok(None);
    };
    let string = |key: &str| {
        item.get(key)
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
            .map(str::to_owned)
    };
    let task = match item.get("type").and_then(Value::as_str) {
        Some("collabAgentToolCall") => NativeTask {
            native_task_id: None,
            native_tool_call_id: string("id"),
            parent_native_thread_id: string("senderThreadId"),
            child_native_thread_ids: item
                .get("receiverThreadIds")
                .and_then(Value::as_array)
                .map(|ids| {
                    ids.iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
            status: string("status"),
        },
        Some("subAgentActivity") => NativeTask {
            native_task_id: None,
            native_tool_call_id: string("id"),
            parent_native_thread_id: params
                .get("threadId")
                .and_then(Value::as_str)
                .map(str::to_owned),
            child_native_thread_ids: string("agentThreadId").into_iter().collect(),
            status: string("kind"),
        },
        _ => return Ok(None),
    };
    task.validate()?;
    Ok(Some(task))
}

use crate::{
    api_models::{PushCategory, RuntimeEventRequest},
    error::ApiError,
};

/// Chat push metadata is an identifier-only contract. Unlike terminal events,
/// these events never accept arbitrary provider or orchestration fields.
pub(crate) fn validate_chat_event(request: &RuntimeEventRequest) -> Result<(), ApiError> {
    let kind = request.data["kind"].as_str();
    let chat = kind == Some("agentChat") || request.event_type == "agent_chat_request";
    let task = kind == Some("chatTask")
        || matches!(
            request.event_type.as_str(),
            "chat_task_attention" | "chat_task_needs_input"
        );
    if !chat && !task {
        return Ok(());
    }
    if request.category != PushCategory::Attention
        || kind != Some(if chat { "agentChat" } else { "chatTask" })
    {
        return Err(invalid_chat_data());
    }
    let object = request.data.as_object().ok_or_else(invalid_chat_data)?;
    for (key, value) in object {
        match key.as_str() {
            "kind" => {}
            "chatId" | "requestId" | "workspaceId" | "tabId" | "taskId" => {
                if !value.is_null()
                    && !value.as_str().is_some_and(|id| {
                        !id.is_empty()
                            && id.len() <= 256
                            && id.bytes().all(|byte| {
                                byte.is_ascii_alphanumeric()
                                    || matches!(byte, b'-' | b'_' | b':' | b'.')
                            })
                    })
                {
                    return Err(invalid_chat_data());
                }
            }
            "batched" if value.is_boolean() => {}
            "count" if value.as_u64().is_some_and(|count| count > 0) => {}
            _ => return Err(invalid_chat_data()),
        }
    }
    let required: &[&str] = if chat {
        &["chatId", "workspaceId", "tabId"]
    } else {
        &["taskId"]
    };
    if required
        .iter()
        .any(|key| request.data[key].as_str().is_none())
    {
        return Err(invalid_chat_data());
    }
    Ok(())
}

fn invalid_chat_data() -> ApiError {
    ApiError::bad_request(
        "invalid_chat_event_data",
        "Chat notifications must contain only routing identifiers.",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use serde_json::{json, Value};

    fn event(data: Value) -> RuntimeEventRequest {
        RuntimeEventRequest {
            runtime_id: "runtime".into(),
            event_id: "event".into(),
            category: PushCategory::Attention,
            event_type: "agent_chat_request".into(),
            title: "Agent Chat Needs Approval".into(),
            body: "Workspace App".into(),
            data,
            occurred_at: Utc::now(),
        }
    }

    #[test]
    fn accepts_safe_chat_identifiers_and_grouping() {
        assert!(validate_chat_event(&event(json!({"kind":"agentChat","chatId":"chat","workspaceId":"workspace","tabId":"tab","requestId":"request","batched":true,"count":2}))).is_ok());
    }

    #[test]
    fn rejects_request_content_secrets_and_missing_chat_target() {
        for field in [
            "questions",
            "command",
            "resultText",
            "brief",
            "token",
            "title",
        ] {
            let mut data =
                json!({"kind":"agentChat","chatId":"chat","workspaceId":"workspace","tabId":"tab"});
            data[field] = json!("private");
            assert!(
                validate_chat_event(&event(data)).is_err(),
                "accepted {field}"
            );
        }
        assert!(validate_chat_event(&event(json!({"kind":"agentChat","chatId":"chat"}))).is_err());
        assert!(validate_chat_event(&event(json!({"kind":"agentChat","chatId":"a raw provider request","workspaceId":"workspace","tabId":"tab"}))).is_err());
    }

    #[test]
    fn task_attention_routes_without_a_live_child_and_keeps_attention_filter() {
        let mut event = event(
            json!({"kind":"chatTask","taskId":"task","chatId":null,"workspaceId":null,"tabId":null}),
        );
        event.event_type = "chat_task_attention".into();
        assert!(validate_chat_event(&event).is_ok());
        event.category = PushCategory::Done;
        assert!(validate_chat_event(&event).is_err());
    }
}

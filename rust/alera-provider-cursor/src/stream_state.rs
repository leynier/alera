use alera_provider_protocol::{EventKind, ProviderEvent};
use cursor_agent_sdk::RunStreamMessage;
use serde_json::Value;

pub(crate) fn run_id(message: &RunStreamMessage) -> Option<String> {
    let candidate = message
        .sdk_message
        .as_ref()
        .and_then(|sdk| {
            sdk.get("runId")
                .or_else(|| sdk.get("run_id"))
                .or_else(|| sdk.get("message").and_then(|value| value.get("runId")))
                .or_else(|| sdk.get("message").and_then(|value| value.get("run_id")))
        })
        .or_else(|| {
            message
                .result
                .as_ref()
                .and_then(|result| result.get("runId").or_else(|| result.get("run_id")))
        })
        .or_else(|| {
            message
                .done
                .as_ref()
                .and_then(|done| done.get("runId").or_else(|| done.get("run_id")))
        });
    candidate.and_then(Value::as_str).map(str::to_owned)
}

pub(crate) fn item_id(message: &RunStreamMessage) -> Option<String> {
    let candidate = message
        .sdk_message
        .as_ref()
        .and_then(|sdk| {
            sdk.get("itemId")
                .or_else(|| sdk.get("item_id"))
                .or_else(|| sdk.get("messageId"))
                .or_else(|| sdk.get("message_id"))
                .or_else(|| sdk.get("callId"))
                .or_else(|| sdk.get("call_id"))
                .or_else(|| sdk.get("toolCallId"))
                .or_else(|| sdk.get("tool_call_id"))
                .or_else(|| sdk.get("uuid"))
                .or_else(|| sdk.get("message").and_then(|value| value.get("itemId")))
                .or_else(|| sdk.get("message").and_then(|value| value.get("item_id")))
                .or_else(|| sdk.get("message").and_then(|value| value.get("messageId")))
                .or_else(|| sdk.get("message").and_then(|value| value.get("message_id")))
                .or_else(|| sdk.get("message").and_then(|value| value.get("callId")))
                .or_else(|| sdk.get("message").and_then(|value| value.get("call_id")))
                .or_else(|| sdk.get("message").and_then(|value| value.get("toolCallId")))
                .or_else(|| {
                    sdk.get("message")
                        .and_then(|value| value.get("tool_call_id"))
                })
                .or_else(|| {
                    sdk.get("message")
                        .and_then(|value| value.get("toolCall"))
                        .and_then(|value| value.get("callId"))
                })
                .or_else(|| {
                    sdk.get("message")
                        .and_then(|value| value.get("toolCall"))
                        .and_then(|value| value.get("tool_call_id"))
                })
                .or_else(|| sdk.get("message").and_then(|value| value.get("uuid")))
        })
        .or_else(|| {
            message.interaction_update.as_ref().and_then(|update| {
                update
                    .get("itemId")
                    .or_else(|| update.get("item_id"))
                    .or_else(|| update.get("messageId"))
                    .or_else(|| update.get("message_id"))
                    .or_else(|| update.get("callId"))
                    .or_else(|| update.get("call_id"))
                    .or_else(|| update.get("toolCallId"))
                    .or_else(|| update.get("tool_call_id"))
                    .or_else(|| update.get("update").and_then(|value| value.get("itemId")))
                    .or_else(|| update.get("update").and_then(|value| value.get("item_id")))
                    .or_else(|| {
                        update
                            .get("update")
                            .and_then(|value| value.get("messageId"))
                    })
                    .or_else(|| {
                        update
                            .get("update")
                            .and_then(|value| value.get("message_id"))
                    })
                    .or_else(|| update.get("update").and_then(|value| value.get("callId")))
                    .or_else(|| update.get("update").and_then(|value| value.get("call_id")))
                    .or_else(|| {
                        update
                            .get("update")
                            .and_then(|value| value.get("toolCallId"))
                    })
                    .or_else(|| {
                        update
                            .get("update")
                            .and_then(|value| value.get("tool_call_id"))
                    })
                    .or_else(|| {
                        update
                            .get("update")
                            .and_then(|value| value.get("toolCall"))
                            .and_then(|value| value.get("callId"))
                    })
                    .or_else(|| {
                        update
                            .get("update")
                            .and_then(|value| value.get("toolCall"))
                            .and_then(|value| value.get("tool_call_id"))
                    })
            })
        });
    candidate.and_then(Value::as_str).map(str::to_owned)
}

pub(crate) fn is_assistant_delta(event: &ProviderEvent) -> bool {
    event.kind == EventKind::ContentDelta
        && event
            .payload
            .get("streamKind")
            .and_then(Value::as_str)
            .is_some_and(|kind| kind.eq_ignore_ascii_case("assistant_text"))
}

pub(crate) fn status_error_message(message: &RunStreamMessage) -> Option<String> {
    let sdk = message.sdk_message.as_ref()?;
    if sdk.get("type").and_then(Value::as_str) != Some("status") {
        return None;
    }
    let payload = sdk.get("message").unwrap_or(sdk);
    let status = payload
        .get("status")
        .and_then(Value::as_str)
        .map(|status| {
            status
                .strip_prefix("RUN_LIFECYCLE_STATUS_")
                .unwrap_or(status)
                .to_ascii_lowercase()
        })?;
    if !matches!(status.as_str(), "error" | "failed") {
        return None;
    }
    payload
        .get("message")
        .and_then(Value::as_str)
        .filter(|message| !message.is_empty())
        .map(str::to_owned)
}

mod support;

use alera_provider_protocol::{EventKind, Provider, TurnInput};
use serde_json::json;
use support::*;

#[tokio::test]
async fn failed_result_maps_to_failed_turn_and_unknown_is_retained() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({"type":"future_message", "data":{"x":1}}),
        result_message(true, None),
    ])
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "run"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let unknown = provider.next_event().await.unwrap().unwrap();
    assert_eq!(unknown.kind, EventKind::RuntimeWarning);
    assert_eq!(unknown.raw.unwrap().payload["type"], "future_message");
    let failed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(failed.kind, EventKind::TurnCompleted);
    assert_eq!(failed.payload["state"], "failed");
    assert_eq!(failed.payload["errorMessage"], "failed");
}

#[tokio::test]
async fn streamed_text_is_not_repeated_by_final_assistant_message() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({
            "type": "stream_event",
            "uuid": "stream-1",
            "session_id": "native-session",
            "event": {
                "type": "content_block_delta",
                "index": 0,
                "delta": {"type": "text_delta", "text": "hello"}
            }
        }),
        json!({
            "type": "assistant",
            "session_id": "native-session",
            "message": {"id": "message-1", "content": [{"type": "text", "text": "hello"}]}
        }),
        json!({
            "type": "assistant",
            "session_id": "native-session",
            "message": {"id": "message-2", "content": [{"type": "text", "text": "later"}]}
        }),
        result_message(false, None),
    ])
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider
        .send_turn(TurnInput::text("app-thread", "stream"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let stream = provider.next_event().await.unwrap().unwrap();
    assert_eq!(stream.kind, EventKind::ContentDelta);
    assert_eq!(stream.payload["delta"], "hello");
    assert_eq!(
        stream.raw.as_ref().unwrap().message_type.as_deref(),
        Some("stream_event")
    );
    let final_message = provider.next_event().await.unwrap().unwrap();
    assert_eq!(final_message.kind, EventKind::ItemUpdated);
    assert!(final_message.payload.get("delta").is_none());
    let later_message = provider.next_event().await.unwrap().unwrap();
    assert_eq!(later_message.kind, EventKind::ContentDelta);
    assert_eq!(later_message.payload["delta"], "later");
}

#[tokio::test]
async fn streamed_tool_json_does_not_suppress_final_assistant_text() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({
            "type": "stream_event",
            "uuid": "stream-json",
            "session_id": "native-session",
            "event": {
                "type": "content_block_delta",
                "index": 0,
                "delta": {"type": "input_json_delta", "partial_json": "{}"}
            }
        }),
        json!({
            "type": "assistant",
            "session_id": "native-session",
            "message": {"id": "message-json", "content": [{"type": "text", "text": "done"}]}
        }),
        result_message(false, None),
    ])
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "json"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let json_delta = provider.next_event().await.unwrap().unwrap();
    assert_eq!(json_delta.kind, EventKind::ContentDelta);
    assert_eq!(json_delta.payload["streamKind"], "unknown");
    let assistant = provider.next_event().await.unwrap().unwrap();
    assert_eq!(assistant.kind, EventKind::ContentDelta);
    assert_eq!(assistant.payload["delta"], "done");
}

#[tokio::test]
async fn result_usage_includes_cached_input_tokens_and_preserves_rate_limits() {
    let rate_limit = json!({
        "type": "rate_limit_event",
        "uuid": "rate-1",
        "session_id": "native-session",
        "rate_limit_info": {
            "status": "allowed_warning",
            "resetsAt": 1_893_456_000_i64,
            "rateLimitType": "five_hour",
            "utilization": 0.5
        }
    });
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        rate_limit,
        result_message_with_usage(json!({
            "input_tokens": 2,
            "cache_read_input_tokens": 3,
            "cache_creation_input_tokens": 4,
            "output_tokens": 5
        })),
    ])
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "usage"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let limits = provider.next_event().await.unwrap().unwrap();
    assert_eq!(limits.kind, EventKind::AccountRateLimitsUpdated);
    assert_eq!(limits.payload["limits"]["windows"][0]["usedPercent"], 50.0);
    assert_eq!(
        limits.payload["limits"]["windows"][0]["windowDurationMins"],
        300
    );
    assert_eq!(
        limits.payload["limits"]["windows"][0]["resetsAt"],
        "2030-01-01T00:00:00+00:00"
    );
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["tokenUsage"]["inputTokens"], 9);
    assert_eq!(completed.payload["tokenUsage"]["cachedInputTokens"], 3);
    assert_eq!(completed.payload["tokenUsage"]["cacheCreationTokens"], 4);
}

#[tokio::test]
async fn rate_limit_without_utilization_is_a_warning_without_fabricated_usage() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({
            "type": "rate_limit_event",
            "uuid": "rate-2",
            "session_id": "native-session",
            "rate_limit_info": {
                "status": "rejected",
                "rateLimitType": "five_hour"
            }
        }),
    ])
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "rate"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let warning = provider.next_event().await.unwrap().unwrap();
    assert_eq!(warning.kind, EventKind::RuntimeWarning);
    assert_eq!(
        warning.payload["message"],
        "Claude rate limit event did not contain a usable window"
    );
    assert!(warning.raw.unwrap().payload["rate_limit_info"]["utilization"].is_null());
}

#[tokio::test]
async fn system_lifecycle_states_are_canonical_and_unknown_raw_is_retained() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({
            "type": "system",
            "subtype": "session_state_changed",
            "state": "idle",
            "vendor_state": {"kept": true}
        }),
        json!({
            "type": "system",
            "subtype": "compact_boundary",
            "compact_id": "compact-1"
        }),
        json!({
            "type": "system",
            "subtype": "future_system_event",
            "future_field": "preserve"
        }),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("app-thread", "system"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let state = provider.next_event().await.unwrap().unwrap();
    assert_eq!(state.kind, EventKind::SessionStateChanged);
    assert_eq!(state.payload["state"], "ready");
    assert_eq!(state.raw.unwrap().payload["vendor_state"]["kept"], true);
    let compacted = provider.next_event().await.unwrap().unwrap();
    assert_eq!(compacted.kind, EventKind::ThreadStateChanged);
    assert_eq!(compacted.payload["state"], "compacted");
    let unknown = provider.next_event().await.unwrap().unwrap();
    assert_eq!(unknown.kind, EventKind::RuntimeWarning);
    assert_eq!(unknown.payload["message"], "unknown Claude system message");
    assert_eq!(unknown.raw.unwrap().payload["future_field"], "preserve");
}

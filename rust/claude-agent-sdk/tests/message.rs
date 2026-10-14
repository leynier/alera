use claude_agent_sdk::{ContentBlock, Message};
use serde_json::json;

#[test]
fn parses_wire_user_message_and_keeps_envelope() {
    let wire = json!({
        "type": "user",
        "session_id": "session-1",
        "uuid": "user-1",
        "parent_tool_use_id": null,
        "message": { "role": "user", "content": "hello" },
        "tool_use_result": { "duration_ms": 2 }
    });
    let envelope = Message::from_value(wire.clone());
    assert_eq!(envelope.raw(), &wire);
    let Message::User(message) = envelope else {
        panic!("expected user message");
    };
    assert_eq!(message.content, json!("hello"));
    assert_eq!(message.uuid.as_deref(), Some("user-1"));
    assert_eq!(message.raw, wire);
}

#[test]
fn keeps_invalid_typed_frames_as_original_unknown_values() {
    let wire = json!({ "type": "assistant", "message": { "content": "not-an-array" }, "uuid": "assistant-1" });
    let Message::Unknown(value) = Message::from_value(wire.clone()) else {
        panic!("expected unknown message");
    };
    assert_eq!(value, wire);
}

#[test]
fn preserves_unknown_content_block_fields_and_wire_rate_metadata() {
    let block = ContentBlock::from_value(json!({ "type": "text", "text": 42, "future": true }));
    assert_eq!(
        block.to_value(),
        json!({ "type": "text", "text": 42, "future": true })
    );

    let rate = Message::from_value(json!({
        "type": "rate_limit_event",
        "uuid": "rate-1",
        "session_id": "session-1",
        "rate_limit_info": {
            "status": "allowed_warning",
            "resetsAt": 123,
            "rateLimitType": "five_hour",
            "utilization": 0.9,
            "futureField": "kept"
        }
    }));
    let Message::RateLimit(event) = rate else {
        panic!("expected rate limit event");
    };
    assert_eq!(event.rate_limit_info.resets_at, Some(123));
    assert_eq!(event.rate_limit_info.raw["futureField"], json!("kept"));
    assert_eq!(event.raw["uuid"], json!("rate-1"));
}

#[test]
fn parses_conversation_reset_as_typed_message() {
    let wire = json!({ "type": "conversation_reset", "new_conversation_id": "new", "uuid": "reset", "session_id": "old" });
    let Message::ConversationReset(message) = Message::from_value(wire.clone()) else {
        panic!("expected conversation reset");
    };
    assert_eq!(message.new_conversation_id, "new");
    assert_eq!(message.raw, wire);
}

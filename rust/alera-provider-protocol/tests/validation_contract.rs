use alera_provider_protocol::{
    EventKind, FailureClass, ProviderError, ProviderEvent, ProviderKind, ProviderRefs, RawEvent,
    RuntimeMode, SessionStartInput,
};
use serde_json::json;

fn expect_validation_error(result: Result<(), ProviderError>) {
    assert!(
        matches!(result, Err(ProviderError::Validation(_))),
        "unexpected result: {result:?}"
    );
}

fn valid_content_event(payload: serde_json::Value) -> ProviderEvent {
    let mut event = ProviderEvent::new(
        ProviderKind::Codex,
        "codex-instance",
        "00000000-0000-4000-8000-000000000002",
        EventKind::ContentDelta,
        payload,
        None,
    );
    event.event_id = "00000000-0000-4000-8000-000000000001".into();
    event.created_at = "2026-10-12T12:34:56.000Z".into();
    event.turn_id = Some("00000000-0000-4000-8000-000000000003".into());
    event
}

fn valid_completed_event(payload: serde_json::Value) -> ProviderEvent {
    let mut event = ProviderEvent::new(
        ProviderKind::Claude,
        "claude-instance",
        "00000000-0000-4000-8000-000000000012",
        EventKind::TurnCompleted,
        payload,
        None,
    );
    event.event_id = "00000000-0000-4000-8000-000000000011".into();
    event.created_at = "2026-10-12T12:34:56.000Z".into();
    event.turn_id = Some("00000000-0000-4000-8000-000000000013".into());
    event
}

#[test]
fn session_start_validation_rejects_blank_shared_identity_fields() {
    let mut input = SessionStartInput::new("app-thread-1");
    input.runtime_mode = RuntimeMode::ApprovalRequired;
    input.validate().unwrap();

    input.thread_id = "  ".into();
    expect_validation_error(input.validate());

    input.thread_id = "app-thread-1".into();
    input.resume_thread_id = Some(String::new());
    expect_validation_error(input.validate());

    input.resume_thread_id = None;
    input.model = Some("\t".into());
    expect_validation_error(input.validate());
}

#[test]
fn content_delta_validation_requires_stream_kind_and_delta_fields() {
    let valid = valid_content_event(json!({
        "streamKind": "assistant_text",
        "delta": "hello"
    }));
    valid.validate().unwrap();

    let missing_stream_kind = valid_content_event(json!({ "delta": "hello" }));
    expect_validation_error(missing_stream_kind.validate());

    let missing_delta = valid_content_event(json!({ "streamKind": "assistant_text" }));
    expect_validation_error(missing_delta.validate());
}

#[test]
fn turn_completed_complete_usage_requires_input_and_output_counts() {
    let valid = valid_completed_event(json!({
        "state": "completed",
        "tokenUsage": {
            "usageScope": "main_agent",
            "usageStatus": "complete",
            "inputTokens": 120,
            "outputTokens": 24,
            "hasSubagents": false
        }
    }));
    valid.validate().unwrap();

    let missing_output = valid_completed_event(json!({
        "state": "completed",
        "tokenUsage": {
            "usageScope": "main_agent",
            "usageStatus": "complete",
            "inputTokens": 120,
            "hasSubagents": false
        }
    }));
    expect_validation_error(missing_output.validate());

    let partial = valid_completed_event(json!({
        "state": "completed",
        "tokenUsage": {
            "usageScope": "main_agent",
            "usageStatus": "partial",
            "hasSubagents": false
        }
    }));
    partial.validate().unwrap();
}

#[test]
fn event_validation_rejects_blank_identity_and_invalid_timestamp() {
    let mut event = valid_content_event(json!({
        "streamKind": "assistant_text",
        "delta": "hello"
    }));
    event.validate().unwrap();

    event.event_id.clear();
    expect_validation_error(event.validate());

    let mut event = valid_content_event(json!({
        "streamKind": "assistant_text",
        "delta": "hello"
    }));
    event.provider_instance_id = " ".into();
    expect_validation_error(event.validate());

    let mut event = valid_content_event(json!({
        "streamKind": "assistant_text",
        "delta": "hello"
    }));
    event.thread_id.clear();
    expect_validation_error(event.validate());

    let mut event = valid_content_event(json!({
        "streamKind": "assistant_text",
        "delta": "hello"
    }));
    event.created_at = "not-an-iso-date".into();
    expect_validation_error(event.validate());
}

#[test]
fn event_validation_rejects_blank_provider_refs_and_raw_metadata() {
    let payload = json!({
        "streamKind": "assistant_text",
        "delta": "hello"
    });
    valid_content_event(payload.clone()).validate().unwrap();

    for provider_refs in [
        ProviderRefs {
            provider_turn_id: Some(String::new()),
            ..ProviderRefs::default()
        },
        ProviderRefs {
            provider_item_id: Some(String::new()),
            ..ProviderRefs::default()
        },
        ProviderRefs {
            provider_request_id: Some(String::new()),
            ..ProviderRefs::default()
        },
    ] {
        let mut event = valid_content_event(payload.clone());
        event.provider_refs = Some(provider_refs);
        expect_validation_error(event.validate());
    }

    for raw in [
        RawEvent {
            source: " ".into(),
            method: Some("method".into()),
            message_type: Some("notification".into()),
            payload: json!({}),
        },
        RawEvent {
            source: "source".into(),
            method: Some("\t".into()),
            message_type: Some("notification".into()),
            payload: json!({}),
        },
        RawEvent {
            source: "source".into(),
            method: Some("method".into()),
            message_type: Some("\n".into()),
            payload: json!({}),
        },
    ] {
        let mut event = valid_content_event(payload.clone());
        event.raw = Some(raw);
        expect_validation_error(event.validate());
    }

    let mut valid_raw = valid_content_event(payload);
    valid_raw.raw = Some(RawEvent {
        source: "codex.app-server".into(),
        method: None,
        message_type: None,
        payload: json!({}),
    });
    valid_raw.validate().unwrap();
}

#[test]
fn failed_turn_carries_a_failure_class() {
    let failed = valid_completed_event(json!({
        "state": "failed",
        "errorMessage": "You've hit your usage limit.",
        "failureClass": "usage_limit",
    }));
    failed.validate().unwrap();
    assert_eq!(failed.failure_class(), FailureClass::UsageLimit);

    let plain = valid_completed_event(json!({ "state": "failed" }));
    plain.validate().unwrap();
    assert_eq!(plain.failure_class(), FailureClass::Unknown);

    // A class from a newer adapter still reads, as unknown.
    let newer = valid_completed_event(json!({ "state": "failed", "failureClass": "billing" }));
    newer.validate().unwrap();
    assert_eq!(newer.failure_class(), FailureClass::Unknown);

    for payload in [
        json!({ "state": "completed", "failureClass": "auth" }),
        json!({ "state": "failed", "failureClass": 7 }),
    ] {
        expect_validation_error(valid_completed_event(payload).validate());
    }
}

#[test]
fn rejected_turns_keep_their_detail_and_expose_only_the_class() {
    let error = ProviderError::Rejected {
        class: FailureClass::PreviousTurnActive,
        detail: "turn 3 is still active".into(),
    };
    assert_eq!(error.failure_class(), FailureClass::PreviousTurnActive);
    assert!(error.to_string().contains("turn 3 is still active"));
    assert_eq!(
        ProviderError::InvalidState("x".into()).failure_class(),
        FailureClass::Unknown
    );
}

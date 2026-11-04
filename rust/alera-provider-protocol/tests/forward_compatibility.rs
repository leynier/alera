use alera_provider_protocol::{
    CanonicalItemType, ContentDeltaPayload, EventKind, ItemLifecyclePayload, ItemStatus,
    ProviderEvent, ProviderKind, ProviderRefs, StreamKind, UsageWindow, UsageWindowKind,
    UserInputQuestion,
};
use serde_json::{json, Value};

#[test]
fn unknown_provider_and_event_names_round_trip_without_loss() {
    let fixture = json!({
        "eventId": "00000000-0000-4000-8000-000000000101",
        "provider": "future-agent",
        "providerInstanceId": "future-instance",
        "threadId": "00000000-0000-4000-8000-000000000102",
        "createdAt": "2026-10-12T12:34:56.000Z",
        "type": "future.event.v9",
        "payload": { "newField": { "enabled": true } }
    });

    let event: ProviderEvent = serde_json::from_value(fixture.clone()).unwrap();
    assert_eq!(event.provider, ProviderKind::Other("future-agent".into()));
    assert_eq!(event.kind, EventKind::Unknown("future.event.v9".into()));
    event.validate().unwrap();
    assert_eq!(serde_json::to_value(event).unwrap(), fixture);
}

#[test]
fn optional_refs_questions_and_typed_payload_fields_are_omitted() {
    let refs = serde_json::to_value(ProviderRefs::default()).unwrap();
    assert_eq!(refs, json!({}));

    let question = UserInputQuestion {
        id: "question-1".into(),
        header: "Scope".into(),
        question: "Which files?".into(),
        options: Vec::new(),
        allow_custom_answer: None,
        initial_answer: None,
        multi_select: false,
    };
    let question_wire = serde_json::to_value(&question).unwrap();
    let question_object = question_wire.as_object().unwrap();
    assert!(!question_object.contains_key("allowCustomAnswer"));
    assert!(!question_object.contains_key("initialAnswer"));
    assert_eq!(question_wire["options"], json!([]));

    let content = ContentDeltaPayload {
        stream_kind: StreamKind::AssistantText,
        delta: "hello".into(),
        content_index: None,
        summary_index: None,
    };
    let content_wire = serde_json::to_value(content).unwrap();
    let content_object = content_wire.as_object().unwrap();
    assert!(!content_object.contains_key("contentIndex"));
    assert!(!content_object.contains_key("summaryIndex"));

    let item = ItemLifecyclePayload {
        item_type: CanonicalItemType::AssistantMessage,
        status: Some(ItemStatus::Completed),
        title: None,
        detail: None,
        data: None,
        agent_id: None,
        parent_tool_use_id: None,
    };
    let item_wire = serde_json::to_value(item).unwrap();
    let item_object = item_wire.as_object().unwrap();
    assert_eq!(item_wire["itemType"], "assistant_message");
    assert_eq!(item_wire["status"], "completed");
    for key in ["title", "detail", "data", "agentId", "parentToolUseId"] {
        assert!(
            !item_object.contains_key(key),
            "unexpected optional field: {key}"
        );
    }

    let window = UsageWindow {
        id: "session".into(),
        kind: UsageWindowKind::Session,
        label: "Session".into(),
        used_percent: 25.0,
        resets_at: None,
        window_duration_mins: None,
    };
    let window_wire = serde_json::to_value(window).unwrap();
    let window_object = window_wire.as_object().unwrap();
    assert!(!window_object.contains_key("resetsAt"));
    assert!(!window_object.contains_key("windowDurationMins"));

    assert!(!question_wire.to_string().contains(":null"));
    assert!(!content_wire.to_string().contains(":null"));
    assert!(!item_wire.to_string().contains(":null"));
    assert!(!window_wire.to_string().contains(":null"));
}

fn event(kind: EventKind, payload: Value) -> ProviderEvent {
    let mut event = ProviderEvent::new(
        ProviderKind::Codex,
        "codex-instance",
        "00000000-0000-4000-8000-000000000201",
        kind,
        payload,
        None,
    );
    event.event_id = "00000000-0000-4000-8000-000000000200".into();
    event.created_at = "2026-10-12T12:34:56.000Z".into();
    event
}

fn expect_validation_error(result: Result<(), alera_provider_protocol::ProviderError>) {
    assert!(matches!(
        result,
        Err(alera_provider_protocol::ProviderError::Validation(_))
    ));
}

#[test]
fn item_and_rate_limit_payloads_enforce_required_shape_and_bounds() {
    let valid_item = event(
        EventKind::ItemUpdated,
        json!({ "itemType": "assistant_message", "status": "completed" }),
    );
    valid_item.validate().unwrap();

    let missing_item_type = event(EventKind::ItemUpdated, json!({ "status": "completed" }));
    expect_validation_error(missing_item_type.validate());

    let valid_limits = event(
        EventKind::AccountRateLimitsUpdated,
        json!({
            "limits": {
                "windows": [{
                    "id": "session",
                    "kind": "session",
                    "label": "Session",
                    "usedPercent": 75.0,
                    "resetsAt": "2026-10-12T13:34:56.000Z",
                    "windowDurationMins": 300
                }]
            }
        }),
    );
    valid_limits.validate().unwrap();

    let out_of_range = event(
        EventKind::AccountRateLimitsUpdated,
        json!({
            "limits": {
                "windows": [{
                    "id": "session",
                    "kind": "session",
                    "label": "Session",
                    "usedPercent": 100.1
                }]
            }
        }),
    );
    expect_validation_error(out_of_range.validate());

    let malformed_windows = event(
        EventKind::AccountRateLimitsUpdated,
        json!({ "limits": { "windows": {} } }),
    );
    expect_validation_error(malformed_windows.validate());
}

use alera_agent_transport::MockTransport;
use alera_provider_pi::{PiProvider, PiProviderConfig};
use alera_provider_protocol::{
    CanonicalItemType, EventKind, ItemLifecyclePayload, ItemStatus, Provider, ProviderEvent,
    SessionStartInput, TurnInput,
};
use serde_json::{json, Value};

fn state_response(id: &str) -> Value {
    json!({
        "type": "response",
        "id": id,
        "command": "get_state",
        "success": true,
        "data": {
            "sessionFile": "/tmp/pi/session.jsonl",
            "sessionId": "session-1",
            "isStreaming": false
        }
    })
}

fn provider(messages: Vec<Value>) -> PiProvider<MockTransport> {
    PiProvider::new(MockTransport::new(messages), PiProviderConfig::default())
}

async fn next_valid_event(provider: &mut PiProvider<MockTransport>) -> ProviderEvent {
    let event = provider.next_event().await.unwrap().unwrap();
    event.validate().unwrap();
    event
}

async fn start_session(provider: &mut PiProvider<MockTransport>) {
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    assert_eq!(
        next_valid_event(provider).await.kind,
        EventKind::SessionStarted
    );
    assert_eq!(
        next_valid_event(provider).await.kind,
        EventKind::ThreadStarted
    );
}

#[tokio::test]
async fn startup_notification_preserves_native_records_and_allows_turn_completion() {
    let notification = json!({
        "type": "extension_ui_request",
        "method": "notify",
        "message": "Extension ready",
        "notifyType": "info"
    });
    let unknown_ui = json!({
        "type": "extension_ui_request",
        "id": "extension-status",
        "method": "setStatus",
        "key": "example",
        "text": "Ready"
    });
    let mut provider = provider(vec![
        notification.clone(),
        unknown_ui.clone(),
        state_response("alera-pi-1"),
        json!({ "type": "response", "command": "prompt", "success": true }),
        json!({ "type": "agent_start" }),
        json!({ "type": "agent_settled" }),
        state_response("alera-pi-2"),
    ]);
    start_session(&mut provider).await;
    let event = next_valid_event(&mut provider).await;
    assert_eq!(event.kind, EventKind::ItemCompleted);
    let payload: ItemLifecyclePayload = serde_json::from_value(event.payload.clone()).unwrap();
    assert_eq!(payload.item_type, CanonicalItemType::DynamicToolCall);
    assert_eq!(payload.status, Some(ItemStatus::Completed));
    assert_eq!(payload.title.as_deref(), Some("notify"));
    assert_eq!(payload.detail.as_deref(), Some("Extension ready"));
    assert_eq!(payload.data, Some(notification.clone()));
    assert_eq!(event.raw.unwrap().payload, notification);
    assert!(event.turn_id.is_none());
    let unknown = next_valid_event(&mut provider).await;
    assert_eq!(
        unknown.kind,
        EventKind::Unknown("extension_ui_request".into())
    );
    assert_eq!(unknown.payload, unknown_ui);
    assert_eq!(unknown.raw.unwrap().payload, unknown_ui);
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    assert_eq!(
        next_valid_event(&mut provider).await.kind,
        EventKind::TurnStarted
    );
    let completed = next_valid_event(&mut provider).await;
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["state"], "completed");
    assert!(provider.session().unwrap().active_turn_id.is_none());
    assert!(provider
        .transport()
        .writes()
        .iter()
        .any(|record| record["type"] == "prompt" && record["message"] == "hello"));
}

#[tokio::test]
async fn generic_tool_lifecycle_preserves_structured_output_and_validates_every_event() {
    let start = json!({
        "type": "tool_execution_start",
        "toolCallId": "tool-call-1",
        "toolName": "custom_tool",
        "args": { "query": "example" }
    });
    let update = json!({
        "type": "tool_execution_update",
        "toolCallId": "tool-call-1",
        "toolName": "custom_tool",
        "partialResult": {
            "content": [{ "type": "text", "text": "Working" }],
            "details": { "progress": 0.5 }
        }
    });
    let end = json!({
        "type": "tool_execution_end",
        "toolCallId": "tool-call-1",
        "toolName": "custom_tool",
        "result": {
            "content": [
                { "type": "text", "text": "First result" },
                { "type": "image", "mimeType": "image/png", "data": "aGVsbG8=" },
                { "type": "text", "text": "Second result" }
            ],
            "details": { "count": 2 }
        },
        "isError": false
    });
    let mut provider = provider(vec![
        state_response("alera-pi-1"),
        json!({ "type": "response", "command": "prompt", "success": true }),
        json!({ "type": "agent_start" }),
        start.clone(),
        update.clone(),
        end.clone(),
        json!({ "type": "agent_settled" }),
        state_response("alera-pi-2"),
    ]);
    start_session(&mut provider).await;
    let turn = provider
        .send_turn(TurnInput::text("thread", "run the tool"))
        .await
        .unwrap();
    assert_eq!(
        next_valid_event(&mut provider).await.kind,
        EventKind::TurnStarted
    );
    for (raw, kind, status, detail) in [
        (start, EventKind::ItemStarted, ItemStatus::InProgress, None),
        (
            update,
            EventKind::ItemUpdated,
            ItemStatus::InProgress,
            Some("Working"),
        ),
        (
            end,
            EventKind::ItemCompleted,
            ItemStatus::Completed,
            Some("First result\nSecond result"),
        ),
    ] {
        let event = next_valid_event(&mut provider).await;
        assert_eq!(event.kind, kind);
        assert_eq!(event.turn_id.as_deref(), Some(turn.turn_id.as_str()));
        assert_eq!(event.item_id.as_deref(), Some("tool-call-1"));
        assert_eq!(
            event
                .provider_refs
                .as_ref()
                .unwrap()
                .provider_item_id
                .as_deref(),
            Some("tool-call-1")
        );
        let payload: ItemLifecyclePayload = serde_json::from_value(event.payload).unwrap();
        assert_eq!(payload.item_type, CanonicalItemType::DynamicToolCall);
        assert_eq!(payload.status, Some(status));
        assert_eq!(payload.title.as_deref(), Some("custom_tool"));
        assert_eq!(payload.detail.as_deref(), detail);
        assert_eq!(payload.data, Some(raw.clone()));
        assert_eq!(event.raw.unwrap().payload, raw);
    }
    assert_eq!(
        next_valid_event(&mut provider).await.kind,
        EventKind::TurnCompleted
    );
}

#[tokio::test]
async fn builtins_keep_canonical_categories_and_tool_errors_keep_failed_status() {
    let cases = [
        ("bash", CanonicalItemType::CommandExecution),
        ("powershell", CanonicalItemType::CommandExecution),
        ("edit", CanonicalItemType::FileChange),
        ("write", CanonicalItemType::FileChange),
        ("read", CanonicalItemType::DynamicToolCall),
        ("chat_weather_forecast", CanonicalItemType::DynamicToolCall),
    ];
    let mut records = vec![state_response("alera-pi-1")];
    for (tool, _) in cases {
        for phase in ["start", "update", "end"] {
            let mut record = json!({
                "type": format!("tool_execution_{phase}"),
                "toolCallId": format!("call-{tool}"),
                "toolName": tool,
            });
            match phase {
                "start" => record["args"] = json!({ "command": "example", "path": "file.txt" }),
                "update" => {
                    record["partialResult"] =
                        json!({ "content": [{ "type": "text", "text": "Working" }] });
                }
                "end" => {
                    record["result"] =
                        json!({ "content": [{ "type": "text", "text": "Tool failed" }] });
                    record["isError"] = json!(true);
                }
                _ => unreachable!(),
            }
            records.push(record);
        }
    }
    let mut provider = provider(records);
    start_session(&mut provider).await;
    for (tool, expected_type) in cases {
        for (kind, status, detail) in [
            (EventKind::ItemStarted, ItemStatus::InProgress, None),
            (
                EventKind::ItemUpdated,
                ItemStatus::InProgress,
                Some("Working"),
            ),
            (
                EventKind::ItemCompleted,
                ItemStatus::Failed,
                Some("Tool failed"),
            ),
        ] {
            let event = next_valid_event(&mut provider).await;
            assert_eq!(event.kind, kind);
            assert_eq!(event.item_id, Some(format!("call-{tool}")));
            let payload: ItemLifecyclePayload = serde_json::from_value(event.payload).unwrap();
            assert_eq!(payload.item_type, expected_type);
            assert_eq!(payload.status, Some(status));
            assert_eq!(payload.detail.as_deref(), detail);
        }
    }
}

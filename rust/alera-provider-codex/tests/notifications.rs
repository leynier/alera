mod support;

use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, SessionStartInput, SessionStatus, TurnInput,
};
use serde_json::{json, Value};

fn initialize_response() -> Value {
    json!({
        "id": 1,
        "result": {
            "codexHome": "/tmp/codex",
            "platformFamily": "unix",
            "platformOs": "linux",
            "userAgent": "test",
        }
    })
}

fn thread_response() -> Value {
    json!({ "id": 2, "result": { "thread": { "id": "native" } } })
}

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-notifications".into(),
        ..CodexProviderConfig::default()
    }
}

#[tokio::test]
async fn observed_mcp_startup_notifications_preserve_context_and_allow_first_turn() {
    let frames = ["starting", "ready"].map(|status| {
        json!({
            "method": "mcpServer/startupStatus/updated",
            "params": {
                "threadId": "native",
                "name": "alera",
                "status": status,
                "error": null,
                "failureReason": null,
            }
        })
    });
    let transport = MockTransport::new([
        initialize_response(),
        frames[0].clone(),
        thread_response(),
        frames[1].clone(),
        json!({ "id": 3, "result": { "turn": { "id": "first-turn" } } }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    let session = provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    assert_eq!(session.status, SessionStatus::Ready);

    for frame in frames {
        let event = support::next_event(&mut provider).await.unwrap().unwrap();
        assert_eq!(event.kind, EventKind::McpStatusUpdated);
        assert_eq!(event.thread_id, "app");
        assert_eq!(event.payload, frame["params"]);
        assert_eq!(event.raw.as_ref().unwrap().payload, frame);
        event.validate().unwrap();
    }

    let turn = provider
        .send_turn(TurnInput::text("app", "hello"))
        .await
        .unwrap();
    assert_eq!(turn.native_turn_id.as_deref(), Some("first-turn"));
    assert_eq!(provider.transport().writes()[3]["method"], "turn/start");
}

#[tokio::test]
async fn failed_mcp_startup_preserves_server_status_and_failure_details() {
    let frame = json!({
        "method": "mcpServer/startupStatus/updated",
        "params": {
            "threadId": "native",
            "name": "alera",
            "status": "failed",
            "error": "boom",
            "failureReason": "reauthenticationRequired",
        }
    });
    let transport = MockTransport::new([initialize_response(), thread_response(), frame.clone()]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();

    let event = support::next_event(&mut provider).await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::McpStatusUpdated);
    assert_eq!(event.payload, frame["params"]);
    assert_eq!(event.raw.as_ref().unwrap().payload, frame);
    event.validate().unwrap();
    assert_eq!(provider.session().unwrap().status, SessionStatus::Ready);
}

#[tokio::test]
async fn unknown_notification_with_null_error_survives_without_runtime_error_classification() {
    let frame = json!({
        "method": "future/status/updated",
        "params": {
            "threadId": "native",
            "status": "ready",
            "error": null,
            "extension": { "enabled": true },
        }
    });
    let transport = MockTransport::new([initialize_response(), thread_response(), frame.clone()]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();

    let event = support::next_event(&mut provider).await.unwrap().unwrap();
    assert_eq!(
        event.kind,
        EventKind::Unknown("future/status/updated".into())
    );
    assert_eq!(event.payload, frame["params"]);
    assert_eq!(event.raw.as_ref().unwrap().payload, frame);
    event.validate().unwrap();
}

#[tokio::test]
async fn explicit_and_unknown_nonnull_runtime_errors_remain_canonical() {
    let frames = [
        json!({
            "method": "error",
            "params": {
                "threadId": "native",
                "turnId": "turn-error",
                "error": { "message": "model unavailable", "codexErrorInfo": "other" },
                "willRetry": false,
            }
        }),
        json!({
            "method": "future/runtime/failed",
            "params": { "threadId": "native", "error": "provider unavailable" }
        }),
    ];
    let transport = MockTransport::new([
        initialize_response(),
        thread_response(),
        frames[0].clone(),
        frames[1].clone(),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();

    for (frame, expected_message) in frames
        .into_iter()
        .zip(["model unavailable", "provider unavailable"])
    {
        let event = support::next_event(&mut provider).await.unwrap().unwrap();
        assert_eq!(event.kind, EventKind::RuntimeError);
        assert_eq!(event.payload["message"], expected_message);
        assert_eq!(event.payload["detail"], frame["params"]["error"]);
        assert_eq!(event.raw.as_ref().unwrap().payload, frame);
        event.validate().unwrap();
    }
}

#[tokio::test]
async fn malformed_core_runtime_messages_with_null_errors_are_still_rejected() {
    for method in ["error", "warning", "guardianWarning"] {
        let transport = MockTransport::new([
            initialize_response(),
            thread_response(),
            json!({ "method": method, "params": { "threadId": "native", "error": null } }),
        ]);
        let mut provider = CodexProvider::new(transport, config());
        provider
            .start_session(SessionStartInput::new("app"))
            .await
            .unwrap();

        assert!(matches!(
            support::next_event(&mut provider).await,
            Err(ProviderError::Protocol(message)) if message == "Codex runtime message has no message"
        ));
    }
}

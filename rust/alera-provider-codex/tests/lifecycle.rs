use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    ElicitationAction, EventKind, Provider, ProviderError, RequestId, RuntimeResponse,
    SessionStartInput,
};
use serde_json::{json, Value};

fn initialize_response(id: i64) -> Value {
    json!({
        "id": id,
        "result": {
            "codexHome": "/tmp/codex",
            "platformFamily": "unix",
            "platformOs": "linux",
            "userAgent": "test",
        }
    })
}

fn thread_response(id: i64, native_id: &str) -> Value {
    json!({ "id": id, "result": { "thread": { "id": native_id } } })
}

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-lifecycle".into(),
        ..CodexProviderConfig::default()
    }
}

#[tokio::test]
async fn form_elicitations_use_typed_rpc_ids_when_native_id_is_missing() {
    let transport = MockTransport::new([
        initialize_response(1),
        json!({
            "id": 10,
            "method": "mcpServer/elicitation/request",
            "params": {
                "serverName": "same-server",
                "mode": "form",
                "message": "first",
                "threadId": "native-mcp",
                "turnId": "turn-mcp"
            }
        }),
        json!({
            "id": "10",
            "method": "mcpServer/elicitation/request",
            "params": {
                "serverName": "same-server",
                "mode": "form",
                "message": "second",
                "threadId": "native-mcp",
                "turnId": "turn-mcp"
            }
        }),
        thread_response(2, "native-mcp"),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-mcp"))
        .await
        .unwrap();

    let first = provider.next_event().await.unwrap().unwrap();
    assert_eq!(first.request_id.as_deref(), Some("10"));
    assert_eq!(
        first.runtime_request.as_ref().unwrap().request_id,
        RequestId::Integer(10)
    );
    provider
        .respond(RuntimeResponse::Elicitation {
            request_id: RequestId::Integer(10),
            action: ElicitationAction::Decline,
            content: None,
        })
        .await
        .unwrap();

    let second = provider.next_event().await.unwrap().unwrap();
    assert_eq!(second.request_id.as_deref(), Some("10"));
    assert_eq!(
        second.runtime_request.as_ref().unwrap().request_id,
        RequestId::String("10".into())
    );
    provider
        .respond(RuntimeResponse::Elicitation {
            request_id: RequestId::String("10".into()),
            action: ElicitationAction::Cancel,
            content: Some(json!({ "reason": "cancelled" })),
        })
        .await
        .unwrap();

    let writes = provider.transport().writes();
    assert!(
        writes.contains(&json!({ "id": 10, "result": { "action": "decline", "content": null } }))
    );
    assert!(writes.contains(&json!({
        "id": "10",
        "result": { "action": "cancel", "content": { "reason": "cancelled" } }
    })));
}

#[tokio::test]
async fn one_connection_cannot_replace_a_ready_session() {
    let transport = MockTransport::new([initialize_response(1), thread_response(2, "native-one")]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-one"))
        .await
        .unwrap();
    let error = provider
        .start_session(SessionStartInput::new("app-two"))
        .await
        .unwrap_err();
    assert!(
        matches!(error, ProviderError::InvalidState(message) if message.contains("one session"))
    );
    assert_eq!(provider.transport().writes().len(), 3);
}

#[tokio::test]
async fn lifecycle_notifications_use_canonical_payloads() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-lifecycle"),
        json!({
            "method": "thread/started",
            "params": { "thread": { "id": "native-lifecycle" } }
        }),
        json!({
            "method": "turn/started",
            "params": {
                "threadId": "native-lifecycle",
                "turn": {
                    "id": "native-turn-lifecycle",
                    "model": "gpt-5",
                    "reasoningEffort": "high"
                }
            }
        }),
        json!({
            "method": "thread/status/changed",
            "params": {
                "threadId": "native-lifecycle",
                "status": {
                    "type": "active",
                    "activeFlags": ["waitingOnApproval"]
                }
            }
        }),
        json!({
            "method": "deprecationNotice",
            "params": { "message": "old setting" }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-lifecycle"))
        .await
        .unwrap();

    let thread = provider.next_event().await.unwrap().unwrap();
    assert_eq!(thread.kind, EventKind::ThreadStarted);
    assert_eq!(
        thread.payload,
        json!({ "providerThreadId": "native-lifecycle" })
    );

    let turn = provider.next_event().await.unwrap().unwrap();
    assert_eq!(turn.kind, EventKind::TurnStarted);
    assert_eq!(turn.payload, json!({ "model": "gpt-5", "effort": "high" }));

    let status = provider.next_event().await.unwrap().unwrap();
    assert_eq!(status.kind, EventKind::ThreadStateChanged);
    assert_eq!(
        status.payload,
        json!({ "state": "active", "detail": { "activeFlags": ["waitingOnApproval"] } })
    );

    let deprecation = provider.next_event().await.unwrap().unwrap();
    assert_eq!(deprecation.kind, EventKind::DeprecationNotice);
}

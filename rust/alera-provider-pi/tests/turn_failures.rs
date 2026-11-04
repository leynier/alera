use alera_agent_transport::MockTransport;
use alera_provider_pi::{PiProvider, PiProviderConfig};
use alera_provider_protocol::{EventKind, Provider, ProviderEvent, SessionStartInput, TurnInput};
use serde_json::{json, Value};

const AUTH_ERROR: &str = "OAuth refresh failed: 401 {\"error\":\"invalid_refresh_token\"}";

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

fn prompt_ack() -> Value {
    json!({ "type": "response", "command": "prompt", "success": true })
}

fn assistant_error(error: &str) -> Value {
    json!({
        "type": "message_end",
        "message": {
            "role": "assistant",
            "content": [],
            "stopReason": "error",
            "errorMessage": error
        }
    })
}

async fn next_valid_event(provider: &mut PiProvider<MockTransport>) -> ProviderEvent {
    let event = provider.next_event().await.unwrap().unwrap();
    event.validate().unwrap();
    event
}

async fn start_turn(provider: &mut PiProvider<MockTransport>) {
    if provider.session().is_none() {
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
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    assert_eq!(
        next_valid_event(provider).await.kind,
        EventKind::TurnStarted
    );
}

fn recovery_provider(recovery: Value) -> PiProvider<MockTransport> {
    PiProvider::new(
        MockTransport::new(vec![
            state_response("alera-pi-1"),
            prompt_ack(),
            json!({ "type": "agent_start" }),
            assistant_error(AUTH_ERROR),
            recovery,
            json!({ "type": "agent_settled" }),
            state_response("alera-pi-2"),
        ]),
        PiProviderConfig::default(),
    )
}

#[tokio::test]
async fn assistant_error_fails_settled_turn_and_does_not_leak_to_next_turn() {
    let error_message = assistant_error(AUTH_ERROR);
    let settled = json!({ "type": "agent_settled" });
    let mut provider = PiProvider::new(
        MockTransport::new(vec![
            state_response("alera-pi-1"),
            prompt_ack(),
            json!({ "type": "agent_start" }),
            error_message.clone(),
            json!({ "type": "agent_end" }),
            settled.clone(),
            state_response("alera-pi-2"),
            prompt_ack(),
            json!({ "type": "agent_start" }),
            json!({
                "type": "message_end",
                "message": {
                    "role": "assistant",
                    "content": [{ "type": "text", "text": "Recovered" }],
                    "stopReason": "stop"
                }
            }),
            settled.clone(),
            state_response("alera-pi-3"),
        ]),
        PiProviderConfig::default(),
    );
    start_turn(&mut provider).await;
    let item = next_valid_event(&mut provider).await;
    assert_eq!(item.kind, EventKind::ItemCompleted);
    assert_eq!(item.payload["status"], "failed");
    assert_eq!(item.payload["data"], error_message);
    assert_eq!(item.raw.unwrap().payload, error_message);
    assert_eq!(
        next_valid_event(&mut provider).await.kind,
        EventKind::Unknown("agent_end".into())
    );
    let failed = next_valid_event(&mut provider).await;
    assert_eq!(failed.kind, EventKind::TurnCompleted);
    assert_eq!(failed.payload["state"], "failed");
    assert_eq!(failed.payload["errorMessage"], AUTH_ERROR);
    assert_eq!(failed.payload["stopReason"], "error");
    assert_eq!(failed.raw.unwrap().payload, settled);
    assert!(provider.session().unwrap().active_turn_id.is_none());
    start_turn(&mut provider).await;
    assert_eq!(
        next_valid_event(&mut provider).await.payload["status"],
        "completed"
    );
    let recovered = next_valid_event(&mut provider).await;
    assert_eq!(recovered.kind, EventKind::TurnCompleted);
    assert_eq!(recovered.payload["state"], "completed");
    assert!(recovered.payload.get("errorMessage").is_none());
}

#[tokio::test]
async fn confirmed_retry_recovery_clears_the_prior_assistant_error() {
    for recovery in [
        json!({ "type": "auto_retry_end", "success": true, "attempt": 1 }),
        json!({
            "type": "compaction_end",
            "result": { "summary": "Compacted", "estimatedTokensAfter": 10 },
            "willRetry": true,
            "aborted": false
        }),
        json!({
            "type": "auto_compaction_end",
            "result": { "summary": "Compacted", "estimatedTokensAfter": 10 },
            "willRetry": true,
            "aborted": false
        }),
    ] {
        let mut provider = recovery_provider(recovery.clone());
        start_turn(&mut provider).await;
        assert_eq!(
            next_valid_event(&mut provider).await.payload["status"],
            "failed"
        );
        let native_recovery = next_valid_event(&mut provider).await;
        assert_eq!(native_recovery.payload, recovery);
        assert_eq!(native_recovery.raw.unwrap().payload, recovery);
        let completed = next_valid_event(&mut provider).await;
        assert_eq!(completed.kind, EventKind::TurnCompleted);
        assert_eq!(completed.payload["state"], "completed");
        assert!(completed.payload.get("errorMessage").is_none());
    }
}

#[tokio::test]
async fn unsuccessful_retry_or_non_retrying_compaction_keeps_the_assistant_error() {
    for recovery in [
        json!({ "type": "auto_retry_end", "success": false, "finalError": AUTH_ERROR }),
        json!({ "type": "compaction_end", "result": { "summary": "Compacted" }, "willRetry": false }),
        json!({ "type": "compaction_end", "result": null, "willRetry": true }),
        json!({ "type": "compaction_end", "result": "invalid", "willRetry": true }),
        json!({ "type": "compaction_end", "result": { "summary": "Compacted" }, "willRetry": true, "aborted": true }),
    ] {
        let mut provider = recovery_provider(recovery);
        start_turn(&mut provider).await;
        next_valid_event(&mut provider).await;
        next_valid_event(&mut provider).await;
        let failed = next_valid_event(&mut provider).await;
        assert_eq!(failed.kind, EventKind::TurnCompleted);
        assert_eq!(failed.payload["state"], "failed");
        assert_eq!(failed.payload["errorMessage"], AUTH_ERROR);
    }
}

#[tokio::test]
async fn assistant_failure_without_error_text_still_fails_terminal_settlement() {
    let mut provider = PiProvider::new(
        MockTransport::new(vec![
            state_response("alera-pi-1"),
            prompt_ack(),
            json!({ "type": "agent_start" }),
            assistant_error(" "),
            json!({ "type": "agent_settled" }),
            state_response("alera-pi-2"),
        ]),
        PiProviderConfig::default(),
    );
    start_turn(&mut provider).await;
    next_valid_event(&mut provider).await;
    let failed = next_valid_event(&mut provider).await;
    assert_eq!(failed.payload["state"], "failed");
    assert_eq!(failed.payload["errorMessage"], "Pi reported a model error");
}

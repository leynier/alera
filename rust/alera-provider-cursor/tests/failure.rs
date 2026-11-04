use alera_provider_cursor::{CursorProvider, CursorProviderConfig};
use alera_provider_protocol::{
    EventKind, FailureClass, Provider, ProviderEvent, SessionStartInput, TurnInput,
};
use cursor_agent_sdk::{encode_connect_frame, CursorClient, CursorSdkError, MockBridgeTransport};
use serde_json::{json, Value};

fn bridge() -> MockBridgeTransport {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    mock
}

async fn started(mock: &MockBridgeTransport) -> CursorProvider {
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
}

async fn terminal(frames: Vec<Vec<u8>>) -> ProviderEvent {
    let mock = bridge();
    mock.push_stream(frames);
    let mut provider = started(&mock).await;
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    while let Some(event) = provider.next_event().await.unwrap() {
        if event.kind == EventKind::TurnCompleted {
            return event;
        }
    }
    panic!("the turn never completed");
}

fn failed_result(error_code: &str) -> Vec<u8> {
    encode_connect_frame(&json!({"result": {
        "runId": "run-1",
        "status": "RUN_LIFECYCLE_STATUS_ERROR",
        "errorCode": error_code,
        "result": {"errorMessage": "You've hit your usage limit"}
    }}))
    .unwrap()
}

fn class(event: &ProviderEvent) -> &Value {
    &event.payload["failureClass"]
}

#[tokio::test]
async fn a_run_that_ends_on_a_usage_or_rate_limit_code_is_a_usage_limit() {
    for code in [
        "PRO_USER_USAGE_LIMIT",
        "RATE_LIMITED",
        "USAGE_LIMIT_EXCEEDED",
    ] {
        let completed = terminal(vec![failed_result(code)]).await;
        assert_eq!(completed.payload["state"], "failed");
        assert_eq!(class(&completed), "usage_limit", "{code}");
        assert_eq!(completed.failure_class(), FailureClass::UsageLimit);
    }
    let other = terminal(vec![failed_result("UPSTREAM_ERROR")]).await;
    assert_eq!(class(&other), "unknown");
}

#[tokio::test]
async fn a_stream_that_ends_on_resource_exhausted_is_a_usage_limit() {
    let mut end_error = encode_connect_frame(&json!({
        "error": {"code": "resource_exhausted", "message": "Too many requests"}
    }))
    .unwrap();
    end_error[0] = 2;
    let completed = terminal(vec![end_error]).await;
    assert_eq!(completed.payload["state"], "failed");
    assert_eq!(class(&completed), "usage_limit");
}

#[tokio::test]
async fn a_send_refused_on_a_rate_limit_rejects_the_turn_as_a_usage_limit() {
    let mock = bridge();
    mock.push_stream_error(CursorSdkError::Http {
        status: 429,
        message: "bridge request failed".into(),
    });
    mock.push_stream_error(CursorSdkError::Http {
        status: 503,
        message: "bridge request failed".into(),
    });
    let mut provider = started(&mock).await;
    let limited = provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap_err();
    assert_eq!(limited.failure_class(), FailureClass::UsageLimit);
    let unavailable = provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap_err();
    assert_eq!(unavailable.failure_class(), FailureClass::Unknown);
}

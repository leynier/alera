use alera_provider_opencode::{
    HttpResponse, MockHttpTransport, OpenCodeGeneration, OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{
    EventKind, FailureClass, Provider, ProviderEvent, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};

async fn provider(
    generation: OpenCodeGeneration,
    event: Value,
) -> OpenCodeProvider<MockHttpTransport> {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"s1"})).unwrap(),
    ));
    // The session start lists commands; a failed listing publishes nothing.
    transport.push_response(HttpResponse::new(404, Vec::new()));
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"m1"})).unwrap(),
    ));
    transport.push_stream([format!("data: {event}\n\n").into_bytes()]);
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation,
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider
}

/// The event that ends a turn sent with `event` on the stream.
async fn terminal(generation: OpenCodeGeneration, event: Value) -> ProviderEvent {
    let mut provider = provider(generation, event).await;
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::TurnCompleted {
            return event;
        }
    }
}

fn execution_failed(error: Value) -> Value {
    json!({"type":"session.execution.failed","data":{"sessionID":"s1","error":error}})
}

fn legacy_session_error(error: Value) -> Value {
    json!({"type":"session.error","properties":{"sessionID":"s1","error":error}})
}

#[tokio::test]
async fn v2_quota_and_rate_limit_stops_are_usage_limits() {
    for error in [
        json!({"type":"provider.quota","message":"Subscription quota exceeded.","status":429}),
        json!({"type":"provider.quota","message":"Upstream request failed: Account budget exceeded"}),
        json!({"type":"provider.rate-limit","message":"Rate limit exceeded: free-models-per-min.","status":429}),
    ] {
        let event = terminal(OpenCodeGeneration::V2, execution_failed(error.clone())).await;
        assert_eq!(event.payload["state"], "failed");
        assert_eq!(event.failure_class(), FailureClass::UsageLimit, "{error}");
        assert_eq!(event.payload["errorMessage"], error["message"]);
    }
}

#[tokio::test]
async fn v2_out_of_funds_and_other_failures_keep_only_opencodes_message() {
    for error in [
        // An empty balance never resets, so it is no usage limit.
        json!({"type":"provider.quota","message":"Upstream request failed: Insufficient account funds","status":402}),
        json!({"type":"provider","message":"Provider rejected the request"}),
    ] {
        let event = terminal(OpenCodeGeneration::V2, execution_failed(error.clone())).await;
        assert_eq!(event.payload["state"], "failed");
        assert!(event.payload.get("failureClass").is_none(), "{error}");
        assert_eq!(event.payload["errorMessage"], error["message"]);
    }
}

#[tokio::test]
async fn legacy_api_error_429_is_a_usage_limit() {
    let event = terminal(
        OpenCodeGeneration::Legacy1,
        legacy_session_error(json!({"name":"APIError","data":{
            "message":"Provider rejected request","statusCode":429,"isRetryable":true
        }})),
    )
    .await;
    assert_eq!(event.payload["state"], "failed");
    assert_eq!(event.failure_class(), FailureClass::UsageLimit);
    assert_eq!(event.payload["errorMessage"], "Provider rejected request");
}

#[tokio::test]
async fn legacy_api_error_402_is_unclassified() {
    let event = terminal(
        OpenCodeGeneration::Legacy1,
        legacy_session_error(json!({"name":"APIError","data":{
            "message":"Insufficient balance","statusCode":402,"isRetryable":false
        }})),
    )
    .await;
    assert_eq!(event.payload["state"], "failed");
    assert!(event.payload.get("failureClass").is_none());
    assert_eq!(event.payload["errorMessage"], "Insufficient balance");
}

#[tokio::test]
async fn a_session_error_between_turns_carries_its_class() {
    let mut provider = provider(
        OpenCodeGeneration::Legacy1,
        legacy_session_error(json!({"name":"APIError","data":{
            "message":"Too many requests","statusCode":429
        }})),
    )
    .await;
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    let error = provider.next_event().await.unwrap().unwrap();
    assert_eq!(error.kind, EventKind::RuntimeError);
    assert_eq!(error.payload["message"], "Too many requests");
    assert_eq!(error.failure_class(), FailureClass::UsageLimit);
}

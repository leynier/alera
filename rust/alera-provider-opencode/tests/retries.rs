use alera_provider_opencode::{
    HttpResponse, MockHttpTransport, OpenCodeGeneration, OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput, TurnInput};
use serde_json::json;

#[tokio::test]
async fn v2_scheduled_retries_are_notices_in_the_turn() {
    let retry = json!({"type": "session.retry.scheduled", "created": 1_700_000_000_000_i64, "data": {
        "sessionID": "s1", "assistantMessageID": "msg_1", "attempt": 2,
        "at": 1_700_000_002_500_i64, "error": {"type": "provider.error", "message": "Rate limited"}
    }});
    let bare = json!({"type": "session.retry.scheduled", "data": {"sessionID": "s1", "error": {}}});
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(200, br#"{"id":"s1"}"#.to_vec()));
    transport.push_response(HttpResponse::new(404, Vec::new()));
    transport.push_response(HttpResponse::new(200, br#"{"id":"m1"}"#.to_vec()));
    transport.push_stream([format!("data: {retry}\n\ndata: {bare}\n\n").into_bytes()]);
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation: OpenCodeGeneration::V2,
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let turn = provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    let mut warnings = Vec::new();
    while let Ok(Some(event)) = provider.next_event().await {
        if event.kind == EventKind::RuntimeWarning {
            warnings.push(event);
        }
    }
    assert_eq!(warnings.len(), 2);
    assert_eq!(
        warnings[0].payload["message"],
        "OpenCode is retrying after Rate limited (retry 1, in 3s)."
    );
    assert_eq!(warnings[0].payload["attempt"], 1);
    assert_eq!(warnings[0].payload["retryDelayMs"], 2500);
    assert_eq!(warnings[0].turn_id.as_deref(), Some(turn.turn_id.as_str()));
    assert_eq!(
        warnings[1].payload["message"],
        "OpenCode is retrying after a provider error."
    );
}

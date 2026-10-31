use alera_provider_opencode::{
    HttpResponse, MockHttpTransport, OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput, TurnInput};
use serde_json::json;

#[tokio::test]
async fn cancelled_todos_leave_the_plan() {
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
    transport.push_stream([br#"data: {"type":"todo.updated","properties":{"sessionID":"s1","todos":[{"content":"Write the fix","status":"completed","priority":"high"},{"content":"Try another approach","status":"cancelled","priority":"low"},{"content":"Add a test","status":"in_progress","priority":"medium"}]}}

"#
    .to_vec()]);
    let mut provider = OpenCodeProvider::new(transport, OpenCodeProviderConfig::default());
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("thread", "fix it"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let plan = provider.next_event().await.unwrap().unwrap();
    assert_eq!(plan.kind, EventKind::TurnPlanUpdated);
    assert_eq!(
        plan.payload["plan"],
        json!([
            {"content":"Write the fix","status":"completed","priority":"high"},
            {"content":"Add a test","status":"in_progress","priority":"medium"}
        ])
    );
}

use alera_provider_cursor::{CursorProvider, CursorProviderConfig};
use alera_provider_protocol::{EventKind, Provider, ProviderEvent, SessionStartInput, TurnInput};
use cursor_agent_sdk::{encode_connect_frame, CursorClient, MockBridgeTransport};
use serde_json::{json, Value};

const RESUME_NO_PROGRESS: &str =
    "Agent turn stopped after repeated resume attempts made no progress";

fn update(kind: &str, text: Option<&str>) -> Value {
    match text {
        Some(text) => json!({"interactionUpdate": {"type": kind, "update": {"delta": text}}}),
        None => json!({"interactionUpdate": {"type": kind, "update": {}}}),
    }
}

fn failed_status() -> Value {
    json!({"sdkMessage": {"type": "status", "message": {
        "runId": "run-1", "status": "ERROR", "message": RESUME_NO_PROGRESS
    }}})
}

fn failed_result(text: Option<&str>) -> Value {
    let run = match text {
        Some(text) => json!({"result": text}),
        None => json!({}),
    };
    json!({"result": {"runId": "run-1", "status": "RUN_LIFECYCLE_STATUS_ERROR", "result": run}})
}

/// Runs one turn over `frames` (and `waits` for stream recovery) and returns
/// every event after `turn.started`.
async fn turn_events(frames: Vec<Value>, waits: Vec<Value>) -> Vec<ProviderEvent> {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    for wait in waits {
        mock.push_unary(Ok(wait));
    }
    mock.push_stream(
        frames
            .iter()
            .map(|frame| encode_connect_frame(frame).unwrap())
            .collect(),
    );
    let client = CursorClient::with_transport(mock, "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    let mut events = Vec::new();
    while let Some(event) = provider.next_event().await.unwrap() {
        events.push(event);
    }
    events
}

fn answers(events: &[ProviderEvent]) -> Vec<&str> {
    events
        .iter()
        .filter(|event| event.kind == EventKind::ContentDelta)
        .filter_map(|event| event.payload["delta"].as_str())
        .collect()
}

fn terminal(events: &[ProviderEvent]) -> &ProviderEvent {
    let terminal = events.last().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    terminal
}

#[tokio::test]
async fn a_resume_that_made_no_progress_after_the_turn_ended_completes_it() {
    let events = turn_events(
        vec![
            update("text-delta", Some("The answer.")),
            update("turn-ended", None),
            update("text-delta", Some("A regenerated closing.")),
            update("turn-ended", None),
            failed_status(),
            failed_result(None),
            json!({"done": {"runId": "run-1"}}),
        ],
        vec![],
    )
    .await;
    let terminal = terminal(&events);
    assert_eq!(terminal.payload["state"], "completed");
    assert!(terminal.payload.get("errorMessage").is_none());
    assert!(terminal.payload.get("failureClass").is_none());
    assert!(events
        .iter()
        .all(|event| event.kind != EventKind::RuntimeError));
    assert_eq!(answers(&events), ["The answer.", "A regenerated closing."]);
}

#[tokio::test]
async fn the_resume_error_still_fails_a_continuation_after_the_turn_ended() {
    let events = turn_events(
        vec![
            update("text-delta", Some("The answer.")),
            update("turn-ended", None),
            update("text-delta", Some("Following up on the stop hook.")),
            failed_status(),
            failed_result(None),
        ],
        vec![],
    )
    .await;
    let terminal = terminal(&events);
    assert_eq!(terminal.payload["state"], "failed");
    assert_eq!(terminal.payload["errorMessage"], RESUME_NO_PROGRESS);
    assert!(events
        .iter()
        .any(|event| event.kind == EventKind::RuntimeError));
}

#[tokio::test]
async fn text_from_a_resume_that_made_no_progress_is_not_the_answer() {
    let events = turn_events(
        vec![
            update("turn-ended", None),
            failed_status(),
            failed_result(Some("A regenerated closing.")),
        ],
        vec![],
    )
    .await;
    assert_eq!(terminal(&events).payload["state"], "completed");
    assert!(answers(&events).is_empty());
}

#[tokio::test]
async fn a_recovered_run_that_failed_its_late_resume_completes_the_turn() {
    let events = turn_events(
        vec![
            json!({"sdkMessage": {"type": "status", "message": {"runId": "run-1", "status": "running"}}}),
            update("text-delta", Some("The answer.")),
            update("turn-ended", None),
            json!("malformed-envelope"),
        ],
        vec![json!({"result": {
            "runId": "run-1",
            "status": "RUN_LIFECYCLE_STATUS_ERROR",
            "errorMessage": RESUME_NO_PROGRESS,
            "result": "A regenerated closing."
        }})],
    )
    .await;
    assert_eq!(terminal(&events).payload["state"], "completed");
    assert_eq!(answers(&events), ["The answer."]);
}

#[tokio::test]
async fn other_errors_after_the_turn_ended_still_fail_it() {
    let events = turn_events(
        vec![
            update("text-delta", Some("The answer.")),
            update("turn-ended", None),
            json!({"sdkMessage": {"type": "status", "message": {
                "runId": "run-1", "status": "ERROR", "message": "Model unavailable"
            }}}),
            failed_result(None),
        ],
        vec![],
    )
    .await;
    let terminal = terminal(&events);
    assert_eq!(terminal.payload["state"], "failed");
    assert_eq!(terminal.payload["errorMessage"], "Model unavailable");
}

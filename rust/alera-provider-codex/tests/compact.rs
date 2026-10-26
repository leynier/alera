use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    Attachment, EventKind, NativeForkInput, Provider, ProviderError, SessionStartInput,
    SessionStatus, TurnInput,
};
use serde_json::{json, Value};

fn initialize() -> Value {
    json!({ "id": 1, "result": { "codexHome": "/tmp/codex", "userAgent": "test" } })
}

fn thread() -> Value {
    json!({ "id": 2, "result": { "thread": { "id": "native" } } })
}

fn notification(method: &str, params: Value) -> Value {
    json!({ "method": method, "params": params })
}

fn turn_started(thread: &str, turn: &str) -> Value {
    notification(
        "turn/started",
        json!({ "threadId": thread, "turn": { "id": turn, "status": "inProgress", "items": [] } }),
    )
}

fn compaction_item(method: &str) -> Value {
    notification(
        method,
        json!({
            "threadId": "native",
            "turnId": "turn-compact",
            "item": { "id": "compaction-1", "type": "contextCompaction" },
        }),
    )
}

fn turn_completed(turn: &str) -> Value {
    notification(
        "turn/completed",
        json!({ "threadId": "native", "turn": { "id": turn, "status": "completed", "items": [] } }),
    )
}

async fn started(frames: impl IntoIterator<Item = Value>) -> CodexProvider<MockTransport> {
    let frames = [initialize(), thread()].into_iter().chain(frames);
    let mut provider =
        CodexProvider::new(MockTransport::new(frames), CodexProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    let commands = provider.next_event().await.unwrap().unwrap();
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    provider
}

#[tokio::test]
async fn session_start_resume_and_fork_advertise_compact() {
    let expected = json!({ "commands": [{
        "name": "compact",
        "description": "Summarize the conversation and reduce context usage",
    }] });
    let start = SessionStartInput::new("app");
    let mut resume = SessionStartInput::new("app");
    resume.resume_thread_id = Some("native".into());
    for input in [start, resume] {
        let mut provider = CodexProvider::new(
            MockTransport::new([initialize(), thread()]),
            CodexProviderConfig::default(),
        );
        provider.start_session(input).await.unwrap();
        let event = provider.next_event().await.unwrap().unwrap();
        assert_eq!(event.kind, EventKind::SessionCommandsUpdated);
        assert_eq!(event.thread_id, "app");
        assert_eq!(event.payload, expected);
        assert!(provider.next_event().await.unwrap().is_none());
    }

    let mut provider = CodexProvider::new(
        MockTransport::new([initialize(), thread()]),
        CodexProviderConfig::default(),
    );
    provider
        .fork_session(NativeForkInput {
            source_native_thread_id: "source".into(),
            session: SessionStartInput::new("app"),
            boundary: None,
        })
        .await
        .unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.payload, expected);
}

#[tokio::test]
async fn compact_runs_thread_compact_start_and_adopts_the_next_root_turn() {
    let mut provider = started([
        json!({ "id": 3, "result": {} }),
        turn_started("native", "turn-compact"),
        compaction_item("item/started"),
        compaction_item("item/completed"),
        turn_completed("turn-compact"),
    ])
    .await;

    let result = provider
        .send_turn(TurnInput::text("app", "  /Compact \n"))
        .await
        .unwrap();
    assert_eq!(result.turn_id, "turn-compact");
    assert_eq!(result.native_turn_id.as_deref(), Some("turn-compact"));
    assert_eq!(
        provider.transport().writes()[3],
        json!({ "id": 3, "method": "thread/compact/start", "params": { "threadId": "native" } })
    );
    assert_eq!(provider.transport().writes().len(), 4);
    let session = provider.session().unwrap();
    assert_eq!(session.status, SessionStatus::Running);
    assert_eq!(session.active_turn_id.as_deref(), Some("turn-compact"));

    let mut kinds = Vec::new();
    while let Some(event) = provider.next_event().await.unwrap() {
        assert_eq!(event.thread_id, "app");
        assert_eq!(event.turn_id.as_deref(), Some("turn-compact"));
        kinds.push(event.kind);
    }
    assert_eq!(
        kinds,
        [
            EventKind::TurnStarted,
            EventKind::ItemStarted,
            EventKind::ItemCompleted,
            EventKind::TurnCompleted,
        ]
    );
    let session = provider.session().unwrap();
    assert_eq!(session.status, SessionStatus::Ready);
    assert_eq!(session.active_turn_id, None);
}

#[tokio::test]
async fn a_turn_started_before_the_compact_answer_is_adopted() {
    let mut provider = started([
        turn_started("native", "turn-compact"),
        json!({ "id": 3, "result": {} }),
        turn_completed("turn-compact"),
    ])
    .await;
    let result = provider
        .send_turn(TurnInput::text("app", "/compact"))
        .await
        .unwrap();
    assert_eq!(result.turn_id, "turn-compact");
    let first = provider.next_event().await.unwrap().unwrap();
    assert_eq!(first.kind, EventKind::TurnStarted);
    assert_eq!(first.turn_id.as_deref(), Some("turn-compact"));
}

#[tokio::test]
async fn only_a_turn_on_the_session_thread_is_adopted() {
    let mut provider = started([
        json!({ "id": 3, "result": {} }),
        turn_started("unrelated-native", "turn-elsewhere"),
        turn_started("native", "turn-compact"),
    ])
    .await;
    let result = provider
        .send_turn(TurnInput::text("app", "/compact"))
        .await
        .unwrap();
    assert_eq!(result.turn_id, "turn-compact");
}

#[tokio::test]
async fn compact_with_more_text_or_attachments_is_an_ordinary_turn() {
    let mut provider =
        started([json!({ "id": 3, "result": { "turn": { "id": "turn-1" } } })]).await;
    provider
        .send_turn(TurnInput::text("app", "/compact now"))
        .await
        .unwrap();
    assert_eq!(provider.transport().writes()[3]["method"], "turn/start");

    let mut provider =
        started([json!({ "id": 3, "result": { "turn": { "id": "turn-1" } } })]).await;
    let mut turn = TurnInput::text("app", "/compact");
    turn.attachments.push(Attachment::Image {
        url: "https://example.test/a.png".into(),
    });
    provider.send_turn(turn).await.unwrap();
    let write = &provider.transport().writes()[3];
    assert_eq!(write["method"], "turn/start");
    assert_eq!(write["params"]["input"][0]["text"], "/compact");
}

#[tokio::test]
async fn a_failed_compact_request_leaves_the_session_ready_for_the_next_turn() {
    let mut provider = started([
        json!({ "id": 3, "error": { "code": -32600, "message": "compaction refused" } }),
        json!({ "id": 4, "result": { "turn": { "id": "turn-next" } } }),
    ])
    .await;
    let error = provider
        .send_turn(TurnInput::text("app", "/compact"))
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::Rpc { .. }));
    let session = provider.session().unwrap();
    assert_eq!(session.status, SessionStatus::Ready);
    assert_eq!(session.active_turn_id, None);

    let result = provider
        .send_turn(TurnInput::text("app", "hello"))
        .await
        .unwrap();
    assert_eq!(result.turn_id, "turn-next");
    assert_eq!(provider.transport().writes()[4]["method"], "turn/start");
}

#[tokio::test]
async fn compact_without_a_following_turn_fails_the_start() {
    let mut provider = started([json!({ "id": 3, "result": {} })]).await;
    let error = provider
        .send_turn(TurnInput::text("app", "/compact"))
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::Closed));
    assert_eq!(provider.session().unwrap().active_turn_id, None);
}

#[tokio::test]
async fn compaction_is_never_steered() {
    let mut provider = started([
        json!({ "id": 3, "result": { "turn": { "id": "turn-1" } } }),
        turn_completed("turn-1"),
        json!({ "id": 4, "result": {} }),
        turn_started("native", "turn-compact"),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("app", "first"))
        .await
        .unwrap();
    let error = provider
        .steer_turn(TurnInput::text("app", "/compact"), "turn-1")
        .await
        .unwrap_err();
    assert!(
        matches!(error, ProviderError::Unsupported(message) if message.starts_with("Context compaction must run as a separate turn"))
    );
    while provider.next_event().await.unwrap().unwrap().kind != EventKind::TurnCompleted {}

    provider
        .send_turn(TurnInput::text("app", "/compact"))
        .await
        .unwrap();
    let error = provider
        .steer_turn(TurnInput::text("app", "keep going"), "turn-compact")
        .await
        .unwrap_err();
    assert!(
        matches!(error, ProviderError::Unsupported(message) if message == "Wait for context compaction to finish before steering the thread.")
    );
    assert_eq!(provider.transport().writes().len(), 5);
}

use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    Attachment, EventKind, FeedbackUploadInput, Provider, ProviderError, SessionStartInput,
    SessionStatus, TurnInput,
};
use serde_json::{json, Value};

fn initialize() -> Value {
    json!({ "id": 1, "result": { "codexHome": "/tmp/codex", "userAgent": "test" } })
}

fn thread() -> Value {
    json!({ "id": 2, "result": { "thread": { "id": "native" } } })
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
async fn feedback_uploads_the_native_thread_with_logs_as_t3_code_does() {
    let mut provider = started([json!({
        "id": 3,
        "result": { "threadId": "feedback-thread-1", "promptHash": "abc" },
    })])
    .await;

    let result = provider
        .upload_feedback(FeedbackUploadInput::new(Some("  The diff was empty.  ")))
        .await
        .unwrap();

    assert_eq!(result.feedback_id, "feedback-thread-1");
    assert_eq!(
        provider.transport().writes()[3],
        json!({
            "id": 3,
            "method": "feedback/upload",
            "params": {
                "classification": "bug",
                "includeLogs": true,
                "reason": "The diff was empty.",
                "threadId": "native",
            },
        })
    );
    assert_eq!(provider.session().unwrap().status, SessionStatus::Ready);
}

#[tokio::test]
async fn feedback_without_a_reason_omits_it() {
    let mut provider = started([json!({ "id": 3, "result": { "threadId": "fb" } })]).await;
    provider
        .upload_feedback(FeedbackUploadInput {
            reason: Some("   ".into()),
        })
        .await
        .unwrap();
    let params = &provider.transport().writes()[3]["params"];
    assert_eq!(
        params,
        &json!({ "classification": "bug", "includeLogs": true, "threadId": "native" })
    );
}

#[tokio::test]
async fn notifications_read_during_the_upload_stay_queued_in_order() {
    let mut provider = started([
        json!({ "method": "thread/name/updated", "params": { "threadId": "native", "threadName": "Bug" } }),
        json!({ "id": 3, "result": { "threadId": "fb" } }),
    ])
    .await;
    provider
        .upload_feedback(FeedbackUploadInput::default())
        .await
        .unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.raw.unwrap().payload["method"], "thread/name/updated");
}

#[tokio::test]
async fn a_refused_upload_surfaces_codex_error() {
    let mut provider = started([json!({
        "id": 3,
        "error": { "code": -32603, "message": "feedback upload failed: offline" },
    })])
    .await;
    let error = provider
        .upload_feedback(FeedbackUploadInput::default())
        .await
        .unwrap_err();
    match error {
        ProviderError::Rpc { message, .. } => {
            assert_eq!(message, "feedback upload failed: offline")
        }
        other => panic!("unexpected error: {other:?}"),
    }
}

#[tokio::test]
async fn an_answer_without_a_thread_id_is_a_protocol_error() {
    let mut provider = started([json!({ "id": 3, "result": {} })]).await;
    let error = provider
        .upload_feedback(FeedbackUploadInput::default())
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::Protocol(_)), "{error:?}");
}

#[tokio::test]
async fn feedback_needs_a_session() {
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize()]),
        CodexProviderConfig::default(),
    );
    let error = provider
        .upload_feedback(FeedbackUploadInput::default())
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::InvalidState(_)), "{error:?}");
    assert!(provider.transport().writes().is_empty());
}

#[tokio::test]
async fn a_feedback_turn_is_refused_instead_of_reaching_the_model() {
    for text in [
        "/feedback",
        "  /Feedback  the diff was empty\n",
        "/FEEDBACK\tnow",
    ] {
        let mut provider = started([]).await;
        let error = provider
            .send_turn(TurnInput::text("app", text))
            .await
            .unwrap_err();
        assert!(matches!(error, ProviderError::Unsupported(_)), "{text}");
        assert_eq!(provider.transport().writes().len(), 3, "{text}");
    }
}

#[tokio::test]
async fn similar_text_or_attachments_start_an_ordinary_turn() {
    for text in ["/feedbacks", "please /feedback", "/feedback-now"] {
        let mut provider =
            started([json!({ "id": 3, "result": { "turn": { "id": "turn-1" } } })]).await;
        provider
            .send_turn(TurnInput::text("app", text))
            .await
            .unwrap();
        assert_eq!(provider.transport().writes()[3]["method"], "turn/start");
    }
    let mut provider =
        started([json!({ "id": 3, "result": { "turn": { "id": "turn-1" } } })]).await;
    let mut turn = TurnInput::text("app", "/feedback");
    turn.attachments.push(Attachment::Image {
        url: "https://example.test/a.png".into(),
    });
    provider.send_turn(turn).await.unwrap();
    assert_eq!(provider.transport().writes()[3]["method"], "turn/start");
}

use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    EventKind, FailureClass, Provider, ProviderError, ProviderEvent, SessionStartInput, TurnInput,
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

fn failed_turn(error_info: Option<Value>) -> Value {
    let mut error = json!({ "message": "turn failed" });
    if let Some(info) = error_info {
        error["codexErrorInfo"] = info;
    }
    json!({
        "method": "turn/completed",
        "params": {
            "threadId": "native",
            "turn": { "id": "root-turn", "status": "failed", "error": error },
        }
    })
}

fn error_notification(error_info: Value, will_retry: bool) -> Value {
    json!({
        "method": "error",
        "params": {
            "threadId": "native",
            "turnId": "root-turn",
            "error": { "message": "stream failed", "codexErrorInfo": error_info },
            "willRetry": will_retry,
        }
    })
}

fn child_notification(method: &str) -> Value {
    json!({
        "method": method,
        "params": {
            "threadId": "child",
            "turn": { "id": "child-turn", "status": "completed" },
        }
    })
}

fn child_spawned() -> Value {
    json!({
        "method": "thread/started",
        "params": { "thread": { "id": "child", "parentThreadId": "native" } }
    })
}

async fn observe(frames: Vec<Value>) -> Vec<ProviderEvent> {
    let count = frames.len();
    let mut transport = vec![initialize_response(), thread_response()];
    transport.extend(frames);
    let mut provider = CodexProvider::new(
        MockTransport::new(transport),
        CodexProviderConfig::default(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    let mut events = Vec::new();
    for _ in 0..count {
        let event = provider.next_event().await.unwrap().unwrap();
        event.validate().unwrap();
        events.push(event);
    }
    events
}

#[tokio::test]
async fn failed_turns_are_classified_from_codex_error_info() {
    for (info, class) in [
        (json!("usageLimitExceeded"), FailureClass::UsageLimit),
        (json!("rateLimitExceeded"), FailureClass::UsageLimit),
        (
            json!({ "responseTooManyFailedAttempts": { "httpStatusCode": 429 } }),
            FailureClass::UsageLimit,
        ),
        (
            json!({ "responseTooManyFailedAttempts": { "httpStatusCode": 503 } }),
            FailureClass::Unknown,
        ),
        (
            json!("contextWindowExceeded"),
            FailureClass::ContextWindowFull,
        ),
        (json!("unauthorized"), FailureClass::Auth),
        (
            json!({ "httpConnectionFailed": { "httpStatusCode": 429 } }),
            FailureClass::Unknown,
        ),
        (json!("other"), FailureClass::Unknown),
    ] {
        let events = observe(vec![failed_turn(Some(info.clone()))]).await;
        let terminal = &events[0];
        assert_eq!(terminal.kind, EventKind::TurnCompleted);
        assert_eq!(terminal.failure_class(), class, "{info}");
        assert_eq!(terminal.payload["errorMessage"], "turn failed");
        assert!(!terminal.child_turns_continue());
    }
}

#[tokio::test]
async fn a_completion_without_error_info_keeps_the_final_error_notification_class() {
    let events = observe(vec![
        error_notification(json!("contextWindowExceeded"), true),
        error_notification(
            json!({ "responseTooManyFailedAttempts": { "httpStatusCode": 429 } }),
            false,
        ),
        failed_turn(None),
    ])
    .await;
    assert_eq!(events[0].kind, EventKind::RuntimeError);
    assert_eq!(events[0].failure_class(), FailureClass::ContextWindowFull);
    assert_eq!(events[1].failure_class(), FailureClass::UsageLimit);
    assert_eq!(events[2].failure_class(), FailureClass::UsageLimit);

    // An explicit class on the completion wins over the notification.
    let explicit = observe(vec![
        error_notification(json!("usageLimitExceeded"), false),
        failed_turn(Some(json!("unauthorized"))),
    ])
    .await;
    assert_eq!(explicit[1].failure_class(), FailureClass::Auth);
}

#[tokio::test]
async fn a_failed_root_turn_leaves_running_native_children_to_report_their_own_ends() {
    let events = observe(vec![
        child_spawned(),
        child_notification("turn/started"),
        failed_turn(Some(json!("other"))),
        child_notification("turn/completed"),
        failed_turn(None),
    ])
    .await;
    let kinds: Vec<_> = events.iter().map(|event| event.kind.clone()).collect();
    assert_eq!(
        kinds,
        [
            EventKind::TaskStarted,
            EventKind::TaskStarted,
            EventKind::TurnCompleted,
            EventKind::TaskCompleted,
            EventKind::TurnCompleted,
        ]
    );
    for task in [&events[0], &events[1], &events[3]] {
        assert!(task.task_awaited());
        assert_eq!(task.payload["taskId"], "child");
    }
    assert!(events[2].child_turns_continue());
    assert_eq!(events[2].failure_class(), FailureClass::Unknown);
    // Once the child ends, a later failure has nothing that continues.
    assert!(!events[4].child_turns_continue());
}

#[tokio::test]
async fn a_completed_root_turn_never_claims_continuing_children() {
    let events = observe(vec![
        child_spawned(),
        child_notification("turn/started"),
        json!({
            "method": "turn/completed",
            "params": { "threadId": "native", "turn": { "id": "root-turn", "status": "completed" } }
        }),
    ])
    .await;
    assert_eq!(events[2].kind, EventKind::TurnCompleted);
    assert!(events[2].payload.get("childTurnsContinue").is_none());
    assert!(events[2].payload.get("failureClass").is_none());
}

#[tokio::test]
async fn a_second_turn_while_one_runs_is_rejected_as_previous_turn_active() {
    let mut provider = CodexProvider::new(
        MockTransport::new([
            initialize_response(),
            thread_response(),
            json!({ "id": 3, "result": { "turn": { "id": "first" } } }),
        ]),
        CodexProviderConfig::default(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("app", "first"))
        .await
        .unwrap();
    let error = provider
        .send_turn(TurnInput::text("app", "second"))
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::Rejected { .. }));
    assert_eq!(error.failure_class(), FailureClass::PreviousTurnActive);
}

mod support;

use alera_provider_protocol::{EventKind, FailureClass, Provider, ProviderEvent, TurnInput};
use serde_json::{json, Value};
use support::*;

fn result(fields: Value) -> Value {
    let mut result = json!({
        "type": "result",
        "subtype": "success",
        "session_id": "native-session",
        "is_error": true,
        "num_turns": 1,
        "result": "Claude could not finish",
    });
    for (key, value) in fields.as_object().unwrap() {
        result[key] = value.clone();
    }
    result
}

fn rate_limit(status: &str) -> Value {
    json!({
        "type": "rate_limit_event",
        "uuid": "rate-1",
        "session_id": "native-session",
        "rate_limit_info": { "status": status, "rateLimitType": "five_hour", "utilization": 1.0 }
    })
}

fn assistant_error(error: &str) -> Value {
    json!({
        "type": "assistant",
        "session_id": "native-session",
        "error": error,
        "message": { "id": "msg-1", "model": "m", "content": [] }
    })
}

/// The turn's terminal event after `frames` play during one turn.
async fn terminal(frames: Vec<Value>) -> ProviderEvent {
    let mut incoming = vec![initialize_response()];
    incoming.extend(frames);
    let (mut provider, _handle) = started_provider(incoming).await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "run"))
        .await
        .unwrap();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::TurnCompleted {
            event.validate().unwrap();
            return event;
        }
    }
}

#[tokio::test]
async fn failed_results_are_classified_from_typed_claude_signals() {
    let cases = [
        (
            vec![result(json!({ "api_error_status": 429 }))],
            FailureClass::UsageLimit,
        ),
        (
            vec![
                rate_limit("rejected"),
                result(json!({ "terminal_reason": "api_error" })),
            ],
            FailureClass::UsageLimit,
        ),
        (
            vec![
                assistant_error("rate_limit"),
                result(json!({ "terminal_reason": "blocking_limit" })),
            ],
            FailureClass::UsageLimit,
        ),
        // A limit the CLI allowed again is no evidence.
        (
            vec![
                rate_limit("rejected"),
                rate_limit("allowed"),
                result(json!({ "terminal_reason": "api_error" })),
            ],
            FailureClass::Unknown,
        ),
        (
            vec![result(json!({ "terminal_reason": "prompt_too_long" }))],
            FailureClass::ContextWindowFull,
        ),
        (
            vec![
                assistant_error("authentication_failed"),
                result(json!({ "api_error_status": 401 })),
            ],
            FailureClass::Auth,
        ),
        // Signing in again cannot grant a 403.
        (
            vec![
                assistant_error("authentication_failed"),
                result(json!({ "api_error_status": 403 })),
            ],
            FailureClass::Unknown,
        ),
        (vec![result(json!({}))], FailureClass::Unknown),
    ];
    for (frames, class) in cases {
        let event = terminal(frames).await;
        assert_eq!(event.payload["state"], "failed");
        assert_eq!(event.failure_class(), class, "{}", event.payload);
        assert_eq!(event.payload["errorMessage"], "Claude could not finish");
    }
}

#[tokio::test]
async fn a_full_context_window_is_not_a_usage_limit() {
    // The CLI ends a turn with blocking_limit, without is_error, once the
    // context window is full.
    let event = terminal(vec![result(json!({
        "is_error": false,
        "terminal_reason": "blocking_limit",
        "result": "Prompt is too long",
    }))])
    .await;
    assert_eq!(event.payload["state"], "failed");
    assert_eq!(event.failure_class(), FailureClass::ContextWindowFull);
    assert_eq!(event.payload["errorMessage"], "Prompt is too long");
}

#[tokio::test]
async fn a_completed_result_carries_no_failure_class() {
    let event = terminal(vec![result_message(false, None)]).await;
    assert_eq!(event.payload["state"], "completed");
    assert!(event.payload.get("failureClass").is_none());
}

#[tokio::test]
async fn sub_agent_tasks_are_awaited_and_background_commands_are_not() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({"type":"system","subtype":"task_started","task_id":"agent","session_id":"native-session","tool_use_id":"tool","task_type":"local_agent","description":"Explore"}),
        json!({"type":"system","subtype":"task_started","task_id":"bash","session_id":"native-session","task_type":"local_bash","parent_task_id":"agent","description":"npm test"}),
        json!({"type":"system","subtype":"task_notification","task_id":"agent","session_id":"native-session","status":"completed"}),
    ])
    .await;
    let mut tasks = Vec::new();
    while tasks.len() < 3 {
        let event = provider.next_event().await.unwrap().unwrap();
        if matches!(
            event.kind,
            EventKind::TaskStarted | EventKind::TaskCompleted
        ) {
            event.validate().unwrap();
            tasks.push(event);
        }
    }
    assert!(tasks[0].task_awaited());
    assert!(tasks[0].payload.get("parentTaskId").is_none());
    assert!(!tasks[1].task_awaited());
    assert_eq!(tasks[1].payload["parentTaskId"], "agent");
    assert_eq!(tasks[2].kind, EventKind::TaskCompleted);
    assert!(tasks[2].payload.get("awaited").is_none());
}

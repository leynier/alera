mod support;

use alera_provider_protocol::{EventKind, Provider, ProviderEvent, TurnInput};
use serde_json::{json, Value};
use support::*;

async fn turn_events(frames: Vec<Value>) -> Vec<ProviderEvent> {
    let mut incoming = vec![initialize_response()];
    incoming.extend(frames);
    let (mut provider, _handle) = started_provider(incoming).await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "run"))
        .await
        .unwrap();
    let mut events = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        event.validate().unwrap();
        let done = matches!(
            event.kind,
            EventKind::TurnCompleted | EventKind::TurnAborted
        );
        events.push(event);
        if done {
            return events;
        }
    }
}

fn informational(content: &str, level: &str) -> Value {
    json!({
        "type": "system", "subtype": "informational", "session_id": "native-session",
        "content": content, "level": level, "prevent_continuation": true,
    })
}

fn retry(attempt: u64, status: Value) -> Value {
    json!({
        "type": "system", "subtype": "api_retry", "session_id": "native-session",
        "attempt": attempt, "max_retries": 10, "retry_delay_ms": 1500,
        "error_status": status, "error": "overloaded",
    })
}

#[tokio::test]
async fn a_hook_dropped_prompt_shows_its_reason_and_info_lines_stay_hidden() {
    let notice = "Prompt dropped by a hook: Deploys are frozen until Monday.";
    let mut result = result_message(false, None);
    result["num_turns"] = json!(0);
    result["result"] = json!(notice);
    let events = turn_events(vec![
        informational("Started in the background: agent-1", "info"),
        informational(notice, "warning"),
        informational("Context checkpoint", "notice"),
        informational("  ", "warning"),
        result,
    ])
    .await;
    let warnings = events
        .iter()
        .filter(|event| event.kind == EventKind::RuntimeWarning)
        .collect::<Vec<_>>();
    assert_eq!(warnings.len(), 2);
    assert_eq!(warnings[0].payload["message"], notice);
    assert_eq!(warnings[0].payload["preventContinuation"], true);
    assert_eq!(warnings[1].payload["message"], "Context checkpoint");
    assert!(!events
        .iter()
        .any(|event| event.kind == EventKind::ContentDelta));
    assert_eq!(events.last().unwrap().payload["state"], "completed");
}

#[tokio::test]
async fn api_retries_update_one_item_and_resolve_on_assistant_activity() {
    let events = turn_events(vec![
        retry(2, json!(529)),
        retry(3, json!(529)),
        json!({
            "type": "assistant", "session_id": "native-session",
            "message": { "id": "m", "model": "m", "content": [{ "type": "text", "text": "hi" }] }
        }),
        result_message(false, None),
    ])
    .await;
    let items = events
        .iter()
        .filter(|event| event.payload["itemType"] == "error")
        .collect::<Vec<_>>();
    assert_eq!(items.len(), 3);
    assert_eq!(items[0].kind, EventKind::ItemStarted);
    assert_eq!(items[0].item_id.as_deref(), Some("api-retry:turn:claude:1"));
    assert_eq!(items[0].payload["title"], "Provider retry");
    assert_eq!(items[0].payload["data"]["code"], "api_error_529");
    assert_eq!(
        items[0].payload["detail"],
        "Claude API overloaded. Retrying, attempt 2 of 10."
    );
    assert_eq!(items[1].kind, EventKind::ItemUpdated);
    assert_eq!(items[1].payload["data"]["attempt"], 3);
    assert_eq!(items[2].kind, EventKind::ItemCompleted);
    assert_eq!(items[2].payload["title"], "Provider recovered");
    let recovered = events
        .iter()
        .position(|event| event.payload["title"] == "Provider recovered");
    let reply = events
        .iter()
        .position(|event| event.kind == EventKind::ContentDelta);
    assert!(recovered < reply);
}

#[tokio::test]
async fn an_unrecovered_api_retry_settles_with_the_failed_turn() {
    let events = turn_events(vec![retry(1, Value::Null), result_message(true, None)]).await;
    let items = events
        .iter()
        .filter(|event| event.payload["itemType"] == "error")
        .collect::<Vec<_>>();
    assert_eq!(items[0].payload["data"]["code"], "overloaded");
    assert_eq!(items[1].payload["status"], "failed");
    assert_eq!(items[1].payload["title"], "Provider error");
    assert_eq!(events.last().unwrap().payload["state"], "failed");
}

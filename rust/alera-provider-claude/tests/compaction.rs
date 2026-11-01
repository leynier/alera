mod support;

use alera_provider_protocol::{EventKind, Provider, ProviderEvent, TurnInput};
use serde_json::{json, Value};
use support::*;

fn system(fields: Value) -> Value {
    let mut frame = json!({ "type": "system", "session_id": "native-session" });
    for (key, value) in fields.as_object().unwrap() {
        frame[key] = value.clone();
    }
    frame
}

/// The events of one turn running `prompt`, up to its terminal event.
async fn turn_events(frames: Vec<Value>, prompt: &str) -> Vec<ProviderEvent> {
    let mut incoming = vec![initialize_response()];
    incoming.extend(frames);
    let (mut provider, _handle) = started_provider(incoming).await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", prompt))
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

fn compactions(events: &[ProviderEvent]) -> Vec<&ProviderEvent> {
    events
        .iter()
        .filter(|event| event.payload["itemType"] == "context_compaction")
        .collect()
}

#[tokio::test]
async fn automatic_compaction_is_one_item_until_its_boundary() {
    let events = turn_events(
        vec![
            system(json!({ "subtype": "status", "status": "compacting", "uuid": "c-1" })),
            system(json!({ "subtype": "status", "status": "compacting", "uuid": "c-2" })),
            system(json!({ "subtype": "status", "status": null, "compact_result": "success", "uuid": "c-3" })),
            system(json!({
                "subtype": "compact_boundary", "uuid": "c-4",
                "compact_metadata": { "trigger": "auto", "pre_tokens": 1500, "post_tokens": 400 }
            })),
            result_message(false, None),
        ],
        "run",
    )
    .await;
    let items = compactions(&events);
    assert_eq!(items.len(), 3);
    assert_eq!(items[0].kind, EventKind::ItemStarted);
    assert_eq!(items[0].payload["status"], "inProgress");
    assert_eq!(items[0].payload["title"], "Compacting context");
    assert_eq!(items[0].payload["data"]["trigger"], "auto");
    for item in &items {
        assert_eq!(item.item_id.as_deref(), Some("compaction:c-1"));
    }
    assert_eq!(items[1].kind, EventKind::ItemCompleted);
    assert_eq!(items[1].payload["title"], "Context compacted");
    assert_eq!(items[2].payload["data"]["preTokens"], 1500);
    assert_eq!(items[2].payload["data"]["postTokens"], 400);
    assert_eq!(
        items[2].payload["data"]["completedAt"],
        items[1].payload["data"]["completedAt"]
    );
    assert!(events
        .iter()
        .any(|event| event.kind == EventKind::ThreadStateChanged));
    assert!(!events
        .iter()
        .any(|event| event.kind == EventKind::RuntimeWarning));
    let terminal = events.last().unwrap();
    assert_eq!(terminal.payload["state"], "completed");
}

#[tokio::test]
async fn a_boundary_without_status_is_a_completed_item() {
    let events = turn_events(
        vec![
            system(json!({
                "subtype": "compact_boundary", "uuid": "b-1",
                "compact_metadata": { "trigger": "manual", "pre_tokens": 900 }
            })),
            result_message(false, None),
        ],
        "run",
    )
    .await;
    let items = compactions(&events);
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].item_id.as_deref(), Some("compaction:b-1"));
    assert_eq!(items[0].payload["status"], "completed");
    assert_eq!(items[0].payload["data"]["trigger"], "manual");
    assert_eq!(items[0].payload["data"]["preTokens"], 900);
}

#[tokio::test]
async fn failed_and_stopped_compactions_settle_their_item() {
    let events = turn_events(
        vec![
            system(json!({ "subtype": "status", "status": "compacting", "uuid": "f-1" })),
            system(json!({
                "subtype": "status", "status": null, "compact_result": "failed",
                "compact_error": "Temporary compaction failure."
            })),
            system(json!({ "subtype": "status", "status": "compacting", "uuid": "s-1" })),
            system(json!({ "subtype": "status", "status": null, "permissionMode": "default" })),
            system(json!({ "subtype": "status", "status": null })),
            result_message(false, None),
        ],
        "run",
    )
    .await;
    let items = compactions(&events);
    assert_eq!(items.len(), 4);
    assert_eq!(items[1].payload["status"], "failed");
    assert_eq!(items[1].payload["title"], "Context compaction failed");
    assert_eq!(items[1].payload["detail"], "Temporary compaction failure.");
    assert_eq!(items[1].payload["data"]["outcome"], "failed");
    assert_eq!(items[3].item_id.as_deref(), Some("compaction:s-1"));
    assert_eq!(items[3].payload["title"], "Context compaction stopped");
    assert_eq!(items[3].payload["data"]["outcome"], "stopped");
}

#[tokio::test]
async fn an_unfinished_compaction_settles_before_the_terminal_event() {
    let compacting =
        || system(json!({ "subtype": "status", "status": "compacting", "uuid": "u-1" }));
    let events = turn_events(vec![compacting(), result_message(false, None)], "run").await;
    let settled = &events[events.len() - 2];
    assert_eq!(settled.payload["title"], "Context compaction failed");
    assert_eq!(settled.payload["detail"], "done");
    assert_eq!(events.last().unwrap().kind, EventKind::TurnCompleted);

    let events = turn_events(
        vec![
            compacting(),
            result_message(false, Some("aborted_streaming")),
        ],
        "run",
    )
    .await;
    let settled = &events[events.len() - 2];
    assert_eq!(settled.payload["title"], "Context compaction stopped");
    assert_eq!(events.last().unwrap().kind, EventKind::TurnAborted);
}

#[tokio::test]
async fn a_compact_command_echo_is_not_a_reply() {
    let events = turn_events(
        vec![
            system(json!({ "subtype": "status", "status": "compacting", "uuid": "m-1" })),
            system(json!({ "subtype": "status", "status": null, "compact_result": "success" })),
            json!({
                "type": "assistant",
                "session_id": "native-session",
                "local_command_source": "compact",
                "message": {
                    "id": "echo", "model": "<synthetic>",
                    "content": [{ "type": "text", "text": "Compacted." }]
                }
            }),
            result_message(false, None),
        ],
        "/compact",
    )
    .await;
    assert_eq!(compactions(&events)[0].payload["data"]["trigger"], "manual");
    assert!(!events
        .iter()
        .any(|event| event.kind == EventKind::ContentDelta));
}

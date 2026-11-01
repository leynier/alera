#[path = "support/goal.rs"]
mod goal_support;

use alera_provider_protocol::{EventKind, InterruptInput, Provider};
use goal_support::*;
use serde_json::{json, Value};

fn image(method: &str, id: &str, status: &str, saved: Option<&str>) -> Value {
    let mut item = json!({
        "type": "imageGeneration", "id": id, "status": status, "result": "aW1hZ2U=",
        "revisedPrompt": "A red fox",
    });
    if let Some(saved) = saved {
        item["savedPath"] = json!(saved);
    }
    notification(
        method,
        json!({ "threadId": "native", "turnId": "turn-1", "item": item }),
    )
}

#[tokio::test]
async fn a_turn_completes_after_its_images_render() {
    let mut provider = mock_session([
        image("item/started", "first", "inProgress", None),
        image("item/started", "second", "generating", None),
        agent_message("turn-1", "Here they are"),
        turn_completed("turn-1", "completed"),
        image(
            "item/completed",
            "first",
            "completed",
            Some("/tmp/first.png"),
        ),
        image(
            "item/completed",
            "second",
            "inProgress",
            Some("/tmp/second.png"),
        ),
    ])
    .await;
    let events = drain(&mut provider).await;
    let kinds = events
        .iter()
        .map(|event| event.kind.clone())
        .collect::<Vec<_>>();
    assert_eq!(
        kinds,
        [
            EventKind::ItemStarted,
            EventKind::ItemStarted,
            EventKind::ItemCompleted,
            EventKind::ItemCompleted,
            EventKind::ItemCompleted,
            EventKind::TurnCompleted,
        ]
    );
    for event in &events {
        assert!(
            !event.payload.to_string().contains("aW1hZ2U="),
            "{}",
            event.payload
        );
    }
    let first = &events[3];
    assert_eq!(first.payload["itemType"], "image_generation");
    assert_eq!(first.payload["status"], "completed");
    assert_eq!(first.payload["data"]["savedPath"], "/tmp/first.png");
    assert_eq!(first.payload["detail"], "A red fox");
    // An unknown native status still reads as running, then completes.
    assert_eq!(events[1].payload["status"], "inProgress");
    assert_eq!(events[4].payload["status"], "completed");
}

#[tokio::test]
async fn failed_images_and_interrupted_turns_are_not_held() {
    let mut failed = image("item/completed", "first", "failed", None);
    failed["params"]["item"]["failure"] = json!({ "type": "usageLimitExceeded" });
    let mut provider = mock_session([
        image("item/started", "first", "inProgress", None),
        turn_completed("turn-1", "interrupted"),
        failed,
    ])
    .await;
    let events = drain(&mut provider).await;
    assert_eq!(events[1].kind, EventKind::TurnCompleted);
    assert_eq!(events[2].payload["status"], "failed");
}

#[tokio::test]
async fn the_stream_end_releases_a_held_completion() {
    let mut provider = mock_session([
        image("item/started", "first", "inProgress", None),
        turn_completed("turn-1", "completed"),
    ])
    .await;
    let events = drain(&mut provider).await;
    assert_eq!(events.last().unwrap().kind, EventKind::TurnCompleted);
}

#[tokio::test]
async fn a_stop_releases_a_held_completion_without_interrupting_codex() {
    let (mut provider, feed) = channel_session().await;
    feed.push(turn_started("turn-1"));
    feed.push(image("item/started", "first", "inProgress", None));
    feed.push(turn_completed("turn-1", "completed"));
    let mut seen = Vec::new();
    while let Ok(Ok(Some(event))) =
        tokio::time::timeout(std::time::Duration::from_millis(50), provider.next_event()).await
    {
        seen.push(event.kind);
    }
    assert!(!seen.contains(&EventKind::TurnCompleted));
    provider
        .interrupt(InterruptInput {
            thread_id: "app".into(),
            turn_id: Some("turn-1".into()),
        })
        .await
        .unwrap();
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["state"], "completed");
    assert!(!feed
        .requests()
        .iter()
        .any(|(method, _)| method == "turn/interrupt"));
}

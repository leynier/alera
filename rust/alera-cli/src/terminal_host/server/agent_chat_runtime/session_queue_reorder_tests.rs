use std::time::Duration;

use serde_json::Value;

use super::super::commands::{CallerCtx, ChatOp};
use super::super::AgentChatRuntime;
use super::fixture::*;
use crate::terminal_host::host_error::HostError;

async fn queue_three(
    runtime: &AgentChatRuntime,
    factory: &RecordingFactory,
) -> (String, Vec<String>) {
    let chat = create(runtime, None).await;
    send(runtime, &chat, "running", "Running prompt").await;
    let control = provider_control(factory, &chat).await;
    tokio::time::timeout(Duration::from_secs(5), control.wait_turns(1))
        .await
        .unwrap();
    let mut ids = Vec::new();
    for name in ["a", "b", "c"] {
        let queued = send(runtime, &chat, name, name).await;
        assert_eq!(queued["delivery"], "queued");
        ids.push(queued["queueId"].as_str().unwrap().to_owned());
    }
    (chat, ids)
}

async fn reorder(
    runtime: &AgentChatRuntime,
    chat: &str,
    queue_id: &str,
    index: usize,
) -> Result<Value, HostError> {
    runtime
        .command(
            chat,
            ChatOp::QueueReorder {
                queue_id: queue_id.to_owned(),
                index,
            },
            CallerCtx::runtime(),
            None,
        )
        .await
}

fn queue_texts(snapshot: &Value) -> Vec<String> {
    snapshot["queue"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["text"].as_str().unwrap().to_owned())
        .collect()
}

#[tokio::test]
async fn reorder_moves_one_entry_and_the_order_survives_a_restart() {
    let (harness, runtime, factory) = fixture().await;
    let (chat, ids) = queue_three(&runtime, &factory).await;

    let moved = reorder(&runtime, &chat, &ids[2], 0).await.unwrap();
    assert_eq!(moved["reordered"], true);
    assert_eq!(moved["index"], 0);
    assert_eq!(
        queue_texts(&runtime.snapshot(&chat).await.unwrap()),
        ["c", "a", "b"]
    );

    // An index past the end lands on the last slot.
    let clamped = reorder(&runtime, &chat, &ids[2], 99).await.unwrap();
    assert_eq!(clamped["index"], 2);
    assert_eq!(
        queue_texts(&runtime.snapshot(&chat).await.unwrap()),
        ["a", "b", "c"]
    );

    let unchanged = reorder(&runtime, &chat, &ids[1], 1).await.unwrap();
    assert_eq!(unchanged["reordered"], false);

    reorder(&runtime, &chat, &ids[0], 1).await.unwrap();
    runtime.shutdown().await;
    assert_eq!(
        queue_texts(&runtime.snapshot(&chat).await.unwrap()),
        ["b", "a", "c"]
    );
    harness.finish().await;
}

#[tokio::test]
async fn reorder_of_an_entry_that_left_the_queue_is_a_conflict() {
    let (harness, runtime, factory) = fixture().await;
    let (chat, ids) = queue_three(&runtime, &factory).await;
    runtime
        .command(
            &chat,
            ChatOp::QueueCancel {
                queue_id: ids[1].clone(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    match reorder(&runtime, &chat, &ids[1], 0).await {
        Err(HostError::Conflict { code, .. }) => assert_eq!(code, "queueNotFound"),
        other => panic!("expected queueNotFound, got {other:?}"),
    }
    assert_eq!(
        queue_texts(&runtime.snapshot(&chat).await.unwrap()),
        ["a", "c"]
    );
    runtime.shutdown().await;
    harness.finish().await;
}

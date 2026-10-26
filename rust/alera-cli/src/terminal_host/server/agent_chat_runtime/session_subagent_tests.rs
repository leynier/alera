use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp};
use super::super::AgentChatRuntime;
use super::fixture::*;

async fn item_where(
    runtime: &AgentChatRuntime,
    chat: &str,
    test: impl Fn(&Value) -> bool,
) -> Value {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    loop {
        let snapshot = runtime.snapshot(chat).await.unwrap();
        if let Some(item) = snapshot["items"]
            .as_array()
            .unwrap()
            .iter()
            .find(|item| test(item))
        {
            return item.clone();
        }
        assert!(
            std::time::Instant::now() < deadline,
            "no matching item in {:#}",
            snapshot["items"]
        );
        tokio::time::sleep(std::time::Duration::from_millis(5)).await;
    }
}

#[tokio::test]
async fn a_subagent_reads_as_its_own_transcript_and_stops_on_its_own() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.item_event(
        EventKind::ItemStarted,
        1,
        "call-1",
        json!({"itemType": "collab_agent_tool_call", "status": "inProgress"}),
    );
    control.event(
        EventKind::TaskStarted,
        1,
        json!({
            "taskId": "task-1", "description": "Count files", "model": "gpt-6-luna",
            "reasoningEffort": "high", "nativeTask": {"nativeToolCallId": "call-1"},
        }),
    );
    control.item_event(
        EventKind::ItemCompleted,
        1,
        "child-answer",
        json!({
            "itemType": "assistant_message", "data": {"text": "42 files"},
            "parentToolUseId": "call-1",
        }),
    );
    let call = item_where(&runtime, &chat, |item| {
        item["normalized"]["subagent"]["model"] == "gpt-6-luna"
    })
    .await;
    let call_id = call["itemId"].as_str().unwrap().to_owned();
    assert_eq!(call["normalized"]["subagent"]["status"], "running");
    assert_eq!(call["normalized"]["subagent"]["reasoningEffort"], "high");
    assert!(call["normalized"]["subagent"]["startedAt"].is_string());
    control.complete(1, "Spawned it");
    // A sub-agent that reports after its parent's turn stays in that turn.
    send(&runtime, &chat, "second", "Anything else?").await;
    control.wait_turns(2).await;
    control.item_event(
        EventKind::ItemCompleted,
        2,
        "late-child",
        json!({
            "itemType": "assistant_message", "data": {"text": "late"},
            "parentToolUseId": "call-1",
        }),
    );
    let late = item_where(&runtime, &chat, |item| item["text"] == "late").await;
    assert_eq!(late["turnId"], call["turnId"]);

    let transcript = runtime
        .command(
            &chat,
            ChatOp::SubagentTranscript {
                item_id: call_id.clone(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(transcript["call"]["itemId"], call_id.as_str());
    let texts: Vec<_> = transcript["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|item| item["text"].as_str().unwrap_or_default().to_owned())
        .collect();
    assert_eq!(texts, ["42 files", "late"]);
    assert_eq!(transcript["truncated"], false);

    let stopped = runtime
        .command(
            &chat,
            ChatOp::StopSubagent {
                item_id: call_id.clone(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(stopped["stopped"], true);
    assert_eq!(*control.stopped_subagents.lock().unwrap(), ["task-1"]);
    let settled = item_where(&runtime, &chat, |item| {
        item["itemId"] == call_id.as_str() && item["normalized"]["subagent"]["status"] == "stopped"
    })
    .await;
    assert!(settled["normalized"]["subagent"]["completedAt"].is_string());
    let again = runtime
        .command(
            &chat,
            ChatOp::StopSubagent { item_id: call_id },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap_err();
    assert!(format!("{again:?}").contains("subagentNotRunning"));
    // An ordinary item is not a sub-agent.
    let answer = late["itemId"].as_str().unwrap().to_owned();
    let refused = runtime
        .command(
            &chat,
            ChatOp::SubagentTranscript { item_id: answer },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap_err();
    assert!(format!("{refused:?}").contains("notSubagent"));
    finish_turn(&runtime, &factory, &chat, 2).await;
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_fork_merges_back_into_its_source_for_the_next_turn() {
    let (harness, runtime, factory) = fixture().await;
    let source = create(&runtime, None).await;
    let first = send(&runtime, &source, "first", "Plan the cache").await;
    let control = provider_control(&factory, &source).await;
    control.wait_turns(1).await;
    finish_turn(&runtime, &factory, &source, 1).await;
    let refused = runtime
        .merge_back(&source, CallerCtx::runtime(), None)
        .await
        .unwrap_err();
    assert!(format!("{refused:?}").contains("notFork"));
    let forked = runtime
        .fork(
            &source,
            first["turnId"].as_str().unwrap(),
            Some("Cache experiment".into()),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let fork = forked["chatId"].as_str().unwrap().to_owned();
    let listed = runtime.list(Some("ws-a"), false).await.unwrap();
    let summary = listed
        .iter()
        .find(|chat| chat["chatId"] == fork.as_str())
        .unwrap();
    assert_eq!(summary["forkedFromChatId"], source.as_str());
    let empty = runtime
        .merge_back(&fork, CallerCtx::runtime(), None)
        .await
        .unwrap_err();
    assert!(format!("{empty:?}").contains("nothingToMerge"));
    send(&runtime, &fork, "fork-first", "Try an LRU cache").await;
    let fork_control = provider_control(&factory, &fork).await;
    fork_control.wait_turns(1).await;
    finish_turn(&runtime, &factory, &fork, 1).await;

    let merged = runtime
        .merge_back(&fork, CallerCtx::runtime(), None)
        .await
        .unwrap();
    assert_eq!(merged["chatId"], source.as_str());
    let notice = item_where(&runtime, &source, |item| {
        item["normalized"]["mergeBack"]["status"] == "pending"
    })
    .await;
    assert_eq!(notice["title"], "Merged back from Cache experiment");
    assert_eq!(
        notice["normalized"]["mergeBack"]["fromChatId"],
        fork.as_str()
    );
    // Merging does not start a turn in the source.
    assert_eq!(control.turns.lock().unwrap().len(), 1);

    send(&runtime, &source, "second", "Which one wins?").await;
    control.wait_turns(2).await;
    let input = control.turns.lock().unwrap()[1].input.clone();
    assert!(input.starts_with("Work merged back from forks of this conversation."));
    assert!(input.contains("> > User: Try an LRU cache"));
    assert!(!input.contains("Plan the cache"));
    assert!(input.ends_with("New message:\nWhich one wins?"));
    item_where(&runtime, &source, |item| {
        item["normalized"]["mergeBack"]["status"] == "delivered"
    })
    .await;
    finish_turn(&runtime, &factory, &source, 2).await;
    send(&runtime, &source, "third", "Thanks").await;
    control.wait_turns(3).await;
    assert_eq!(control.turns.lock().unwrap()[2].input, "Thanks");
    finish_turn(&runtime, &factory, &source, 3).await;
    runtime.shutdown().await;
    harness.finish().await;
}

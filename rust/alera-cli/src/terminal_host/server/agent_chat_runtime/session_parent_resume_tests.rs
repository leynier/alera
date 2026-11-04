use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::AgentChatRuntime;
use super::background_work::{idle_with, wait_for_session};
use super::fixture::*;
use crate::terminal_host::server::chat_orchestration::mock_provider::MockProviderControl;

/// Returns once the session applied every event sent before, by sending a
/// token count it can observe.
async fn settle(
    runtime: &AgentChatRuntime,
    control: &MockProviderControl,
    chat: &str,
    marker: u64,
) {
    control.event(
        EventKind::ThreadTokenUsageUpdated,
        1,
        json!({"inputTokens": marker}),
    );
    tokio::time::timeout(std::time::Duration::from_secs(5), async {
        while runtime.snapshot(chat).await.unwrap()["usage"]["tokens"]["input"] != marker {
            tokio::time::sleep(std::time::Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
}

fn child_started(control: &MockProviderControl, task: &str) {
    control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": task, "awaited": true}),
    );
}

fn child_finished(control: &MockProviderControl, task: &str, status: &str, summary: &str) {
    control.event(
        EventKind::TaskCompleted,
        1,
        json!({
            "taskId": task, "status": status, "description": format!("Count {task}"),
            "summary": summary, "wakesParent": true,
        }),
    );
}

fn turn_inputs(factory: &RecordingFactory) -> Vec<String> {
    let turns = factory.recorded.turns.lock().unwrap();
    turns.iter().map(|turn| turn.input.clone()).collect()
}

#[tokio::test]
async fn a_child_that_finishes_after_its_parent_turn_resumes_the_parent() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    child_started(&control, "files");
    control.complete(1, "The helper is counting");
    wait_for_session(&runtime, &chat, idle_with("running")).await;

    child_finished(&control, "files", "completed", "42 files");
    control.wait_turns(2).await;
    assert_eq!(
        turn_inputs(&factory)[1],
        "Subagent completed: Count files\n\nResult:\n42 files"
    );
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    let wake = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .rfind(|item| item["type"] == "user_message")
        .unwrap();
    assert_eq!(
        wake["normalized"]["origin"],
        json!({"kind": "subagentWake", "taskIds": ["files"]})
    );
    assert_eq!(wake["actor"], "runtime");
    finish_turn(&runtime, &factory, &chat, 2).await;
    wait_for_session(&runtime, &chat, idle_with("ready")).await;
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn children_finishing_together_resume_the_parent_once() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn two helpers").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    child_started(&control, "a");
    child_started(&control, "b");
    control.complete(1, "Both are running");
    wait_for_session(&runtime, &chat, idle_with("running")).await;
    child_finished(&control, "a", "failed", "a broke");
    child_finished(&control, "b", "completed", "b done");
    control.wait_turns(2).await;
    // The second result reaches the running resume turn natively.
    wait_for_session(&runtime, &chat, |session: &Value| {
        !session["activeTurnId"].is_null()
    })
    .await;
    assert!(turn_inputs(&factory)[1].starts_with("Subagent failed: Count a"));
    finish_turn(&runtime, &factory, &chat, 2).await;
    wait_for_session(&runtime, &chat, idle_with("ready")).await;
    assert_eq!(factory.recorded.turns.lock().unwrap().len(), 2);
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_running_turn_receives_the_result_without_another_turn() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    child_started(&control, "files");
    control.complete(1, "The helper is counting");
    send(&runtime, &chat, "second", "Anything new?").await;
    control.wait_turns(2).await;
    let queued = send(&runtime, &chat, "third", "And then this").await;
    assert_eq!(queued["delivery"], "queued");
    child_finished(&control, "files", "completed", "42 files");
    control.complete(2, "Nothing yet");
    control.wait_turns(3).await;
    finish_turn(&runtime, &factory, &chat, 3).await;
    wait_for_session(&runtime, &chat, idle_with("ready")).await;
    assert_eq!(
        turn_inputs(&factory),
        ["Spawn a helper", "Anything new?", "And then this"]
    );
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn children_of_a_turn_that_did_not_complete_never_resume_it() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    child_started(&control, "continuing");
    control.event(
        EventKind::TurnCompleted,
        1,
        json!({"state": "failed", "childTurnsContinue": true}),
    );
    wait_for_session(&runtime, &chat, idle_with("running")).await;
    child_finished(&control, "continuing", "completed", "done anyway");
    wait_for_session(&runtime, &chat, idle_with("ready")).await;

    send(&runtime, &chat, "second", "Spawn another").await;
    control.wait_turns(2).await;
    control.event(
        EventKind::TaskStarted,
        2,
        json!({"taskId": "stopped", "awaited": true}),
    );
    control.event(EventKind::TurnAborted, 2, json!({"reason": "interrupted"}));
    wait_for_session(&runtime, &chat, idle_with("ready")).await;
    control.event(
        EventKind::TaskCompleted,
        2,
        json!({"taskId": "stopped", "status": "completed", "wakesParent": true}),
    );
    settle(&runtime, &control, &chat, 7).await;
    // Neither wakes the parent; a later message is the next turn.
    send(&runtime, &chat, "third", "Next").await;
    control.wait_turns(3).await;
    assert_eq!(
        turn_inputs(&factory),
        ["Spawn a helper", "Spawn another", "Next"]
    );
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn children_that_report_back_natively_never_resume_the_parent() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    child_started(&control, "agent");
    control.complete(1, "The helper runs");
    wait_for_session(&runtime, &chat, idle_with("running")).await;
    control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "agent", "status": "completed"}),
    );
    wait_for_session(&runtime, &chat, idle_with("ready")).await;
    send(&runtime, &chat, "second", "Next").await;
    control.wait_turns(2).await;
    assert_eq!(turn_inputs(&factory), ["Spawn a helper", "Next"]);
    runtime.shutdown().await;
    harness.finish().await;
}

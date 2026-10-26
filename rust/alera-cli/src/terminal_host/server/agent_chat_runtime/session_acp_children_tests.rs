//! ACP native child sessions as the runtime sees them: task events keyed by
//! the Agent call, child items under it, and the turn the agent starts on
//! its own once the children end.

use std::time::Duration;

use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::AgentChatRuntime;
use super::fixture::*;

/// The native turn the agent starts by itself; mock sends number from 1.
const AGENT_TURN: usize = 9;

async fn wait_for(runtime: &AgentChatRuntime, chat: &str, test: impl Fn(&Value) -> bool) -> Value {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = runtime.snapshot(chat).await.unwrap();
            if test(&snapshot) {
                break snapshot;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("the chat did not reach the expected state")
}

fn item(snapshot: &Value, test: impl Fn(&Value) -> bool) -> Option<&Value> {
    snapshot["items"].as_array()?.iter().find(|item| test(item))
}

fn task(status: &str) -> Value {
    json!({
        "taskId": "agent-1", "status": status, "description": "Review",
        "childSessionId": "child-1",
        "nativeTask": {
            "nativeTaskId": "child-1", "nativeToolCallId": "agent-1",
            "childNativeThreadIds": ["child-1"],
        },
    })
}

fn agent_started() -> Value {
    json!({"agentStarted": {"origin": "backgroundContinuation"}})
}

#[tokio::test]
async fn a_child_session_settles_its_call_and_the_agents_own_turn_is_adopted() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Review the code").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.item_event(
        EventKind::ItemUpdated,
        1,
        "agent-1",
        json!({"itemType": "dynamic_tool_call", "status": "inProgress", "title": "Review"}),
    );
    let mut started = task("running");
    started["awaited"] = json!(true);
    control.event(EventKind::TaskStarted, 1, started);
    control.item_event(
        EventKind::ContentDelta,
        1,
        "child-1/early",
        json!({"streamKind": "assistant_text", "delta": "Reading.", "parentToolUseId": "agent-1"}),
    );
    control.complete(1, "The review is running.");
    // The child still works, so the chat does too.
    let snapshot = wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"]["activeTurnId"].is_null()
            && item(snapshot, |item| {
                item["normalized"]["parentItemId"].is_string()
            })
            .is_some()
    })
    .await;
    assert_eq!(snapshot["session"]["status"], "running");
    let call = item(&snapshot, |item| item["normalized"]["subagent"].is_object()).unwrap();
    assert_eq!(call["normalized"]["subagent"]["status"], "running");
    assert_eq!(call["normalized"]["subagent"]["taskId"], "agent-1");
    let child = item(&snapshot, |item| {
        item["normalized"]["parentItemId"].is_string()
    })
    .unwrap();
    assert_eq!(child["normalized"]["parentItemId"], call["itemId"]);

    let mut completed = task("completed");
    completed["summary"] = json!("Found the regression.");
    control.event(EventKind::TaskCompleted, 1, completed);
    let snapshot = wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"]["status"] == "ready"
    })
    .await;
    let call = item(&snapshot, |item| item["normalized"]["subagent"].is_object()).unwrap();
    assert_eq!(call["normalized"]["subagent"]["status"], "completed");
    assert_eq!(
        call["normalized"]["subagent"]["summary"],
        "Found the regression."
    );

    // Claude resumes itself: its turn runs with no user message.
    control.event(EventKind::TurnStarted, AGENT_TURN, agent_started());
    let snapshot = wait_for(&runtime, &chat, |snapshot| {
        !snapshot["session"]["activeTurnId"].is_null()
    })
    .await;
    let turns = snapshot["turns"].as_array().unwrap();
    assert_eq!(turns.len(), 2);
    assert_eq!(turns[1]["origin"], "backgroundContinuation");
    assert_eq!(turns[1]["status"], "running");
    assert_eq!(snapshot["session"]["activeTurnId"], turns[1]["turnId"]);
    let adopted = turns[1]["turnId"].clone();
    control.complete(AGENT_TURN, "Fixed it.");
    let snapshot = wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"]["activeTurnId"].is_null()
    })
    .await;
    assert_eq!(snapshot["session"]["status"], "ready");
    let answer = item(&snapshot, |item| item["text"] == "Fixed it.").unwrap();
    assert_eq!(answer["turnId"], adopted);
    assert!(item(&snapshot, |item| {
        item["itemType"] == "user_message" && item["turnId"] == adopted
    })
    .is_none());
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn an_agent_started_turn_never_replaces_a_running_one() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Work").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    let before = runtime.snapshot(&chat).await.unwrap();
    control.event(EventKind::TurnStarted, AGENT_TURN, agent_started());
    control.complete(1, "Done");
    let snapshot = wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"]["activeTurnId"].is_null()
    })
    .await;
    let turns = snapshot["turns"].as_array().unwrap();
    assert_eq!(turns.len(), 1);
    assert_eq!(turns[0]["turnId"], before["session"]["activeTurnId"]);
    assert!(turns[0]["origin"].is_null());
    runtime.shutdown().await;
    harness.finish().await;
}

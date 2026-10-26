use std::time::Duration;

use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::AgentChatRuntime;
use super::fixture::*;
use crate::terminal_host::server::chat_orchestration::mock_provider::MockProviderControl;

/// The native turn Codex starts on its own; mock sends number theirs from 1.
const CODEX_TURN: usize = 7;

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

fn goal_event(control: &MockProviderControl, status: &str) {
    control.event(
        EventKind::SessionGoalUpdated,
        1,
        json!({"goal": {"objective": "Ship the parser", "status": status, "tokensUsed": 1200}}),
    );
}

fn advertise_goal(control: &MockProviderControl) {
    control.event(
        EventKind::SessionCommandsUpdated,
        1,
        json!({"commands": [{"name": "compact"}, {"name": "goal"}]}),
    );
}

/// Ends native turn [turn] with Codex already in [next].
fn continue_goal(control: &MockProviderControl, turn: usize, next: usize) {
    control.event(
        EventKind::TurnCompleted,
        turn,
        json!({"state": "completed", "goalContinuation": {"nextTurnId": format!("native-turn-{next}")}}),
    );
    control.event(
        EventKind::TurnStarted,
        next,
        json!({"goalContinuation": true}),
    );
}

fn goal_turn(snapshot: &Value) -> Option<&Value> {
    snapshot["turns"]
        .as_array()?
        .iter()
        .find(|turn| turn["origin"] == "goalContinuation")
}

fn running_goal_turn(snapshot: &Value) -> bool {
    goal_turn(snapshot).is_some_and(|turn| snapshot["session"]["activeTurnId"] == turn["turnId"])
}

/// A chat whose first turn runs with an active goal.
async fn goal_chat() -> (
    crate::terminal_host::server::chat_orchestration::test_support::TestHarness,
    AgentChatRuntime,
    std::sync::Arc<RecordingFactory>,
    String,
    std::sync::Arc<MockProviderControl>,
) {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "/goal Ship the parser").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    advertise_goal(&control);
    goal_event(&control, "active");
    wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"]["goal"]["status"] == "active"
    })
    .await;
    (harness, runtime, factory, chat, control)
}

#[tokio::test]
async fn the_goal_reaches_the_snapshot_and_a_null_update_clears_it() {
    let (harness, runtime, _factory, chat, control) = goal_chat().await;
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(
        snapshot["session"]["goal"],
        json!({"objective": "Ship the parser", "status": "active", "tokensUsed": 1200})
    );
    let stored = harness.store.agent_chat(&chat).await.unwrap().unwrap();
    assert_eq!(stored.snapshot["session"]["goal"]["status"], "active");
    control.event(EventKind::SessionGoalUpdated, 1, json!({"goal": null}));
    wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"].get("goal").is_none()
    })
    .await;
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_turn_codex_starts_for_the_goal_is_adopted_as_the_running_turn() {
    let (harness, runtime, factory, chat, control) = goal_chat().await;
    control.item_event(
        EventKind::ItemCompleted,
        1,
        "answer-1",
        json!({"itemType": "assistant_message", "data": {"text": "First step"}}),
    );
    continue_goal(&control, 1, CODEX_TURN);
    let snapshot = wait_for(&runtime, &chat, running_goal_turn).await;
    let turns = snapshot["turns"].as_array().unwrap();
    assert_eq!(turns.len(), 2);
    assert_eq!(turns[0]["status"], "completed");
    assert_eq!(turns[1]["status"], "running");
    assert_eq!(turns[1]["model"], "verified-model");
    assert_eq!(snapshot["session"]["status"], "running");
    let goal_turn_id = turns[1]["turnId"].clone();

    // Its items join it, and it has no user message of its own.
    control.item_event(
        EventKind::ItemCompleted,
        CODEX_TURN,
        "answer-7",
        json!({"itemType": "assistant_message", "data": {"text": "Second step"}}),
    );
    control.complete(CODEX_TURN, "Done for now");
    let snapshot = wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"]["activeTurnId"].is_null()
    })
    .await;
    assert_eq!(snapshot["session"]["status"], "ready");
    let items = snapshot["items"].as_array().unwrap();
    let of_goal_turn: Vec<&Value> = items
        .iter()
        .filter(|item| item["turnId"] == goal_turn_id)
        .collect();
    assert!(of_goal_turn
        .iter()
        .any(|item| item["text"] == "Second step"));
    assert!(of_goal_turn
        .iter()
        .all(|item| item["type"] != "user_message"));
    assert_eq!(factory.recorded.turns.lock().unwrap().len(), 1);
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn queued_messages_wait_out_the_goal_run_instead_of_racing_it() {
    let (harness, runtime, factory, chat, control) = goal_chat().await;
    let queued = send(&runtime, &chat, "later", "Also update the docs").await;
    assert_eq!(queued["delivery"], "queued");
    continue_goal(&control, 1, CODEX_TURN);
    wait_for(&runtime, &chat, running_goal_turn).await;
    // A send while the adopted turn runs queues behind it too.
    let queued = send(&runtime, &chat, "later-2", "And the changelog").await;
    assert_eq!(queued["delivery"], "queued");
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(snapshot["queue"].as_array().unwrap().len(), 2);
    assert_eq!(factory.recorded.turns.lock().unwrap().len(), 1);

    control.complete(CODEX_TURN, "Goal paused");
    control.wait_turns(2).await;
    let inputs: Vec<String> = factory
        .recorded
        .turns
        .lock()
        .unwrap()
        .iter()
        .map(|turn| turn.input.clone())
        .collect();
    assert_eq!(inputs[1], "Also update the docs");
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn stop_reaches_the_adopted_turn() {
    let (harness, runtime, _factory, chat, control) = goal_chat().await;
    continue_goal(&control, 1, CODEX_TURN);
    let snapshot = wait_for(&runtime, &chat, running_goal_turn).await;
    let goal_turn_id = snapshot["session"]["activeTurnId"].clone();
    runtime
        .command(
            &chat,
            super::super::commands::ChatOp::Interrupt { turn_id: None },
            super::super::commands::CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let interrupts = control.interrupts.lock().unwrap().clone();
    assert_eq!(interrupts.len(), 1);
    assert_eq!(
        interrupts[0].turn_id.as_deref(),
        Some(format!("native-turn-{CODEX_TURN}").as_str())
    );
    let snapshot = wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"]["activeTurnId"].is_null()
    })
    .await;
    let turn = snapshot["turns"]
        .as_array()
        .unwrap()
        .iter()
        .find(|turn| turn["turnId"] == goal_turn_id)
        .unwrap();
    assert_eq!(turn["status"], "interrupted");
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_goal_command_that_changes_goal_work_stops_the_turn_and_goes_first() {
    let (harness, runtime, factory, chat, control) = goal_chat().await;
    send(&runtime, &chat, "earlier", "Also update the docs").await;
    let show = send(&runtime, &chat, "show", "/goal").await;
    assert_eq!(show["delivery"], "queued");
    assert!(control.interrupts.lock().unwrap().is_empty());

    let pause = send(&runtime, &chat, "pause", "/goal pause").await;
    assert_eq!(pause["delivery"], "queued");
    control.wait_turns(2).await;
    assert_eq!(control.interrupts.lock().unwrap().len(), 1);
    let inputs: Vec<String> = factory
        .recorded
        .turns
        .lock()
        .unwrap()
        .iter()
        .map(|turn| turn.input.clone())
        .collect();
    assert_eq!(inputs[1], "/goal pause");
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    let queued: Vec<&str> = snapshot["queue"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|entry| entry["text"].as_str())
        .collect();
    assert_eq!(queued, ["Also update the docs", "/goal"]);
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_child_finishing_during_the_goal_run_does_not_start_a_wake_turn() {
    let (harness, runtime, factory, chat, control) = goal_chat().await;
    control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": "helper", "awaited": true}),
    );
    continue_goal(&control, 1, CODEX_TURN);
    wait_for(&runtime, &chat, running_goal_turn).await;
    control.event(
        EventKind::TaskCompleted,
        CODEX_TURN,
        json!({"taskId": "helper", "status": "completed", "summary": "done", "wakesParent": true}),
    );
    control.complete(CODEX_TURN, "Goal complete");
    wait_for(&runtime, &chat, |snapshot| {
        snapshot["session"]["activeTurnId"].is_null()
    })
    .await;
    assert_eq!(factory.recorded.turns.lock().unwrap().len(), 1);
    runtime.shutdown().await;
    harness.finish().await;
}

use std::sync::atomic::Ordering;

use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp};
use super::super::AgentChatRuntime;
use super::background_work::{idle_with, wait_for_session};
use super::fixture::*;

async fn command(runtime: &AgentChatRuntime, chat: &str, op: ChatOp) -> Value {
    runtime
        .command(chat, op, CallerCtx::runtime(), None)
        .await
        .unwrap()
}

fn subagent_call(snapshot: &Value, call: &str) -> Value {
    snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["normalized"]["subagent"]["taskId"] == call)
        .map(|item| item["normalized"]["subagent"].clone())
        .unwrap_or(Value::Null)
}

/// Starts a sub-agent under the call `call` of native turn `turn`.
fn start_subagent(control: &MockControl, turn: usize, call: &str, task: &str, awaited: bool) {
    control.item_event(
        EventKind::ItemStarted,
        turn,
        call,
        json!({"itemType": "collab_agent_tool_call", "status": "inProgress"}),
    );
    control.event(
        EventKind::TaskStarted,
        turn,
        json!({"taskId": task, "awaited": awaited, "nativeTask": {"nativeToolCallId": call}}),
    );
}

type MockControl =
    crate::terminal_host::server::chat_orchestration::mock_provider::MockProviderControl;

#[tokio::test]
async fn a_steer_into_a_stopping_turn_waits_in_the_queue() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    let started = send(&runtime, &chat, "first", "Long task").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    let queued = send(&runtime, &chat, "queued", "Queued before the stop").await;
    factory
        .recorded
        .hold_interrupt
        .store(true, Ordering::SeqCst);
    let stopped = command(&runtime, &chat, ChatOp::Interrupt { turn_id: None }).await;
    assert_eq!(stopped["interrupted"], true);

    // Promoting into the stopping turn fails and keeps the message queued.
    let error = runtime
        .command(
            &chat,
            ChatOp::QueuePromoteToSteer {
                queue_id: queued["queueId"].as_str().unwrap().to_owned(),
                turn_id: started["turnId"].as_str().unwrap().to_owned(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap_err();
    assert_eq!(error.wire_response(1)["errorCode"], "turnStopping");
    // A plain steer queues behind it instead of reaching a turn that stops.
    let mut steer = input("steer", "Steered after the stop");
    steer.delivery = "steer".into();
    let steered = runtime
        .send(&chat, steer, CallerCtx::runtime())
        .await
        .unwrap();
    assert_eq!(steered["delivery"], "queued");
    assert!(factory.recorded.steers.lock().unwrap().is_empty());
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    let texts: Vec<&str> = snapshot["queue"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["text"].as_str().unwrap())
        .collect();
    assert_eq!(texts, ["Queued before the stop", "Steered after the stop"]);

    // Both run once the provider ends the stopped turn.
    control.event(EventKind::TurnAborted, 1, json!({"reason": "interrupted"}));
    control.wait_turns(2).await;
    assert_eq!(
        control.turns.lock().unwrap()[1].input,
        "Queued before the stop"
    );
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn stop_with_no_turn_running_ends_the_background_work_earlier_turns_left() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    *control.background_tasks.lock().unwrap() = Some(vec!["server".into()]);
    control.wait_turns(1).await;
    start_subagent(&control, 1, "call-1", "helper", true);
    control.event(EventKind::TaskStarted, 1, json!({"taskId": "server"}));
    command(
        &runtime,
        &chat,
        ChatOp::AwaitBackgroundTasks {
            task_ids: vec!["server".into()],
            awaited: true,
        },
    )
    .await;
    control.event(EventKind::TurnCompleted, 1, json!({"state": "completed"}));
    wait_for_session(&runtime, &chat, idle_with("running")).await;
    assert_eq!(
        runtime.snapshot(&chat).await.unwrap()["backgroundSubagentsRunning"],
        true
    );

    let stopped = command(&runtime, &chat, ChatOp::Interrupt { turn_id: None }).await;
    assert_eq!(stopped["interrupted"], true);
    wait_for_session(&runtime, &chat, idle_with("ready")).await;
    let mut asked = control.stopped_subagents.lock().unwrap().clone();
    asked.sort();
    assert_eq!(asked, ["helper", "server"]);
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(snapshot["backgroundSubagentsRunning"], false);
    assert_eq!(subagent_call(&snapshot, "helper")["status"], "stopped");
    // The stopped child's end does not start the parent again.
    control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "helper", "status": "completed", "wakesParent": true}),
    );
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    let again = command(&runtime, &chat, ChatOp::Interrupt { turn_id: None }).await;
    assert_eq!(again["interrupted"], false);
    assert_eq!(control.turns.lock().unwrap().len(), 1);
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_plain_subagent_settles_when_its_provider_stops() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    // Neither awaited nor a workflow: nothing but the process reports on it.
    start_subagent(&control, 1, "call-1", "helper", false);
    finish_turn(&runtime, &factory, &chat, 1).await;
    let running = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(subagent_call(&running, "helper")["status"], "running");

    command(&runtime, &chat, ChatOp::Stop).await;
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    let subagent = subagent_call(&snapshot, "helper");
    assert_eq!(subagent["status"], "stopped");
    assert!(subagent["completedAt"].is_string());
    runtime.shutdown().await;
    harness.finish().await;
}

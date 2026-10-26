use std::time::Duration;

use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::AgentChatRuntime;
use super::fixture::*;

async fn wait_for_session(runtime: &AgentChatRuntime, chat: &str, test: impl Fn(&Value) -> bool) {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = runtime.snapshot(chat).await.unwrap();
            if test(&snapshot["session"]) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap_or_else(|_| {
        panic!("session did not reach the expected state");
    });
}

fn idle_with(status: &'static str) -> impl Fn(&Value) -> bool {
    move |session| session["activeTurnId"].is_null() && session["status"] == status
}

#[tokio::test]
async fn awaited_child_work_keeps_the_chat_working_and_background_commands_do_not() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": "agent", "awaited": true}),
    );
    control.event(EventKind::TaskStarted, 1, json!({"taskId": "dev-server"}));
    control.event(EventKind::TurnCompleted, 1, json!({"state": "completed"}));
    wait_for_session(&runtime, &chat, idle_with("running")).await;

    // A late progress event never registers work again.
    control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "dev-server", "status": "completed"}),
    );
    control.event(
        EventKind::TaskProgress,
        1,
        json!({"taskId": "dev-server", "awaited": true}),
    );
    control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "agent", "status": "completed"}),
    );
    wait_for_session(&runtime, &chat, idle_with("ready")).await;
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_failed_turn_ends_its_awaited_work_unless_its_children_continue() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Spawn a helper").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": "agent-1", "awaited": true}),
    );
    control.event(EventKind::TurnCompleted, 1, json!({"state": "failed"}));
    wait_for_session(&runtime, &chat, idle_with("ready")).await;

    send(&runtime, &chat, "second", "Spawn another helper").await;
    control.wait_turns(2).await;
    control.event(
        EventKind::TaskStarted,
        2,
        json!({"taskId": "agent-2", "awaited": true}),
    );
    let queued = send(&runtime, &chat, "third", "Then this").await;
    assert_eq!(queued["delivery"], "queued");
    control.event(
        EventKind::TurnCompleted,
        2,
        json!({"state": "failed", "childTurnsContinue": true}),
    );
    // The queued message does not wait behind the child that continues.
    wait_until(|| factory.recorded.turns.lock().unwrap().len() == 3).await;
    assert_eq!(factory.recorded.turns.lock().unwrap()[2].input, "Then this");
    finish_turn(&runtime, &factory, &chat, 3).await;
    wait_for_session(&runtime, &chat, idle_with("running")).await;
    control.event(
        EventKind::TaskCompleted,
        2,
        json!({"taskId": "agent-2", "status": "completed"}),
    );
    wait_for_session(&runtime, &chat, idle_with("ready")).await;
    runtime.shutdown().await;
    harness.finish().await;
}

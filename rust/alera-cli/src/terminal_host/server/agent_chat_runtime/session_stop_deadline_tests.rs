//! Stop always answers, an agent that ignores it can be force stopped, and a
//! steer skips a running `/compact`.

use std::sync::atomic::Ordering;
use std::time::Duration;

use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp};
use super::super::session_stop::StopTiming;
use super::super::AgentChatRuntime;
use super::fixture::*;

fn quick() -> StopTiming {
    StopTiming {
        interrupt: Duration::from_millis(50),
        control: Duration::from_millis(50),
        unresponsive: Duration::from_millis(300),
    }
}

async fn command(runtime: &AgentChatRuntime, chat: &str, op: ChatOp) -> Value {
    runtime
        .command(chat, op, CallerCtx::runtime(), None)
        .await
        .unwrap()
}

fn turn(snapshot: &Value, turn_id: &str) -> Value {
    snapshot["turns"]
        .as_array()
        .unwrap()
        .iter()
        .find(|turn| turn["turnId"] == turn_id)
        .cloned()
        .unwrap_or(Value::Null)
}

async fn wait_for_snapshot(runtime: &AgentChatRuntime, chat: &str, test: impl Fn(&Value) -> bool) {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if test(&runtime.snapshot(chat).await.unwrap()) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the snapshot never matched");
}

#[tokio::test]
async fn a_stop_the_provider_never_answers_turns_unresponsive_and_force_stop_ends_the_turn() {
    let (harness, runtime, factory) = fixture_timed(quick()).await;
    let chat = create(&runtime, None).await;
    let started = send(&runtime, &chat, "first", "Long task").await;
    let turn_id = started["turnId"].as_str().unwrap().to_owned();
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    let queued = send(&runtime, &chat, "queued", "Queued behind it").await;
    assert_eq!(queued["delivery"], "queued");
    factory
        .recorded
        .hang_interrupt
        .store(true, Ordering::SeqCst);

    // The interrupt never answers, yet Stop does, and the turn reads stopping.
    let stopped = tokio::time::timeout(
        Duration::from_secs(2),
        runtime.command(
            &chat,
            ChatOp::Interrupt { turn_id: None },
            CallerCtx::runtime(),
            None,
        ),
    )
    .await
    .expect("Stop waited on the provider")
    .unwrap();
    assert_eq!(stopped["interrupted"], true);
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(snapshot["session"]["stop"]["turnId"], turn_id.as_str());
    assert!(snapshot["session"]["stop"]["requestedAt"].is_string());
    assert!(snapshot["session"]["stop"].get("unresponsiveAt").is_none());
    assert_eq!(snapshot["session"]["activeTurnId"], turn_id.as_str());

    // The actor keeps serving while the deadline runs, then marks it.
    wait_for_snapshot(&runtime, &chat, |snapshot| {
        snapshot["session"]["stop"]["unresponsiveAt"].is_string()
    })
    .await;

    let forced = command(
        &runtime,
        &chat,
        ChatOp::ForceStop {
            turn_id: Some(turn_id.clone()),
        },
    )
    .await;
    assert_eq!(forced["forceStopped"], true);
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    assert!(snapshot["session"].get("activeTurnId").is_none());
    assert!(snapshot["session"].get("stop").is_none());
    assert_eq!(snapshot["session"]["status"], "stopped");
    assert_eq!(snapshot["queue"], json!([]));
    let ended = turn(&snapshot, &turn_id);
    assert_eq!(ended["status"], "interrupted");
    assert_eq!(ended["reason"], "forceStopped");
    assert_eq!(ended["errorMessage"], "Force stopped by user");
    assert_eq!(snapshot["recovery"]["canResume"], true);

    // A second Force stop has nothing left to stop.
    let again = command(&runtime, &chat, ChatOp::ForceStop { turn_id: None }).await;
    assert_eq!(again["forceStopped"], false);

    // The chat resumes its native session with the next message.
    factory
        .recorded
        .hang_interrupt
        .store(false, Ordering::SeqCst);
    send(&runtime, &chat, "next", "Carry on").await;
    let restarted = factory.inner.control_after(&chat, &control).await;
    restarted.wait_turns(1).await;
    let starts = factory.recorded.starts.lock().unwrap().clone();
    assert_eq!(starts.len(), 2);
    assert!(starts[1].resume_thread_id.is_some());
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_force_stop_of_a_turn_that_is_no_longer_running_is_refused() {
    let (harness, runtime, factory) = fixture_timed(quick()).await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Long task").await;
    provider_control(&factory, &chat).await.wait_turns(1).await;
    let error = runtime
        .command(
            &chat,
            ChatOp::ForceStop {
                turn_id: Some("turn-gone".into()),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap_err();
    assert_eq!(error.wire_response(1)["errorCode"], "turnNotActive");
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_steer_the_provider_never_answers_fails_in_time() {
    let (harness, runtime, factory) = fixture_timed(quick()).await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Long task").await;
    provider_control(&factory, &chat).await.wait_turns(1).await;
    factory.recorded.hang_steer.store(true, Ordering::SeqCst);
    let mut steer = input("steer", "Steered");
    steer.delivery = "steer".into();
    let error = tokio::time::timeout(
        Duration::from_secs(2),
        runtime.send(&chat, steer, CallerCtx::runtime()),
    )
    .await
    .expect("the steer waited on the provider")
    .unwrap_err();
    assert_eq!(error.wire_response(1)["errorCode"], "providerTimeout");
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_steer_during_compact_goes_first_and_skips_the_compaction() {
    let (harness, runtime, factory) = fixture_timed(quick()).await;
    let chat = create(&runtime, None).await;
    let started = send(&runtime, &chat, "compact", "/compact").await;
    let turn_id = started["turnId"].as_str().unwrap().to_owned();
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    assert_eq!(
        send(&runtime, &chat, "waiting", "Queued earlier").await["delivery"],
        "queued"
    );
    let mut steer = input("steer", "Do this now");
    steer.delivery = "steer".into();
    let steered = runtime
        .send(&chat, steer, CallerCtx::runtime())
        .await
        .unwrap();
    assert_eq!(steered["delivery"], "queued");
    assert!(factory.recorded.steers.lock().unwrap().is_empty());
    assert_eq!(control.interrupts.lock().unwrap().len(), 1);

    // The compaction ends with the notice and the steer runs first.
    control.wait_turns(2).await;
    assert_eq!(control.turns.lock().unwrap()[1].input, "Do this now");
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    let skipped = turn(&snapshot, &turn_id);
    assert_eq!(skipped["status"], "interrupted");
    assert_eq!(skipped["reason"], "compactionSkipped");
    assert_eq!(
        skipped["errorMessage"],
        "Skipped compaction to send a queued message"
    );
    let texts: Vec<&str> = snapshot["queue"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["text"].as_str().unwrap())
        .collect();
    assert_eq!(texts, ["Queued earlier"]);
    control.event(EventKind::TurnCompleted, 2, json!({"state": "completed"}));
    runtime.shutdown().await;
    harness.finish().await;
}

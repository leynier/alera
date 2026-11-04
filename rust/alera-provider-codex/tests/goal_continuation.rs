//! Turns Codex starts on its own while a goal is active: continued inside
//! the grace window, paused when it ends, stopped when no run owns them.

#[path = "support/goal.rs"]
mod goal_support;

use alera_provider_protocol::{EventKind, InterruptInput, Provider, ProviderEvent, TurnInput};
use goal_support::*;
use serde_json::json;

async fn next(provider: &mut impl Provider) -> ProviderEvent {
    provider.next_event().await.unwrap().unwrap()
}

/// A session whose goal Codex reports active, with Alera's turn running.
async fn active_goal_turn() -> (
    alera_provider_codex::CodexProvider<ChannelTransport>,
    ChannelFeed,
) {
    let (mut provider, feed) = channel_session().await;
    feed.push(goal_updated("Ship", "active"));
    let update = next(&mut provider).await;
    assert_eq!(update.kind, EventKind::SessionGoalUpdated);
    feed.push(response(3, json!({ "turn": { "id": "turn-1" } })));
    feed.push(turn_started("turn-1"));
    provider
        .send_turn(TurnInput::text("app", "work"))
        .await
        .unwrap();
    assert_eq!(next(&mut provider).await.kind, EventKind::TurnStarted);
    (provider, feed)
}

#[tokio::test(start_paused = true)]
async fn codex_turns_continue_the_run_until_the_grace_window_ends() {
    let (mut provider, feed) = active_goal_turn().await;
    feed.push(turn_completed("turn-1", "completed"));
    feed.push(turn_started("turn-2"));
    let completed = next(&mut provider).await;
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(
        completed.payload["goalContinuation"],
        json!({ "nextTurnId": "turn-2" })
    );
    let started = next(&mut provider).await;
    assert_eq!(started.turn_id.as_deref(), Some("turn-2"));
    assert_eq!(started.payload["goalContinuation"], true);
    assert_eq!(
        provider.session().unwrap().active_turn_id.as_deref(),
        Some("turn-2")
    );

    // Codex does not continue after turn-2: the goal pauses, then it settles.
    feed.push(turn_completed("turn-2", "completed"));
    let before = tokio::time::Instant::now();
    let update = next(&mut provider).await;
    assert!(before.elapsed() >= std::time::Duration::from_secs(5));
    assert_eq!(update.kind, EventKind::SessionGoalUpdated);
    assert_eq!(update.payload["goal"]["status"], "paused");
    let settled = next(&mut provider).await;
    assert_eq!(settled.kind, EventKind::TurnCompleted);
    assert_eq!(settled.turn_id.as_deref(), Some("turn-2"));
    assert_eq!(settled.payload["state"], "completed");
    assert_eq!(settled.payload.get("goalContinuation"), None);
    assert_eq!(
        feed.requests().last().unwrap(),
        &(
            "thread/goal/set".to_owned(),
            json!({ "threadId": "native", "status": "paused" })
        )
    );

    // The pause's answer is dropped rather than read as unsolicited, and a
    // turn Codex starts before it lands has no run, so it is stopped.
    feed.push(goal_response(4, "Ship", "paused"));
    feed.push(turn_started("turn-3"));
    feed.push(agent_message("turn-3", "orphan"));
    feed.push(turn_completed("turn-3", "interrupted"));
    feed.push(goal_updated("Ship", "paused"));
    let quiet =
        tokio::time::timeout(std::time::Duration::from_secs(30), provider.next_event()).await;
    assert!(
        quiet.is_err(),
        "the orphan turn and a repeated goal stay unseen"
    );
    assert_eq!(
        feed.requests().last().unwrap(),
        &(
            "turn/interrupt".to_owned(),
            json!({ "threadId": "native", "turnId": "turn-3" })
        )
    );
}

#[tokio::test(start_paused = true)]
async fn a_goal_that_stops_being_active_settles_the_held_turn_at_once() {
    let (mut provider, feed) = active_goal_turn().await;
    feed.push(turn_completed("turn-1", "completed"));
    feed.push(goal_updated("Ship", "complete"));
    let before = tokio::time::Instant::now();
    let update = next(&mut provider).await;
    assert_eq!(update.payload["goal"]["status"], "complete");
    let settled = next(&mut provider).await;
    assert_eq!(settled.kind, EventKind::TurnCompleted);
    assert_eq!(settled.payload.get("goalContinuation"), None);
    assert!(before.elapsed() < std::time::Duration::from_secs(1));
    assert_eq!(feed.requests().len(), 1, "only the turn/start");
}

#[tokio::test(start_paused = true)]
async fn a_codex_turn_with_no_run_is_paused_and_stopped_unseen() {
    let (mut provider, feed) = channel_session().await;
    feed.push(goal_updated("Ship", "active"));
    assert_eq!(
        next(&mut provider).await.kind,
        EventKind::SessionGoalUpdated
    );
    feed.push(turn_started("orphan"));
    feed.push(agent_message("orphan", "working alone"));
    feed.push(turn_completed("orphan", "interrupted"));
    feed.push(goal_updated("Ship", "paused"));
    let update = next(&mut provider).await;
    assert_eq!(update.kind, EventKind::SessionGoalUpdated);
    assert_eq!(update.payload["goal"]["status"], "paused");
    let methods: Vec<String> = feed
        .requests()
        .into_iter()
        .map(|(method, _)| method)
        .collect();
    assert_eq!(methods, ["thread/goal/set", "turn/interrupt"]);
    assert_eq!(
        feed.requests()[1].1,
        json!({ "threadId": "native", "turnId": "orphan" })
    );
    assert_eq!(provider.session().unwrap().active_turn_id, None);
    // Nothing of the orphan turn surfaces, and the confirming update
    // repeats what was already announced.
    let quiet =
        tokio::time::timeout(std::time::Duration::from_secs(30), provider.next_event()).await;
    assert!(quiet.is_err());
}

#[tokio::test(start_paused = true)]
async fn stop_pauses_the_goal_and_settles_a_held_turn_as_interrupted() {
    let (mut provider, feed) = active_goal_turn().await;
    feed.push(turn_completed("turn-1", "completed"));
    // Drives the read that holds turn-1, then gives up before the window ends.
    let held = tokio::time::timeout(std::time::Duration::from_secs(1), provider.next_event()).await;
    assert!(held.is_err());
    feed.push(goal_response(4, "Ship", "paused"));
    provider
        .interrupt(InterruptInput {
            thread_id: "app".into(),
            turn_id: Some("turn-1".into()),
        })
        .await
        .unwrap();
    let methods: Vec<String> = feed
        .requests()
        .into_iter()
        .map(|(method, _)| method)
        .collect();
    assert_eq!(methods, ["turn/start", "thread/goal/set"]);
    let update = next(&mut provider).await;
    assert_eq!(update.payload["goal"]["status"], "paused");
    let settled = next(&mut provider).await;
    assert_eq!(settled.kind, EventKind::TurnCompleted);
    assert_eq!(settled.payload["state"], "interrupted");
}

#[tokio::test(start_paused = true)]
async fn stop_during_a_goal_turn_pauses_then_interrupts_the_newest_turn() {
    let (mut provider, feed) = active_goal_turn().await;
    feed.push(turn_completed("turn-1", "completed"));
    feed.push(turn_started("turn-2"));
    next(&mut provider).await;
    next(&mut provider).await;
    feed.push(goal_response(4, "Ship", "paused"));
    feed.push(response(5, json!({})));
    provider
        .interrupt(InterruptInput {
            thread_id: "app".into(),
            turn_id: Some("turn-1".into()),
        })
        .await
        .unwrap();
    let requests = feed.requests();
    assert_eq!(requests[1].1["status"], "paused");
    assert_eq!(
        requests[2],
        (
            "turn/interrupt".to_owned(),
            json!({ "threadId": "native", "turnId": "turn-2" })
        )
    );
}

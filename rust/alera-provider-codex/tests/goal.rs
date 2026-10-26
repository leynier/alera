//! `/goal` commands over Codex's `thread/goal/*`, as T3 Code runs them.

#[path = "support/goal.rs"]
mod goal_support;

use alera_provider_protocol::{EventKind, Provider, ProviderError, SessionStatus, TurnInput};
use goal_support::*;
use serde_json::{json, Value};

fn reply_text(events: &[alera_provider_protocol::ProviderEvent]) -> Option<String> {
    events
        .iter()
        .find(|event| event.kind == EventKind::ItemCompleted)
        .and_then(|event| event.payload["data"]["text"].as_str().map(str::to_owned))
}

fn goal_updates(events: &[alera_provider_protocol::ProviderEvent]) -> Vec<Value> {
    events
        .iter()
        .filter(|event| event.kind == EventKind::SessionGoalUpdated)
        .map(|event| event.payload["goal"].clone())
        .collect()
}

#[tokio::test]
async fn show_replies_with_the_goal_in_a_turn_that_never_reaches_codex() {
    let mut provider = mock_session([goal_response(3, "Ship the parser", "budgetLimited")]).await;
    let result = provider
        .send_turn(TurnInput::text("app", "/goal"))
        .await
        .unwrap();
    assert_eq!(result.turn_id, "goal-command:1");
    assert_eq!(
        requests(provider.transport().writes()),
        [(
            "thread/goal/get".to_owned(),
            json!({ "threadId": "native" })
        )]
    );
    let events = drain(&mut provider).await;
    let kinds: Vec<_> = events.iter().map(|event| event.kind.clone()).collect();
    assert_eq!(
        kinds,
        [
            EventKind::SessionGoalUpdated,
            EventKind::TurnStarted,
            EventKind::ItemCompleted,
            EventKind::TurnCompleted,
        ]
    );
    assert!(events[1..]
        .iter()
        .all(|event| event.turn_id.as_deref() == Some("goal-command:1")));
    assert_eq!(
        reply_text(&events).as_deref(),
        Some("Goal budget limited: Ship the parser")
    );
    assert_eq!(
        goal_updates(&events),
        [json!({
            "objective": "Ship the parser", "status": "budget_limited",
            "tokensUsed": 1200, "timeUsedSeconds": 90,
        })]
    );
    assert_eq!(events[3].payload["state"], "completed");
    let session = provider.session().unwrap();
    assert_eq!(session.status, SessionStatus::Ready);
    assert_eq!(session.active_turn_id, None);
}

#[tokio::test]
async fn show_pause_and_resume_without_a_goal_say_so() {
    for text in ["/goal edit", "/goal pause", "/goal RESUME"] {
        let mut provider = mock_session([response(3, json!({ "goal": null }))]).await;
        provider
            .send_turn(TurnInput::text("app", text))
            .await
            .unwrap();
        assert_eq!(requests(provider.transport().writes()).len(), 1, "{text}");
        let events = drain(&mut provider).await;
        assert_eq!(reply_text(&events).as_deref(), Some("No goal is set."));
        // The first read is announced, so a goal the host kept is cleared.
        assert_eq!(goal_updates(&events), [Value::Null]);
    }
}

#[tokio::test]
async fn clear_answers_through_the_goal_and_only_says_when_none_was_set() {
    let mut provider = mock_session([
        goal_response(3, "Ship", "active"),
        response(4, json!({ "cleared": true })),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("app", "/goal clear"))
        .await
        .unwrap();
    assert_eq!(
        requests(provider.transport().writes())[1],
        (
            "thread/goal/clear".to_owned(),
            json!({ "threadId": "native" })
        )
    );
    let events = drain(&mut provider).await;
    assert_eq!(reply_text(&events), None);
    // Read as active, then cleared; only the result is announced.
    assert_eq!(goal_updates(&events), [Value::Null]);

    let mut provider = mock_session([
        response(3, json!({})),
        response(4, json!({ "cleared": false })),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("app", "/goal clear"))
        .await
        .unwrap();
    let events = drain(&mut provider).await;
    assert_eq!(reply_text(&events).as_deref(), Some("No goal is set."));
}

#[tokio::test]
async fn pause_sets_the_goal_paused_without_a_reply() {
    let mut provider = mock_session([
        goal_response(3, "Ship", "active"),
        goal_response(4, "Ship", "paused"),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("app", "/goal pause"))
        .await
        .unwrap();
    assert_eq!(
        requests(provider.transport().writes())[1],
        (
            "thread/goal/set".to_owned(),
            json!({ "threadId": "native", "status": "paused" })
        )
    );
    let events = drain(&mut provider).await;
    assert_eq!(reply_text(&events), None);
    let updates = goal_updates(&events);
    assert_eq!(updates.len(), 1);
    assert_eq!(updates[0]["status"], "paused");
}

#[tokio::test]
async fn set_replaces_the_goal_paused_then_activates_after_its_first_turn_starts() {
    let mut provider = mock_session([
        goal_response(3, "Old", "paused"),
        response(4, json!({ "cleared": true })),
        notification("thread/goal/cleared", json!({ "threadId": "native" })),
        goal_response(5, "Ship the parser", "paused"),
        response(6, json!({ "turn": { "id": "turn-1" } })),
        turn_started("turn-1"),
        goal_updated("Ship the parser", "active"),
        goal_response(7, "Ship the parser", "active"),
    ])
    .await;
    let result = provider
        .send_turn(TurnInput::text("app", "/goal  Ship the parser "))
        .await
        .unwrap();
    assert_eq!(result.turn_id, "turn-1");
    let requests = requests(provider.transport().writes());
    let methods: Vec<&str> = requests.iter().map(|(method, _)| method.as_str()).collect();
    assert_eq!(
        methods,
        [
            "thread/goal/get",
            "thread/goal/clear",
            "thread/goal/set",
            "turn/start",
            "thread/goal/set",
        ]
    );
    assert_eq!(
        requests[2].1,
        json!({ "threadId": "native", "objective": "Ship the parser", "status": "paused" })
    );
    assert_eq!(
        requests[3].1["input"],
        json!([{ "type": "text", "text": "Start working toward this goal: Ship the parser" }])
    );
    assert_eq!(
        requests[4].1,
        json!({ "threadId": "native", "status": "active" })
    );
    let session = provider.session().unwrap();
    assert_eq!(session.status, SessionStatus::Running);
    assert_eq!(session.active_turn_id.as_deref(), Some("turn-1"));
    let events = drain(&mut provider).await;
    let updates = goal_updates(&events);
    assert_eq!(updates.len(), 1, "intermediate states stay unannounced");
    assert_eq!(updates[0]["objective"], "Ship the parser");
    assert_eq!(updates[0]["status"], "active");
    let started = events
        .iter()
        .find(|event| event.kind == EventKind::TurnStarted)
        .unwrap();
    assert_eq!(started.payload.get("goalContinuation"), None);
}

#[tokio::test]
async fn resume_starts_an_empty_goal_turn_with_this_turns_configuration() {
    let mut provider = mock_session([
        goal_response(3, "Ship", "paused"),
        response(4, json!({ "turn": { "id": "turn-1" } })),
        goal_response(5, "Ship", "active"),
    ])
    .await;
    let mut input = TurnInput::text("app", "/goal resume");
    input.model = Some("gpt-5".into());
    input.interaction_mode = alera_provider_protocol::InteractionMode::Plan;
    provider.send_turn(input).await.unwrap();
    let requests = requests(provider.transport().writes());
    assert_eq!(requests[1].0, "turn/start");
    assert_eq!(requests[1].1["input"], json!([]));
    assert_eq!(requests[1].1["model"], "gpt-5");
    assert_eq!(requests[1].1["collaborationMode"]["mode"], "plan");
    assert_eq!(requests[2].1["status"], "active");
}

#[tokio::test]
async fn a_first_turn_that_completes_during_activation_is_held_for_the_goal() {
    let mut provider = mock_session([
        response(3, json!({})),
        goal_response(4, "Ship", "paused"),
        response(5, json!({ "turn": { "id": "turn-1" } })),
        turn_started("turn-1"),
        agent_message("turn-1", "Started."),
        turn_completed("turn-1", "completed"),
        goal_response(6, "Ship", "active"),
        turn_started("turn-2"),
        turn_completed("turn-2", "interrupted"),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("app", "/goal Ship"))
        .await
        .unwrap();
    let events = drain(&mut provider).await;
    let kinds: Vec<_> = events.iter().map(|event| event.kind.clone()).collect();
    assert_eq!(
        kinds,
        [
            EventKind::TurnStarted,
            EventKind::ItemCompleted,
            EventKind::SessionGoalUpdated,
            EventKind::TurnCompleted,
            EventKind::TurnStarted,
            EventKind::TurnCompleted,
        ]
    );
    assert_eq!(events[3].turn_id.as_deref(), Some("turn-1"));
    assert_eq!(
        events[3].payload["goalContinuation"],
        json!({ "nextTurnId": "turn-2" })
    );
    assert_eq!(events[4].turn_id.as_deref(), Some("turn-2"));
    assert_eq!(events[4].payload["goalContinuation"], true);
    assert_eq!(events[5].payload.get("goalContinuation"), None);
}

#[tokio::test]
async fn stop_during_activation_leaves_the_goal_paused() {
    let mut provider = mock_session([
        response(3, json!({})),
        goal_response(4, "Ship", "paused"),
        response(5, json!({ "turn": { "id": "turn-1" } })),
        turn_started("turn-1"),
        turn_completed("turn-1", "interrupted"),
        goal_response(6, "Ship", "active"),
        goal_response(7, "Ship", "paused"),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("app", "/goal Ship"))
        .await
        .unwrap();
    let requests = requests(provider.transport().writes());
    assert_eq!(requests.len(), 5);
    assert_eq!(requests[3].1["status"], "active");
    assert_eq!(requests[4].1["status"], "paused");
    let events = drain(&mut provider).await;
    let completed = events
        .iter()
        .find(|event| event.kind == EventKind::TurnCompleted)
        .unwrap();
    assert_eq!(completed.payload["state"], "interrupted");
    assert_eq!(goal_updates(&events).last().unwrap()["status"], "paused");
}

#[tokio::test]
async fn a_stop_that_lands_before_activation_never_activates() {
    let mut provider = mock_session([
        response(3, json!({})),
        goal_response(4, "Ship", "paused"),
        turn_started("turn-1"),
        notification(
            "turn/aborted",
            json!({ "threadId": "native", "turnId": "turn-1", "reason": "interrupted" }),
        ),
        response(5, json!({ "turn": { "id": "turn-1" } })),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("app", "/goal Ship"))
        .await
        .unwrap();
    let methods: Vec<String> = requests(provider.transport().writes())
        .into_iter()
        .map(|(method, _)| method)
        .collect();
    assert_eq!(
        methods,
        ["thread/goal/get", "thread/goal/set", "turn/start"]
    );
}

#[tokio::test]
async fn an_app_server_without_goals_drops_the_command() {
    let mut provider = mock_session([json!({
        "id": 3, "error": { "code": -32601, "message": "unknown method thread/goal/get" }
    })])
    .await;
    provider
        .send_turn(TurnInput::text("app", "/goal Ship"))
        .await
        .unwrap();
    let events = drain(&mut provider).await;
    let commands = events
        .iter()
        .find(|event| event.kind == EventKind::SessionCommandsUpdated)
        .unwrap();
    let names: Vec<&str> = commands.payload["commands"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|command| command["name"].as_str())
        .collect();
    assert_eq!(names, ["compact", "feedback"]);
    assert_eq!(
        reply_text(&events).as_deref(),
        Some("This Codex version does not support goals.")
    );
}

#[tokio::test]
async fn a_goal_command_cannot_steer_a_running_turn() {
    let mut provider = mock_session([response(3, json!({ "turn": { "id": "turn-1" } }))]).await;
    provider
        .send_turn(TurnInput::text("app", "work"))
        .await
        .unwrap();
    let error = provider
        .steer_turn(TurnInput::text("app", "/goal pause"), "turn-1")
        .await
        .unwrap_err();
    assert!(
        matches!(error, ProviderError::Unsupported(message) if message.starts_with("Goal commands must run as a separate turn"))
    );
}

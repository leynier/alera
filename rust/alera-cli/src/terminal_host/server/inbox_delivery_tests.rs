use serde_json::json;

use super::inbox_test_fixture::*;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::coordinator_loop::{CoordinatorConfig, CoordinatorHandle};

fn set_presence(fixture: &mut Fixture, handle: &str, agent: &str, state: AgentPresenceState) {
    if matches!(agent, "claude" | "codex") {
        super::orchestration_message_delivery::QUEUED_INPUT_AGENTS_FOR_TESTS
            .with(|agents| agents.borrow_mut().push(agent.to_string()));
    }
    fixture
        .actor
        .agent_presence
        .update(handle, agent.to_string(), state);
}

#[tokio::test]
async fn a_now_question_is_pasted_into_a_working_agent_that_queues_input() {
    let mut fixture = fixture().await;
    set_presence(
        &mut fixture,
        "claude-term",
        "claude",
        AgentPresenceState::Working,
    );

    let pasted = fixture
        .actor
        .sessions
        .get_mut("claude-term")
        .unwrap()
        .attach_test_input();
    let asked = fixture
        .ok(
            PHONE,
            "inbox.ask",
            json!({"to": "claude-term", "body": "Still on track?", "delivery": "now"}),
        )
        .await;

    assert_eq!(asked["deliveryMode"], "pasted_now", "{asked}");
    assert_eq!(asked["message"]["delivery"], "now");
    assert!(fixture
        .actor
        .orchestration_delivery_in_flight
        .contains("claude-term"));
    let write = pasted
        .recv_timeout(std::time::Duration::from_secs(5))
        .unwrap();
    let text = String::from_utf8_lossy(&write.bytes);
    assert!(
        text.contains("[Alera] Question from ext:user via Alera mobile"),
        "{text}"
    );
    assert!(text.contains("Still on track?"), "{text}");
    let thread = fixture
        .ok(
            PHONE,
            "inbox.thread",
            json!({"threadId": asked["threadId"]}),
        )
        .await;
    assert_eq!(thread["thread"]["deliveryMode"], "pasted_now", "{thread}");
    assert_eq!(thread["messages"][0]["delivery"], "now");
    assert_eq!(thread["messages"][0]["deliveryMode"], "pasted_now");
}

#[tokio::test]
async fn a_now_question_waits_for_the_turn_of_an_agent_that_does_not_queue_input() {
    let mut fixture = fixture().await;
    set_presence(
        &mut fixture,
        "shell-term",
        "copilot",
        AgentPresenceState::Working,
    );

    let asked = fixture
        .ok(
            PHONE,
            "inbox.ask",
            json!({"to": "shell-term", "body": "Still on track?"}),
        )
        .await;

    assert_eq!(asked["deliveryMode"], "queued_at_turn_end", "{asked}");
    assert_eq!(asked["recipient"]["acceptsQueuedInput"], false);
    assert!(!fixture
        .actor
        .orchestration_delivery_in_flight
        .contains("shell-term"));
}

#[tokio::test]
async fn a_turn_end_question_is_never_pasted_mid_turn() {
    let mut fixture = fixture().await;
    set_presence(
        &mut fixture,
        "claude-term",
        "claude",
        AgentPresenceState::Working,
    );

    let asked = fixture
        .ok(
            PHONE,
            "inbox.ask",
            json!({"to": "claude-term", "body": "Later is fine", "delivery": "turnEnd"}),
        )
        .await;

    assert_eq!(asked["deliveryMode"], "queued_at_turn_end", "{asked}");
    assert_eq!(asked["message"]["delivery"], "turnEnd");
    let refused = fixture
        .request(
            PHONE,
            "inbox.ask",
            json!({"to": "claude-term", "body": "?", "delivery": "soon"}),
        )
        .await;
    assert_eq!(refused["ok"], false, "{refused}");
}

#[tokio::test]
async fn targets_report_what_a_now_question_would_do() {
    let mut fixture = fixture().await;
    set_presence(
        &mut fixture,
        "claude-term",
        "claude",
        AgentPresenceState::Working,
    );
    set_presence(
        &mut fixture,
        "codex-term",
        "codex",
        AgentPresenceState::Done,
    );
    set_presence(
        &mut fixture,
        "shell-term",
        "copilot",
        AgentPresenceState::Working,
    );
    let (tx, _rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    fixture.actor.coordinators.insert(
        "run_1".to_string(),
        CoordinatorHandle::start(
            CoordinatorConfig {
                run_id: "run_1".to_string(),
                coordinator_handle: Some("lonely-term".to_string()),
                poll_interval_ms: 60_000,
                max_concurrent: 1,
                workspace_id: Some("ws-2".to_string()),
                agent_type: "codex".to_string(),
            },
            tx,
            |run_id| run_id,
        ),
    );

    let targets = fixture.ok(PHONE, "inbox.targets", json!({})).await;
    let modes: Vec<_> = targets["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|item| {
            (
                item["handle"].as_str().unwrap().to_string(),
                item["deliveryMode"].as_str().unwrap().to_string(),
                item["acceptsQueuedInput"].as_bool().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        modes,
        [
            ("claude-term".to_string(), "pasted_now".to_string(), true),
            ("codex-term".to_string(), "pasted_now".to_string(), true),
            ("lonely-term".to_string(), "check".to_string(), true),
            (
                "shell-term".to_string(),
                "queued_at_turn_end".to_string(),
                false
            ),
        ]
    );
    fixture.actor.sessions.remove("claude-term");
    assert_eq!(
        fixture.actor.inbox_recipient("claude-term")["deliveryMode"],
        "unavailable"
    );
}

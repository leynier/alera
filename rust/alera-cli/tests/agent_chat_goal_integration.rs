//! Codex `/goal` over real host sockets and the provider process fixture.

#![cfg(unix)]

use serde_json::{json, Value};

#[allow(
    dead_code,
    reason = "The shared socket fixture also supports broader lifecycle tests."
)]
#[path = "support/agent_chat_socket_host.rs"]
mod agent_chat_socket_host;

use agent_chat_socket_host::{Host, WORKSPACE};

fn methods(host: &Host) -> Vec<String> {
    host.log()
        .iter()
        .filter(|entry| entry["event"] == "input")
        .filter_map(|entry| entry["message"]["method"].as_str().map(str::to_owned))
        .filter(|method| method.starts_with("thread/goal/") || method == "turn/start")
        .collect()
}

#[test]
fn a_goal_runs_through_the_turn_codex_starts_until_it_is_complete() {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let status = desktop.ok("status.get", json!({}));
    let capabilities = status["runtimeCapabilities"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    assert!(capabilities.contains(&json!("agentChatGoalV1")));
    let chat = desktop.create()["chatId"].as_str().unwrap().to_owned();
    desktop.ok(
        "agentChat.send",
        json!({
            "requestId": "goal-send", "chatId": chat, "workspaceId": WORKSPACE,
            "clientMessageId": "goal-message", "text": "/goal Ship the fixture",
        }),
    );
    let snapshot = desktop.wait_snapshot(&chat, |snapshot| {
        snapshot["session"]["goal"]["status"] == "complete"
            && snapshot["session"]["status"] == "ready"
    });
    assert_eq!(snapshot["session"]["goal"]["objective"], "Ship the fixture");
    let commands: Vec<&str> = snapshot["session"]["commands"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|command| command["name"].as_str())
        .collect();
    assert_eq!(commands, ["compact", "goal"]);
    let turns = snapshot["turns"].as_array().unwrap();
    assert_eq!(turns.len(), 2, "{snapshot}");
    assert_eq!(turns[0]["status"], "completed");
    assert_eq!(turns[0].get("origin"), None);
    assert_eq!(turns[1]["status"], "completed");
    assert_eq!(turns[1]["origin"], "goalContinuation");
    let users: Vec<&Value> = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|item| item["type"] == "user_message")
        .collect();
    assert_eq!(users.len(), 1);
    assert_eq!(users[0]["turnId"], turns[0]["turnId"]);
    assert_eq!(
        methods(&host),
        [
            "thread/goal/get",
            "thread/goal/set",
            "turn/start",
            "thread/goal/set",
        ]
    );
    let start = host.inputs("turn/start").remove(0);
    assert_eq!(
        start["message"]["params"]["input"][0]["text"],
        "Start working toward this goal: Ship the fixture"
    );

    desktop.ok(
        "agentChat.send",
        json!({
            "requestId": "goal-clear", "chatId": chat, "workspaceId": WORKSPACE,
            "clientMessageId": "goal-clear-message", "text": "/goal clear",
        }),
    );
    let snapshot = desktop.wait_snapshot(&chat, |snapshot| {
        snapshot["session"].get("goal").is_none()
            && snapshot["turns"]
                .as_array()
                .is_some_and(|turns| turns.len() == 3)
            && snapshot["session"]["status"] == "ready"
    });
    assert_eq!(snapshot["turns"][2]["status"], "completed");
    assert_eq!(
        methods(&host)[4..],
        ["thread/goal/get", "thread/goal/clear"]
    );
}

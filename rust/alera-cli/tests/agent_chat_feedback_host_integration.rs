//! `/feedback` through a real runtime-host socket and the production Codex
//! JSONL transport, against the deterministic fixture peer.

#![cfg(unix)]

use serde_json::{json, Value};

#[allow(
    dead_code,
    reason = "The shared socket fixture also supports broader lifecycle tests."
)]
#[path = "support/agent_chat_socket_host.rs"]
mod agent_chat_socket_host;

use agent_chat_socket_host::{Host, Socket, WORKSPACE};

fn ready_after(socket: &mut Socket, chat: &str, turns: usize) -> Value {
    socket.wait_snapshot(chat, |snapshot| {
        snapshot["session"]["status"] == "ready"
            && snapshot["turns"]
                .as_array()
                .is_some_and(|all| all.len() == turns)
    })
}

#[test]
fn feedback_uploads_the_codex_thread_once_and_never_starts_a_turn() {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let status = desktop.ok("status.get", json!({}));
    assert!(status["runtimeCapabilities"]
        .as_array()
        .unwrap()
        .contains(&json!("agentChatFeedbackV1")));

    let created = desktop.create();
    let chat = created["chatId"].as_str().unwrap();
    let early = desktop.request(
        "agentChat.feedback",
        json!({"requestId": "feedback-early", "chatId": chat}),
    );
    assert_eq!(early["ok"], false);
    assert_eq!(early["errorCode"], "feedbackNeedsConversation");
    assert_eq!(early["error"], "Send a message before you submit feedback.");
    host.assert_no_provider_start();

    desktop.ok(
        "agentChat.send",
        json!({"requestId": "send-1", "chatId": chat, "workspaceId": WORKSPACE,
               "clientMessageId": "message-1", "text": "hello"}),
    );
    let finished = ready_after(&mut desktop, chat, 1);
    let commands = finished["session"]["commands"].as_array().unwrap();
    assert!(
        commands.iter().any(|command| command["name"] == "feedback"),
        "Codex did not advertise /feedback: {commands:?}"
    );

    let request = json!({"requestId": "feedback-1", "chatId": chat,
                         "workspaceId": WORKSPACE, "reason": " Wrong file edited "});
    let answer = desktop.ok("agentChat.feedback", request.clone());
    let uploads = host.inputs("feedback/upload");
    assert_eq!(uploads.len(), 1);
    let params = &uploads[0]["message"]["params"];
    let native_thread = params["threadId"].as_str().unwrap();
    assert!(native_thread.starts_with("fixture-thread-"), "{params}");
    assert_eq!(
        params,
        &json!({"classification": "bug", "includeLogs": true,
                "reason": "Wrong file edited", "threadId": native_thread})
    );
    assert_eq!(
        answer["feedbackId"],
        format!("fixture-feedback-{native_thread}")
    );
    assert_eq!(desktop.ok("agentChat.feedback", request), answer);
    assert_eq!(
        host.inputs("feedback/upload").len(),
        1,
        "a replay uploaded twice"
    );

    let failed = desktop.request(
        "agentChat.feedback",
        json!({"requestId": "feedback-2", "chatId": chat, "reason": "fail"}),
    );
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["errorCode"], "feedbackFailed");
    assert_eq!(failed["error"], "Fixture feedback upload refused.");

    let after = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert_eq!(after["items"], finished["items"]);
    assert_eq!(after["turns"], finished["turns"]);
    assert_eq!(host.inputs("turn/start").len(), 1);
}

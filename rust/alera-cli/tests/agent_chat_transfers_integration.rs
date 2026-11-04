//! Context transfers (`agentChatTransfersV1`) over real host sockets and the
//! provider process fixture: a fork and its merge-back leave records in the
//! snapshot, the change stream and `chatOrchestration.transfers`.

#![cfg(unix)]

use serde_json::{json, Value};

#[allow(
    dead_code,
    reason = "The shared socket fixture also supports broader lifecycle tests."
)]
#[path = "support/agent_chat_socket_host.rs"]
mod agent_chat_socket_host;

use agent_chat_socket_host::{Host, Socket, WORKSPACE};

fn send(socket: &mut Socket, chat: &str, id: &str, text: &str) -> Value {
    socket.ok(
        "agentChat.send",
        json!({"requestId": id, "chatId": chat, "workspaceId": WORKSPACE,
               "clientMessageId": id, "text": text}),
    )
}

fn completed(socket: &mut Socket, chat: &str, count: usize) -> Value {
    socket.wait_snapshot(chat, |snapshot| {
        snapshot["session"]["status"] == "ready"
            && snapshot["turns"].as_array().is_some_and(|turns| {
                turns.len() == count && turns.iter().all(|turn| turn["status"] == "completed")
            })
    })
}

#[test]
fn a_fork_and_its_merge_back_are_projected_as_transfers() {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let status = desktop.ok("status.get", json!({}));
    assert!(status["runtimeCapabilities"]
        .as_array()
        .unwrap()
        .contains(&json!("agentChatTransfersV1")));

    let source = desktop.create()["chatId"].as_str().unwrap().to_owned();
    let first = send(&mut desktop, &source, "first", "Plan the cache");
    completed(&mut desktop, &source, 1);
    let forked = desktop.ok(
        "agentChat.fork",
        json!({"requestId": "fork", "chatId": source, "turnId": first["turnId"],
               "title": "Cache experiment"}),
    );
    let fork = forked["chatId"].as_str().unwrap().to_owned();
    let fork_record = &forked["snapshot"]["contextTransfers"][0];
    assert_eq!(fork_record["kind"], "fork");
    assert_eq!(fork_record["sourceChatId"], source.as_str());
    assert_eq!(fork_record["sourceTurnId"], first["turnId"]);

    send(&mut desktop, &fork, "fork-first", "Try an LRU cache");
    completed(&mut desktop, &fork, 2);
    desktop.ok(
        "agentChat.mergeBack",
        json!({"requestId": "merge", "chatId": fork}),
    );
    let changed = desktop.wait_event(|event| {
        event["event"] == "agentChatChanged"
            && event["payload"]["chatId"] == source.as_str()
            && event["payload"]["delta"]["contextTransfers"].is_array()
    });
    let record = &changed["payload"]["delta"]["contextTransfers"][0];
    assert_eq!(record["kind"], "mergeBack");
    assert_eq!(record["status"], "pending");
    assert_eq!(record["sourceChatId"], fork.as_str());

    let listed = desktop.ok("chatOrchestration.transfers", json!({"chatId": source}));
    assert_eq!(listed["chatId"], source.as_str());
    let transfers = listed["transfers"].as_array().unwrap();
    assert_eq!(transfers.len(), 1);
    assert_eq!(transfers[0]["kind"], "mergeBack");
    assert_eq!(transfers[0]["transferId"], record["transferId"]);
    assert!(transfers[0].get("itemId").is_none());

    send(&mut desktop, &source, "second", "Which one wins?");
    let snapshot = completed(&mut desktop, &source, 2);
    assert_eq!(snapshot["contextTransfers"][0]["status"], "consumed");
    assert_eq!(
        snapshot["contextTransfers"][0]["targetTurnId"],
        snapshot["turns"][1]["turnId"]
    );
}

//! Workflow verbs (`agentChatWorkflowsV1`) over real host sockets: the host
//! advertises them and routes them to the chat, which refuses an item that
//! started no workflow.

#![cfg(unix)]

use serde_json::{json, Value};

#[allow(
    dead_code,
    reason = "The shared socket fixture also supports broader lifecycle tests."
)]
#[path = "support/agent_chat_socket_host.rs"]
mod agent_chat_socket_host;

use agent_chat_socket_host::{Host, WORKSPACE};

#[test]
fn workflow_verbs_are_advertised_and_refuse_an_item_that_started_no_workflow() {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let status = desktop.ok("status.get", json!({}));
    assert!(status["runtimeCapabilities"]
        .as_array()
        .unwrap()
        .contains(&json!("agentChatWorkflowsV1")));
    let chat = desktop.create()["chatId"].as_str().unwrap().to_owned();
    desktop.ok(
        "agentChat.send",
        json!({
            "requestId": "workflow-send", "chatId": chat, "workspaceId": WORKSPACE,
            "clientMessageId": "workflow-message", "text": "Hello",
        }),
    );
    let snapshot = desktop.wait_snapshot(&chat, |snapshot| {
        snapshot["items"]
            .as_array()
            .is_some_and(|items| items.iter().any(|item| item["type"] == "user_message"))
    });
    let item = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["type"] == "user_message")
        .map(|item| item["itemId"].clone())
        .unwrap();
    let refused: Vec<Value> = [
        (
            "agentChat.workflowScript",
            json!({"chatId": chat, "itemId": item}),
        ),
        (
            "agentChat.workflowAgent",
            json!({"chatId": chat, "itemId": item, "agentIndex": 1}),
        ),
    ]
    .into_iter()
    .map(|(verb, payload)| desktop.request(verb, payload))
    .collect();
    for response in refused {
        assert_eq!(response["ok"], false, "{response}");
        assert_eq!(response["errorCode"], "notWorkflow", "{response}");
    }
    let malformed = desktop.request(
        "agentChat.workflowAgent",
        json!({"chatId": chat, "itemId": item, "agentIndex": -1}),
    );
    assert_eq!(malformed["ok"], false, "{malformed}");
}

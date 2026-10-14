//! Real runtime-host sockets and the production JSONL process transport, without inference.
//!
//! The executable fixture requires Python 3 and Unix process-group teardown.
//! Windows process launch and socket behavior remain outside this test target.

#![cfg(unix)]

use serde_json::{json, Value};
use std::fs;

#[path = "support/agent_chat_socket_host.rs"]
mod agent_chat_socket_host;

use agent_chat_socket_host::{Host, Socket, WORKSPACE};

fn send_input(chat: &str, request: &str, client_message: &str, text: &str) -> Value {
    json!({"requestId": request, "chatId": chat, "workspaceId": WORKSPACE,
           "clientMessageId": client_message, "text": text})
}

fn completed(socket: &mut Socket, chat: &str, count: usize) -> Value {
    socket.wait_snapshot(chat, |snapshot| {
        snapshot["session"]["status"] == "ready"
            && snapshot["turns"].as_array().is_some_and(|turns| {
                turns.len() == count && turns.iter().all(|turn| turn["status"] == "completed")
            })
    })
}

fn items_of_type<'a>(snapshot: &'a Value, kind: &str) -> Vec<&'a Value> {
    snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|item| item["type"] == kind)
        .collect()
}

fn chat_events(socket: &Socket) -> Vec<&Value> {
    socket
        .events
        .iter()
        .filter(|event| {
            event["event"]
                .as_str()
                .is_some_and(|name| name.starts_with("agentChat"))
        })
        .collect()
}

#[test]
fn socket_chat_streams_approval_once_and_reconnects_to_the_durable_snapshot() {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let status = desktop.ok("status.get", json!({}));
    assert!(status["runtimeCapabilities"]
        .as_array()
        .unwrap()
        .contains(&json!("agentChatV1")));
    let catalog = desktop.ok("agentChat.providers", json!({"workspaceId": WORKSPACE}));
    let fixture = catalog["providers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|provider| provider["providerInstanceId"] == "fixture-codex")
        .unwrap();
    assert_eq!(fixture["available"], true);
    assert_eq!(fixture["modelsSource"], "configured");
    assert_eq!(fixture["models"][0]["id"], "fixture-model");
    assert_eq!(fixture["installed"], true);
    assert_eq!(fixture["version"], "1.2.3");
    let probes = host.log();
    assert_eq!(
        probes.len(),
        2,
        "catalog did not use exactly two metadata probes"
    );
    assert_eq!(probes[0]["args"], json!(["--version"]));
    assert_eq!(probes[1]["args"], json!(["debug", "models"]));
    host.assert_no_provider_start();
    assert_eq!(
        desktop.ok("agentChat.providers", json!({"workspaceId": WORKSPACE})),
        catalog
    );
    assert_eq!(
        host.log(),
        probes,
        "cached catalog repeated its status probe"
    );

    let created = desktop.create();
    let chat = created["chatId"].as_str().unwrap();
    let tab = created["tabId"].as_str().unwrap();
    let draft = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert_eq!(draft["session"]["status"], "stopped");
    assert_eq!(draft["turns"], json!([]));
    assert_eq!(draft["items"], json!([]));
    host.assert_no_provider_start();
    let tab_record = desktop.ok("tab.find", json!({"id": tab}));
    assert_eq!(tab_record["kind"], "agentChat");
    assert_eq!(tab_record["payload"]["chatId"], chat);
    assert_eq!(tab_record["payload"]["providerInstanceId"], "fixture-codex");

    let input = send_input(chat, "send-approval", "message-approval", "approval");
    let started = desktop.ok("agentChat.send", input.clone());
    assert_eq!(started["delivery"], "started");
    assert_eq!(desktop.ok("agentChat.send", input.clone()), started);
    let mut same_message = input.clone();
    same_message["requestId"] = json!("send-approval-another-receipt");
    assert_eq!(desktop.ok("agentChat.send", same_message), started);
    let mut conflicting = input;
    conflicting["text"] = json!("a different prompt");
    let conflict = desktop.request("agentChat.send", conflicting);
    assert_eq!(conflict["ok"], false);
    assert_eq!(conflict["errorCode"], "request_conflict");

    let waiting = desktop.wait_snapshot(chat, |snapshot| {
        snapshot["session"]["status"] == "waiting"
            && snapshot["pendingRequests"]
                .as_array()
                .is_some_and(|requests| requests.len() == 1)
    });
    assert_eq!(
        items_of_type(&waiting, "assistant_message")[0]["text"],
        "Fixture response."
    );
    assert_eq!(items_of_type(&waiting, "user_message").len(), 1);
    let request = &waiting["pendingRequests"][0];
    assert_eq!(request["kind"], "command_execution_approval");
    assert_eq!(request["command"], "printf fixture");
    let runtime_request = request["requestId"].as_str().unwrap();
    assert_ne!(runtime_request, "7001");
    assert_ne!(runtime_request, "fixture-command");
    desktop.wait_event(|event| {
        event["event"] == "agentChatChanged"
            && event["payload"]["chatId"] == chat
            && event["payload"]["delta"].to_string().contains("Fixture")
    });

    let approval = json!({
        "requestId": "accept-approval", "chatId": chat,
        "runtimeRequestId": runtime_request,
        "response": {"type": "approval", "decision": "accept"},
    });
    let accepted = desktop.ok("agentChat.respond", approval.clone());
    let finished = completed(&mut desktop, chat, 1);
    assert_eq!(desktop.ok("agentChat.respond", approval), accepted);
    assert_eq!(finished["pendingRequests"], json!([]));
    assert_eq!(
        items_of_type(&finished, "assistant_message")[0]["text"],
        "Fixture response."
    );
    assert_eq!(items_of_type(&finished, "user_message").len(), 1);
    assert_eq!(
        host.inputs("turn/start").len(),
        1,
        "a replay sent a second native turn"
    );
    let messages = host
        .log()
        .into_iter()
        .filter(|row| row["event"] == "input")
        .map(|row| row["message"].clone())
        .collect::<Vec<_>>();
    assert_eq!(messages[0]["method"], "initialize");
    assert_eq!(messages[1]["method"], "initialized");
    assert_eq!(messages[2]["method"], "thread/start");
    assert_eq!(messages[2]["params"]["approvalPolicy"], "untrusted");
    assert_eq!(messages[3]["method"], "turn/start");
    assert_eq!(messages[3]["params"]["input"][0]["text"], "approval");
    assert_eq!(
        messages
            .iter()
            .filter(|message| *message
                == &json!({
                    "id": 7001, "result": {"decision": "accept"},
                }))
            .count(),
        1,
        "approval did not reach the native JSONL request id exactly once"
    );

    drop(desktop);
    let mut reconnected = host.connect();
    let restored = reconnected.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert_eq!(restored["cursor"], finished["cursor"]);
    assert_eq!(restored["items"], finished["items"]);
    assert_eq!(restored["turns"], finished["turns"]);
    assert_eq!(restored["tabId"], tab);
}

#[test]
fn close_reaps_provider_and_reopening_a_cached_archived_chat_resumes_history() {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let created = desktop.create();
    let chat = created["chatId"].as_str().unwrap();
    let old_tab = created["tabId"].as_str().unwrap();
    let draft = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert_eq!(draft["session"]["status"], "stopped");
    host.assert_no_provider_start();
    desktop.ok(
        "agentChat.send",
        send_input(chat, "send-first", "first-message", "first"),
    );
    let first = completed(&mut desktop, chat, 1);
    let start = host
        .log()
        .into_iter()
        .find(|row| row["event"] == "started")
        .unwrap();
    let first_pid = start["pid"].as_i64().unwrap();
    let credential_path = start["credentialPath"].as_str().unwrap();
    let native_thread = host.inputs("turn/start")[0]["message"]["params"]["threadId"].clone();

    assert_eq!(
        desktop.ok(
            "agentChat.close",
            json!({"requestId": "close-first", "chatId": chat})
        ),
        json!({"archived": true})
    );
    host.wait_for_exit(first_pid);
    assert!(
        !std::path::Path::new(credential_path).exists(),
        "close did not revoke the generation credential"
    );
    assert_eq!(desktop.ok("tab.find", json!({"id": old_tab})), Value::Null);
    assert_eq!(
        desktop.ok("agentChat.list", json!({"workspaceId": WORKSPACE}))["chats"],
        json!([])
    );

    // This loads an archived actor before reopen, exposing stale actor state.
    let archived = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert_eq!(archived["archived"], true);
    assert_eq!(archived["session"]["status"], "stopped");
    assert_eq!(archived["items"], first["items"]);
    let rejected = desktop.request(
        "agentChat.send",
        send_input(chat, "send-closed", "closed-message", "closed"),
    );
    assert_eq!(rejected["ok"], false);
    assert_eq!(rejected["errorCode"], "chatArchived");
    let before_reopen = host.log();
    let reopened = desktop.ok(
        "agentChat.reopen",
        json!({"requestId": "reopen-first", "chatId": chat}),
    );
    assert_eq!(reopened["chatId"], chat);
    let new_tab = reopened["tabId"].as_str().unwrap();
    assert_ne!(new_tab, old_tab);
    assert_eq!(reopened["snapshot"]["archived"], false);
    assert_eq!(reopened["snapshot"]["session"]["status"], "stopped");
    let visible = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert_eq!(visible["archived"], false);
    assert_eq!(visible["tabId"], new_tab);
    assert_eq!(visible["items"], first["items"]);
    assert_eq!(visible["turns"], first["turns"]);
    assert_eq!(visible["session"]["status"], "stopped");
    assert_eq!(host.log(), before_reopen, "reopen eagerly started the SDK");
    host.assert_no_chat_credentials();
    assert_eq!(
        desktop.ok("tab.list", json!({"workspaceId": WORKSPACE}))[0]["id"],
        new_tab
    );
    desktop.ok(
        "agentChat.send",
        send_input(chat, "send-reopened", "second-message", "second"),
    );
    let second = completed(&mut desktop, chat, 2);
    assert_eq!(items_of_type(&second, "user_message").len(), 2);
    assert_eq!(items_of_type(&second, "assistant_message").len(), 2);
    let resumes = host.inputs("thread/resume");
    assert_eq!(resumes.len(), 1);
    assert_eq!(resumes[0]["message"]["params"]["threadId"], native_thread);
    assert_eq!(host.inputs("turn/start").len(), 2);
    let second_pid = resumes[0]["pid"].as_i64().unwrap();
    assert_ne!(first_pid, second_pid);
    desktop.ok(
        "agentChat.close",
        json!({"requestId": "close-second", "chatId": chat}),
    );
    host.wait_for_exit(second_pid);
}

#[test]
fn capability_opt_in_and_chat_credentials_enforce_socket_visibility_and_permissions() {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let mut no_kinds = host.raw_socket();
    assert_eq!(no_kinds.hello(false, true, None)["ok"], true);
    let mut no_capability = host.raw_socket();
    assert_eq!(no_capability.hello(true, false, None)["ok"], true);
    let mut invalid = host.raw_socket();
    let rejection = invalid.hello(true, true, Some("invalid-synthetic-credential"));
    assert_eq!(rejection["ok"], false);
    assert_eq!(rejection["errorCode"], "chat_credential_invalid");
    assert_eq!(invalid.request("agentChat.list", json!({}))["ok"], false);

    let created = desktop.create();
    let chat = created["chatId"].as_str().unwrap();
    let tab = created["tabId"].as_str().unwrap();
    let draft = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert_eq!(draft["session"]["status"], "stopped");
    host.assert_no_provider_start();
    let record = desktop.ok("tab.find", json!({"id": tab}));
    for (client_name, legacy) in [
        ("no_supported_tab_kinds", &mut no_kinds),
        ("no_agent_chat_capability", &mut no_capability),
    ] {
        assert_eq!(legacy.ok("tab.find", json!({"id": tab})), Value::Null);
        assert_eq!(
            legacy.ok("tab.list", json!({"workspaceId": WORKSPACE})),
            json!([])
        );
        let rejected = legacy.request("tab.upsert", record.clone());
        assert_eq!(rejected["ok"], false);
        assert_eq!(rejected["errorCode"], "unsupported");
        let events = chat_events(legacy);
        assert!(
            events.is_empty(),
            "{client_name} received chat events: {events:?}"
        );
    }

    desktop.ok(
        "agentChat.send",
        send_input(chat, "mint-bound-credential", "credential-message", "first"),
    );
    completed(&mut desktop, chat, 1);
    let start = host
        .log()
        .into_iter()
        .find(|row| row["event"] == "started")
        .unwrap();
    assert_eq!(
        start["cwd"],
        host.root().join("workspace").to_string_lossy().as_ref()
    );
    assert_eq!(start["originator"], "alera");
    let credential_path = start["credentialPath"].as_str().unwrap();
    let credential = fs::read_to_string(credential_path).unwrap();
    let mut bound = host.raw_socket();
    let hello = bound.hello(true, true, Some(&credential));
    assert_eq!(hello["ok"], true);
    assert_eq!(hello["payload"]["chatBinding"]["chatId"], chat);
    bound.ok("status.get", json!({}));
    bound.ok("project.list", json!({}));
    let inactive = bound.request("chatOrchestration.read", json!({"chatId": chat}));
    assert_eq!(inactive["ok"], false);
    assert_eq!(inactive["errorCode"], "caller_turn_inactive");

    // Keep the caller's turn live while exercising its bound permissions.
    desktop.ok(
        "agentChat.send",
        send_input(chat, "start-bound-turn", "bound-live-message", "approval"),
    );
    desktop.wait_snapshot(chat, |snapshot| {
        snapshot["session"]["status"] == "waiting"
            && snapshot["session"]["activeTurnId"].is_string()
            && snapshot["pendingRequests"]
                .as_array()
                .is_some_and(|requests| requests.len() == 1)
    });
    bound.ok("chatOrchestration.read", json!({"chatId": chat}));
    let authorized_turns = host.inputs("turn/start").len();
    assert_eq!(authorized_turns, 2);
    for (verb, payload) in [
        ("agentChat.snapshot", json!({"chatId": chat})),
        (
            "agentChat.send",
            send_input(chat, "bound-send", "bound-message", "denied"),
        ),
        ("tab.upsert", record),
        ("createOrAttach", json!({"sessionId": "denied-terminal"})),
    ] {
        let denied = bound.request(verb, payload);
        assert_eq!(denied["ok"], false, "bound credential allowed {verb}");
        assert_eq!(denied["errorCode"], "chat_scope_denied");
    }
    assert_eq!(
        host.inputs("turn/start").len(),
        authorized_turns,
        "a denied write started another provider turn"
    );
    desktop.ok(
        "agentChat.rename",
        json!({"requestId": "rename-visible", "chatId": chat, "title": "Visible Chat"}),
    );
    desktop.wait_event(|event| {
        event["event"] == "agentChatChanged"
            && event["payload"]["chatId"] == chat
            && event["payload"]["delta"]["title"] == "Visible Chat"
    });
    for legacy in [&mut no_kinds, &mut no_capability, &mut bound] {
        legacy.ok("status.get", json!({}));
    }
    let received = json!({
        "no_supported_tab_kinds": chat_events(&no_kinds),
        "no_agent_chat_capability": chat_events(&no_capability),
        "chat_bound": chat_events(&bound),
    });
    assert_eq!(
        received,
        json!({
            "no_supported_tab_kinds": [],
            "no_agent_chat_capability": [],
            "chat_bound": [],
        }),
        "an unnegotiated or bound socket received chat events: {received}"
    );
    desktop.ok(
        "agentChat.close",
        json!({"requestId": "close-bound", "chatId": chat}),
    );
    let revoked = bound.request("chatOrchestration.read", json!({"chatId": chat}));
    assert_eq!(revoked["ok"], false);
    assert_eq!(revoked["errorCode"], "chat_credential_invalid");
    let mut expired = host.raw_socket();
    let expired_hello = expired.hello(true, true, Some(&credential));
    assert_eq!(expired_hello["ok"], false);
    assert_eq!(expired_hello["errorCode"], "chat_credential_invalid");
}

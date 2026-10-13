//! Snapshot mutation responses over real host sockets and the provider process fixture.

#![cfg(unix)]

use serde_json::{json, Value};

#[allow(
    dead_code,
    reason = "The shared socket fixture also supports broader lifecycle tests."
)]
#[path = "support/agent_chat_socket_host.rs"]
mod agent_chat_socket_host;

use agent_chat_socket_host::{Host, Socket, WORKSPACE};

fn setup() -> (Host, Socket, String) {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let created = desktop.create();
    let chat = created["chatId"].as_str().unwrap().to_owned();
    desktop.wait_snapshot(&chat, |snapshot| snapshot["session"]["status"] == "ready");
    (host, desktop, chat)
}

fn envelope_snapshot<'a>(response: &'a Value, chat: &str) -> &'a Value {
    let payload = response.as_object().expect("snapshot response object");
    assert_eq!(
        payload.len(),
        1,
        "expected exactly {{snapshot}}: {response}"
    );
    let snapshot = payload.get("snapshot").expect("snapshot envelope");
    assert_eq!(snapshot["chatId"], chat);
    assert!(snapshot["cursor"].is_u64());
    assert!(snapshot["session"].is_object());
    assert!(
        snapshot.get("snapshot").is_none(),
        "snapshot was nested twice"
    );
    snapshot
}

fn committed_event(socket: &mut Socket, chat: &str, cursor: &Value) {
    socket.wait_event(|event| {
        event["event"] == "agentChatChanged"
            && event["payload"]["chatId"] == chat
            && event["payload"]["cursor"] == *cursor
    });
}

#[test]
fn configure_envelopes_the_final_committed_snapshot_and_replays_it_exactly() {
    let (_host, mut desktop, chat) = setup();
    let before = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert!(
        before.get("snapshot").is_none(),
        "snapshot reads remain raw"
    );
    let payload = json!({"requestId": "configure-model", "chatId": chat, "model": "changed-model"});
    let configured = desktop.ok("agentChat.configure", payload.clone());
    let snapshot = envelope_snapshot(&configured, &chat);
    assert_eq!(snapshot["session"]["model"], "changed-model");
    assert_eq!(
        snapshot["cursor"].as_u64(),
        Some(before["cursor"].as_u64().unwrap() + 2)
    );
    committed_event(&mut desktop, &chat, &snapshot["cursor"]);
    assert_eq!(
        desktop.ok("agentChat.snapshot", json!({"chatId": chat})),
        *snapshot
    );
    let later = desktop.ok(
        "agentChat.configure",
        json!({
            "requestId": "configure-again", "chatId": chat, "model": "later-model",
        }),
    );
    let later_snapshot = envelope_snapshot(&later, &chat);
    assert_eq!(
        desktop.ok("agentChat.configure", payload.clone()),
        configured
    );
    assert_eq!(
        desktop.ok("agentChat.snapshot", json!({"chatId": chat})),
        *later_snapshot
    );
    let mut conflicting = payload;
    conflicting["model"] = json!("different-model");
    let error = desktop.request("agentChat.configure", conflicting);
    assert_eq!(error["ok"], false);
    assert_eq!(error["errorCode"], "request_conflict");
    assert!(error.get("payload").is_none());
}

#[test]
fn recovering_an_already_running_session_returns_one_envelope_without_a_restart() {
    let (host, mut desktop, chat) = setup();
    let before = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    let payload = json!({"requestId": "recover-running", "chatId": chat, "mode": "resume"});
    let recovered = desktop.ok("agentChat.recover", payload.clone());
    let snapshot = envelope_snapshot(&recovered, &chat);
    assert_eq!(snapshot["session"]["status"], "ready");
    assert_eq!(
        snapshot["session"]["generation"],
        before["session"]["generation"]
    );
    assert_eq!(
        snapshot["cursor"].as_u64(),
        Some(before["cursor"].as_u64().unwrap() + 1)
    );
    committed_event(&mut desktop, &chat, &snapshot["cursor"]);
    assert_eq!(
        desktop.ok("agentChat.snapshot", json!({"chatId": chat})),
        *snapshot
    );
    assert_eq!(desktop.ok("agentChat.recover", payload), recovered);
    assert_eq!(
        desktop.ok("agentChat.snapshot", json!({"chatId": chat})),
        *snapshot
    );
    assert_eq!(host.inputs("thread/start").len(), 1);
    assert!(host.inputs("thread/resume").is_empty());
}

fn recover_stopped_session(mode: &str) {
    let (host, mut desktop, chat) = setup();
    let before = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    desktop.ok("workspace.sleep", json!({"workspaceId": WORKSPACE}));
    let stopped =
        desktop.wait_snapshot(&chat, |snapshot| snapshot["session"]["status"] == "stopped");
    let payload = json!({"requestId": "recover-stopped", "chatId": chat, "mode": mode});
    let recovered = desktop.ok("agentChat.recover", payload.clone());
    let snapshot = envelope_snapshot(&recovered, &chat);
    assert_eq!(snapshot["session"]["status"], "starting");
    assert_eq!(
        snapshot["session"]["generation"],
        before["session"]["generation"]
    );
    assert!(snapshot["recovery"].is_null());
    assert_eq!(
        snapshot["cursor"].as_u64(),
        Some(stopped["cursor"].as_u64().unwrap() + 2)
    );
    committed_event(&mut desktop, &chat, &snapshot["cursor"]);
    let ready = desktop.wait_snapshot(&chat, |snapshot| snapshot["session"]["status"] == "ready");
    assert_eq!(
        ready["session"]["generation"],
        before["session"]["generation"]
    );
    assert!(ready["cursor"].as_u64().unwrap() > snapshot["cursor"].as_u64().unwrap());
    assert_eq!(desktop.ok("agentChat.recover", payload), recovered);
    assert_eq!(
        desktop.ok("agentChat.snapshot", json!({"chatId": chat})),
        ready
    );
    match mode {
        "restart" => {
            assert_eq!(host.inputs("thread/start").len(), 2);
            assert!(host.inputs("thread/resume").is_empty());
        }
        "resume" => {
            assert_eq!(host.inputs("thread/start").len(), 1);
            let resumes = host.inputs("thread/resume");
            assert_eq!(resumes.len(), 1);
            let first_pid = host
                .log()
                .into_iter()
                .find(|row| row["event"] == "started")
                .unwrap()["pid"]
                .as_i64()
                .unwrap();
            assert_eq!(
                resumes[0]["message"]["params"]["threadId"],
                format!("fixture-thread-{first_pid}")
            );
        }
        _ => unreachable!(),
    }
}

#[test]
fn recovering_a_stopped_session_starts_fresh_and_replays_its_snapshot_envelope() {
    recover_stopped_session("restart");
}

#[test]
fn recovering_a_stopped_session_resumes_its_native_thread_and_keeps_generation() {
    recover_stopped_session("resume");
}

#[test]
fn snapshot_mutation_errors_keep_the_existing_protocol_shape() {
    let (_host, mut desktop, chat) = setup();
    let invalid = desktop.request(
        "agentChat.configure",
        json!({
            "requestId": "invalid-configuration", "chatId": chat, "interactionMode": "unknown",
        }),
    );
    assert_eq!(invalid["ok"], false);
    assert_eq!(invalid["errorCode"], "unsupported");
    assert!(invalid["error"]
        .as_str()
        .unwrap()
        .contains("unknown interaction mode"));
    assert!(invalid.get("payload").is_none());
    assert!(invalid.get("snapshot").is_none());
    desktop.ok("workspace.sleep", json!({"workspaceId": WORKSPACE}));
    desktop.wait_snapshot(&chat, |snapshot| snapshot["session"]["status"] == "stopped");
    let invalid = desktop.request(
        "agentChat.recover",
        json!({
            "requestId": "invalid-recovery", "chatId": chat, "mode": "unknown",
        }),
    );
    assert_eq!(invalid["ok"], false);
    assert_eq!(
        invalid["error"],
        "FormatException: Unknown recovery mode unknown"
    );
    assert!(invalid.get("errorCode").is_none());
    assert!(invalid.get("payload").is_none());
    assert!(invalid.get("snapshot").is_none());
}

#[test]
fn orchestration_configure_forwards_a_single_committed_snapshot_envelope() {
    let (_host, mut desktop, chat) = setup();
    let before = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    let payload = json!({"requestId": "orchestration-configure", "chatId": chat, "model": "orchestrated-model"});
    let configured = desktop.ok("chatOrchestration.configure", payload.clone());
    let snapshot = envelope_snapshot(&configured, &chat);
    assert_eq!(snapshot["session"]["model"], "orchestrated-model");
    assert_eq!(
        snapshot["cursor"].as_u64(),
        Some(before["cursor"].as_u64().unwrap() + 2)
    );
    committed_event(&mut desktop, &chat, &snapshot["cursor"]);
    assert_eq!(
        desktop.ok("agentChat.snapshot", json!({"chatId": chat})),
        *snapshot
    );
    assert_eq!(
        desktop.ok("chatOrchestration.configure", payload),
        configured
    );
    assert_eq!(
        desktop.ok("agentChat.snapshot", json!({"chatId": chat})),
        *snapshot
    );
}

#[test]
fn bound_orchestration_configure_envelopes_its_guarded_operation_once() {
    let (host, mut desktop, parent) = setup();
    desktop.ok(
        "agentChat.send",
        json!({
            "requestId": "parent-approval", "chatId": parent, "clientMessageId": "parent-message",
            "text": "approval",
        }),
    );
    desktop.wait_snapshot(&parent, |snapshot| {
        snapshot["session"]["status"] == "waiting"
    });
    let log = host.log();
    let credential_path = log.iter().find(|row| row["event"] == "started").unwrap()
        ["credentialPath"]
        .as_str()
        .unwrap();
    let credential = std::fs::read_to_string(credential_path).unwrap();
    let mut bound = host.raw_socket();
    assert_eq!(bound.hello(true, true, Some(&credential))["ok"], true);
    let delegated = bound.ok(
        "chatOrchestration.delegate",
        json!({
            "requestId": "bound-child", "task": "complete the fixture task", "notify": "never",
            "agent": {"providerInstanceId": "fixture-codex"},
            "target": {"workspace": {"workspaceId": WORKSPACE}},
        }),
    );
    let child = delegated["childChatId"].as_str().unwrap();
    let before = desktop.wait_snapshot(child, |snapshot| {
        snapshot["session"]["status"] == "ready"
            && snapshot["turns"].as_array().is_some_and(|turns| {
                !turns.is_empty() && turns.iter().all(|turn| turn["status"] == "completed")
            })
    });
    let payload =
        json!({"requestId": "bound-configure", "chatId": child, "model": "bounded-model"});
    let configured = bound.ok("chatOrchestration.configure", payload.clone());
    let snapshot = envelope_snapshot(&configured, child);
    assert_eq!(snapshot["session"]["model"], "bounded-model");
    assert_eq!(
        snapshot["cursor"].as_u64(),
        Some(before["cursor"].as_u64().unwrap() + 2)
    );
    committed_event(&mut desktop, child, &snapshot["cursor"]);
    assert_eq!(
        desktop.ok("agentChat.snapshot", json!({"chatId": child})),
        *snapshot
    );
    assert_eq!(bound.ok("chatOrchestration.configure", payload), configured);
}

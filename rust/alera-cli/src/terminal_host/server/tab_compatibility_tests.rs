use std::collections::HashMap;

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::protocol::{
    CODEX_TAB_KIND, MOBILE_EMULATOR_TAB_KIND, PROTOCOL_VERSION, RUNTIME_HOST_ACCOUNT_CAPABILITY,
    RUNTIME_HOST_CLOUD_PUSH_CAPABILITY, RUNTIME_HOST_CODEX_GOALS_CAPABILITY,
    RUNTIME_HOST_CODEX_SESSIONS_CAPABILITY, RUNTIME_HOST_CODEX_TURN_POLICY_CAPABILITY,
    RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY, RUNTIME_HOST_MOBILE_EMULATOR_CAPABILITY,
};

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::ServerActor;

pub(super) async fn request(
    actor: &mut ServerActor,
    client_id: u64,
    request_id: i64,
    request_type: &str,
    payload: Value,
    receiver: &mut UnboundedReceiver<ClientFrame>,
) -> Value {
    actor
        .handle_line(
            client_id,
            json!({
                "id": request_id,
                "type": request_type,
                "payload": payload,
            })
            .to_string(),
        )
        .await;
    loop {
        let response = receiver
            .recv()
            .await
            .expect("the client should receive a response")
            .as_json()
            .expect("the response should be JSON");
        if response["id"] != request_id {
            continue;
        }
        assert_eq!(response["ok"], true);
        return response["payload"].clone();
    }
}

fn emulator_tab() -> WorkspaceTabRecord {
    let now = "2026-07-27T12:34:56.789Z"
        .parse::<chrono::DateTime<Utc>>()
        .unwrap();
    WorkspaceTabRecord {
        id: "emulator-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: MOBILE_EMULATOR_TAB_KIND.to_string(),
        title: "Pixel 9".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({
            "platform": "android",
            "deviceId": "pixel-9",
        }),
    }
}

fn codex_tab() -> WorkspaceTabRecord {
    let now = "2026-07-27T12:34:56.789Z"
        .parse::<chrono::DateTime<Utc>>()
        .unwrap();
    WorkspaceTabRecord {
        id: "codex-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: CODEX_TAB_KIND.to_string(),
        title: "Codex".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({"codexThreadId": "thread-1"}),
    }
}

fn terminal_pulse_tab() -> WorkspaceTabRecord {
    let now = "2026-07-27T12:34:56.789Z"
        .parse::<chrono::DateTime<Utc>>()
        .unwrap();
    WorkspaceTabRecord {
        id: "terminal-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: "terminal".to_string(),
        title: "Flutter".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({
            "terminalPulse": {
                "command": "r",
                "appendEnter": true,
                "delayMs": 2_000,
            },
            "shell": "zsh",
        }),
    }
}

#[tokio::test]
async fn tab_reads_redact_terminal_pulse_from_mobile_clients() {
    let dir = tempfile::tempdir().unwrap();
    let (local_handle, mut local_rx) = ClientHandle::test_channels();
    let (mobile_handle, mut mobile_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(local_handle)),
            (2, mobile_client(mobile_handle, "phone")),
        ]),
        HashMap::new(),
    )
    .await;
    let tab = terminal_pulse_tab();
    actor
        .runtime_store
        .upsert_workspace_tab(tab.clone())
        .await
        .unwrap();

    let local_list = request(
        &mut actor,
        1,
        1,
        "tab.list",
        json!({"workspaceId": "workspace-1"}),
        &mut local_rx,
    )
    .await;
    let local_find = request(
        &mut actor,
        1,
        2,
        "tab.find",
        json!({"id": "terminal-1"}),
        &mut local_rx,
    )
    .await;
    let mobile_list = request(
        &mut actor,
        2,
        3,
        "tab.list",
        json!({"workspaceId": "workspace-1"}),
        &mut mobile_rx,
    )
    .await;
    let mobile_find = request(
        &mut actor,
        2,
        4,
        "tab.find",
        json!({"id": "terminal-1"}),
        &mut mobile_rx,
    )
    .await;
    let mobile_rename = request(
        &mut actor,
        2,
        5,
        "tab.rename",
        json!({"id": "terminal-1", "title": "Mobile Flutter"}),
        &mut mobile_rx,
    )
    .await;
    let local_rename = request(
        &mut actor,
        1,
        6,
        "tab.rename",
        json!({"id": "terminal-1", "title": "Desktop Flutter"}),
        &mut local_rx,
    )
    .await;

    assert_eq!(local_list[0]["payload"]["terminalPulse"]["command"], "r");
    assert_eq!(local_find["payload"]["terminalPulse"]["command"], "r");
    assert_eq!(mobile_list[0]["payload"]["terminalPulse"], Value::Null);
    assert_eq!(mobile_find["payload"]["terminalPulse"], Value::Null);
    assert_eq!(mobile_rename["payload"]["terminalPulse"], Value::Null);
    assert_eq!(local_rename["payload"]["terminalPulse"]["command"], "r");
    assert_eq!(mobile_list[0]["payload"]["shell"], "zsh");
    assert_eq!(mobile_find["payload"]["shell"], "zsh");
    let stored = actor
        .runtime_store
        .find_workspace_tab("terminal-1")
        .await
        .unwrap()
        .expect("the renamed tab should remain stored");
    assert_eq!(stored.title, "Desktop Flutter");
    assert_eq!(
        stored.payload["terminalPulse"],
        tab.payload["terminalPulse"]
    );
}

#[tokio::test]
async fn terminal_attach_and_restart_responses_use_client_tab_projection() {
    let dir = tempfile::tempdir().unwrap();
    let (local_handle, _local_rx) = ClientHandle::test_channels();
    let (mobile_handle, _mobile_rx) = ClientHandle::test_channels();
    let actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(local_handle)),
            (2, mobile_client(mobile_handle, "phone")),
        ]),
        HashMap::new(),
    )
    .await;
    let tab = terminal_pulse_tab();
    let attachment = json!({"sessionId": "session-1"});

    let mobile = actor.terminal_tab_response_for_client(2, tab.clone(), attachment.clone());
    let local = actor.terminal_tab_response_for_client(1, tab, attachment);

    assert_eq!(mobile["tab"]["payload"]["terminalPulse"], Value::Null);
    assert_eq!(mobile["tab"]["payload"]["shell"], "zsh");
    assert_eq!(mobile["attachment"]["sessionId"], "session-1");
    assert_eq!(local["tab"]["payload"]["terminalPulse"]["command"], "r");
}

#[tokio::test]
async fn tab_reads_hide_codex_from_clients_without_tab_support() {
    let dir = tempfile::tempdir().unwrap();
    let (legacy_handle, mut legacy_rx) = ClientHandle::test_channels();
    let (modern_handle, mut modern_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(legacy_handle)),
            (2, local_client(modern_handle)),
        ]),
        HashMap::new(),
    )
    .await;
    let tab = codex_tab();
    actor
        .runtime_store
        .upsert_workspace_tab(tab.clone())
        .await
        .unwrap();

    request(
        &mut actor,
        1,
        1,
        "hello",
        json!({"protocolVersion": PROTOCOL_VERSION, "token": "token"}),
        &mut legacy_rx,
    )
    .await;
    request(
        &mut actor,
        2,
        2,
        "hello",
        json!({
            "protocolVersion": PROTOCOL_VERSION,
            "token": "token",
            "supportedTabKinds": [CODEX_TAB_KIND],
        }),
        &mut modern_rx,
    )
    .await;

    let legacy_list = request(
        &mut actor,
        1,
        3,
        "tab.list",
        json!({"workspaceId": "workspace-1"}),
        &mut legacy_rx,
    )
    .await;
    let legacy_find = request(
        &mut actor,
        1,
        4,
        "tab.find",
        json!({"id": "codex-1"}),
        &mut legacy_rx,
    )
    .await;
    let modern_list = request(
        &mut actor,
        2,
        5,
        "tab.list",
        json!({"workspaceId": "workspace-1"}),
        &mut modern_rx,
    )
    .await;
    let modern_find = request(
        &mut actor,
        2,
        6,
        "tab.find",
        json!({"id": "codex-1"}),
        &mut modern_rx,
    )
    .await;

    assert_eq!(legacy_list, json!([]));
    assert_eq!(legacy_find, Value::Null);
    assert_eq!(modern_list, json!([tab.clone()]));
    assert_eq!(modern_find, json!(tab.clone()));
    assert_eq!(
        actor
            .runtime_store
            .find_workspace_tab("codex-1")
            .await
            .unwrap(),
        Some(tab),
        "compatibility projection must not rewrite the stored Codex tab",
    );
}

#[tokio::test]
async fn tab_reads_hide_mobile_emulator_from_legacy_desktop_clients() {
    let dir = tempfile::tempdir().unwrap();
    let (legacy_handle, mut legacy_rx) = ClientHandle::test_channels();
    let (modern_handle, mut modern_rx) = ClientHandle::test_channels();
    let (mobile_handle, mut mobile_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(legacy_handle)),
            (2, local_client(modern_handle)),
            (3, mobile_client(mobile_handle, "phone")),
        ]),
        HashMap::new(),
    )
    .await;
    let tab = emulator_tab();
    actor
        .runtime_store
        .upsert_workspace_tab(tab.clone())
        .await
        .unwrap();

    request(
        &mut actor,
        1,
        1,
        "hello",
        json!({
            "protocolVersion": PROTOCOL_VERSION,
            "token": "token",
        }),
        &mut legacy_rx,
    )
    .await;
    request(
        &mut actor,
        2,
        2,
        "hello",
        json!({
            "protocolVersion": PROTOCOL_VERSION,
            "token": "token",
            "supportedTabKinds": [MOBILE_EMULATOR_TAB_KIND],
        }),
        &mut modern_rx,
    )
    .await;

    let legacy_list = request(
        &mut actor,
        1,
        3,
        "tab.list",
        json!({"workspaceId": "workspace-1"}),
        &mut legacy_rx,
    )
    .await;
    let legacy_find = request(
        &mut actor,
        1,
        4,
        "tab.find",
        json!({"id": "emulator-1"}),
        &mut legacy_rx,
    )
    .await;
    let modern_list = request(
        &mut actor,
        2,
        5,
        "tab.list",
        json!({"workspaceId": "workspace-1"}),
        &mut modern_rx,
    )
    .await;
    let modern_find = request(
        &mut actor,
        2,
        6,
        "tab.find",
        json!({"id": "emulator-1"}),
        &mut modern_rx,
    )
    .await;
    let mobile_list = request(
        &mut actor,
        3,
        7,
        "tab.list",
        json!({"workspaceId": "workspace-1"}),
        &mut mobile_rx,
    )
    .await;
    let mobile_find = request(
        &mut actor,
        3,
        8,
        "tab.find",
        json!({"id": "emulator-1"}),
        &mut mobile_rx,
    )
    .await;

    assert_eq!(legacy_list, json!([]));
    assert_eq!(legacy_find, Value::Null);
    assert_eq!(modern_list, json!([tab.clone()]));
    assert_eq!(modern_find, json!(tab.clone()));
    assert_eq!(mobile_list, json!([tab.clone()]));
    assert_eq!(mobile_find, json!(tab.clone()));
    assert_eq!(
        actor
            .runtime_store
            .find_workspace_tab("emulator-1")
            .await
            .unwrap(),
        Some(tab),
        "wire compatibility must not rewrite the stored record",
    );
}

#[tokio::test]
async fn status_advertises_additive_capabilities_without_a_protocol_version_change() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;

    let status = request(&mut actor, 1, 1, "status.get", json!({}), &mut receiver).await;

    assert_eq!(status["protocolVersion"], PROTOCOL_VERSION);
    assert_eq!(
        status["runtimeHostVersion"],
        crate::terminal_host::runtime_build_info::version()
    );
    assert_eq!(
        status["runtimeHostCommit"],
        crate::terminal_host::runtime_build_info::build().unwrap_or("unknown")
    );
    let capabilities = status["runtimeCapabilities"].as_array().unwrap();
    for capability in [
        RUNTIME_HOST_ACCOUNT_CAPABILITY,
        RUNTIME_HOST_CLOUD_PUSH_CAPABILITY,
        RUNTIME_HOST_CODEX_SESSIONS_CAPABILITY,
        RUNTIME_HOST_CODEX_TURN_POLICY_CAPABILITY,
        RUNTIME_HOST_CODEX_GOALS_CAPABILITY,
        RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY,
        RUNTIME_HOST_MOBILE_EMULATOR_CAPABILITY,
    ] {
        assert!(capabilities.contains(&json!(capability)));
    }
    assert_eq!(status["activePushSubscriptions"], 0);
}

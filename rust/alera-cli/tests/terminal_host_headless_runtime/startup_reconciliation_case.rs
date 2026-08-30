use std::time::{Duration, Instant};

use alera_core::runtime::{RuntimeStore, Workspace, WorkspaceTabRecord};
use serde_json::{json, Value};

use super::{connect, read_response, send, spawn_host, workspace_payload};

#[test]
fn runtime_start_reconciles_persisted_spawn_on_create_tabs() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("reconciled.txt");
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        let workspace: Workspace =
            serde_json::from_value(workspace_payload("reconcile-workspace", dir.path())).unwrap();
        store.upsert_workspace(workspace).await.unwrap();
        let tab: WorkspaceTabRecord = serde_json::from_value(json!({
            "id": "reconcile-tab", "workspaceId": "reconcile-workspace", "kind": "terminal",
            "title": "Reconcile Terminal", "createdAt": "2026-07-19T00:00:00Z",
            "updatedAt": "2026-07-19T00:00:00Z", "payload": {
                "terminalSessionId": "reconcile-session",
                "initialCommand": format!("printf RESTORED > {}; exit", marker.display()),
                "spawnOnCreate": true
            }
        }))
        .unwrap();
        store.upsert_workspace_tab(tab).await.unwrap();
    });

    let token = "reconcile-spawn-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let deadline = Instant::now() + Duration::from_secs(10);
    while !std::fs::read_to_string(&marker).is_ok_and(|value| value == "RESTORED") {
        assert!(
            Instant::now() < deadline,
            "persisted command was never executed"
        );
        std::thread::sleep(Duration::from_millis(25));
    }

    let (mut writer, mut reader) = connect(port, token);
    // The marker is written before shell exit and asynchronous tab cleanup.
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        send(
            &mut writer,
            json!({"id": 1, "type": "tab.find", "payload": {"id": "reconcile-tab"}}),
        );
        let response = read_response(&mut reader, 1);
        assert_eq!(response["ok"], json!(true));
        if response["payload"] == Value::Null {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "exited startup tab was not removed"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}

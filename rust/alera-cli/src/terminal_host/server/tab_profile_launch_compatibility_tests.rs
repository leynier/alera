use std::collections::HashMap;

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::json;

use crate::terminal_host::client::ClientHandle;

use super::actor_test_harness::{local_client, test_actor};
use super::tab_compatibility_tests::request;

fn prompt_delivery_tab() -> WorkspaceTabRecord {
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
            "agentProfileLaunchV1": {
                "version": 1,
                "launch": {"kind": "command", "command": "fx"},
            },
            "initialPrompt": "durable bootstrap",
            "pendingAgentPrompt": {
                "agent": "fx",
                "prompt": "durable bootstrap",
            },
        }),
    }
}

#[tokio::test]
async fn tab_projections_redact_durable_and_pending_prompts_but_not_storage() {
    let dir = tempfile::tempdir().unwrap();
    let (local_handle, mut local_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(local_handle))]),
        HashMap::new(),
    )
    .await;
    let tab = prompt_delivery_tab();
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();

    let listed = request(
        &mut actor,
        1,
        1,
        "tab.list",
        json!({"workspaceId": "workspace-1"}),
        &mut local_rx,
    )
    .await;
    let found = request(
        &mut actor,
        1,
        2,
        "tab.find",
        json!({"id": "terminal-1"}),
        &mut local_rx,
    )
    .await;

    let mut renamed = found.clone();
    renamed["title"] = json!("Renamed from projection");
    renamed["payload"]["agentProfileLaunchV1"]["launch"]["command"] = json!("tampered");
    let upserted = request(&mut actor, 1, 3, "tab.upsert", renamed, &mut local_rx).await;

    for payload in [
        &listed[0]["payload"],
        &found["payload"],
        &upserted["payload"],
    ] {
        assert!(payload.get("initialPrompt").is_none());
        assert!(payload.get("pendingAgentPrompt").is_none());
    }
    let stored = actor
        .runtime_store
        .find_workspace_tab("terminal-1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(stored.title, "Renamed from projection");
    assert_eq!(
        stored.payload["agentProfileLaunchV1"]["launch"]["command"],
        "fx"
    );
    assert_eq!(stored.payload["initialPrompt"], "durable bootstrap");
    assert_eq!(
        stored.payload["pendingAgentPrompt"]["prompt"],
        "durable bootstrap"
    );
}

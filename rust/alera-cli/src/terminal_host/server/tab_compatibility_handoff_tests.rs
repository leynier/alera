use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Value};

use super::{preserve_host_owned_tab_payload, HANDOFF_SOURCE_WORKSPACE_IDS_KEY};

fn tab(payload: Value) -> WorkspaceTabRecord {
    WorkspaceTabRecord {
        id: "terminal-tab".into(),
        workspace_id: "destination".into(),
        kind: "terminal".into(),
        title: "Agent".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        payload,
    }
}

#[test]
fn stale_client_rename_preserves_handoff_hook_history() {
    let stored = tab(json!({"handoffSourceWorkspaceIds": ["main", "child"]}));
    let mut incoming = tab(json!({"manualTitle": true}));
    incoming.title = "Renamed Agent".into();

    preserve_host_owned_tab_payload(&stored, &mut incoming);

    assert_eq!(
        incoming.payload[HANDOFF_SOURCE_WORKSPACE_IDS_KEY],
        json!(["main", "child"])
    );
    assert_eq!(incoming.title, "Renamed Agent");
}

#[test]
fn client_cannot_replace_handoff_hook_history() {
    let stored = tab(json!({"handoffSourceWorkspaceIds": ["main"]}));
    let mut incoming = tab(json!({
        "handoffSourceWorkspaceIds": ["unrelated-workspace"],
        "terminalPulse": true
    }));

    preserve_host_owned_tab_payload(&stored, &mut incoming);

    assert_eq!(
        incoming.payload[HANDOFF_SOURCE_WORKSPACE_IDS_KEY],
        json!(["main"])
    );
    assert_eq!(incoming.payload["terminalPulse"], true);
}

#[test]
fn client_cannot_create_handoff_hook_history_on_an_unmoved_tab() {
    let stored = tab(json!({"agentType": "codex"}));
    let mut incoming = tab(json!({
        "agentType": "codex",
        "handoffSourceWorkspaceIds": ["unrelated-workspace"]
    }));

    preserve_host_owned_tab_payload(&stored, &mut incoming);

    assert!(incoming
        .payload
        .get(HANDOFF_SOURCE_WORKSPACE_IDS_KEY)
        .is_none());
    assert_eq!(incoming.payload["agentType"], "codex");
}

#[tokio::test]
async fn stale_tab_upsert_cannot_move_a_transferred_tab_back_to_its_source() {
    use std::collections::HashMap;
    use std::time::Duration;

    use super::super::actor_test_harness::{local_client, test_actor};
    use crate::terminal_host::client::ClientHandle;

    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let stored = tab(json!({"handoffSourceWorkspaceIds": ["source"]}));
    actor
        .runtime_store
        .upsert_workspace_tab(stored.clone())
        .await
        .unwrap();
    let mut stale = stored.clone();
    stale.workspace_id = "source".into();
    stale.title = "Stale title".into();

    actor
        .handle_line(
            1,
            json!({
                "id": 717,
                "type": "tab.upsert",
                "payload": stale,
            })
            .to_string(),
        )
        .await;

    let response = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let response = receiver.recv().await.unwrap().as_json().unwrap();
            if response["id"] == 717 {
                break response;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(response["ok"], false);
    let saved = actor
        .runtime_store
        .find_workspace_tab(&stored.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(saved.workspace_id, "destination");
    assert_eq!(saved.title, "Agent");
    assert_eq!(
        saved.payload[HANDOFF_SOURCE_WORKSPACE_IDS_KEY],
        json!(["source"])
    );
}

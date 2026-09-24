use std::collections::HashMap;

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::terminal_host::client::{ClientFrame, ClientHandle};

use super::actor_test_harness::{local_client, test_actor};
use super::{ServerActor, ServerCommand};

fn workspace_tab(tab_id: &str, workspace_id: &str, kind: &str) -> WorkspaceTabRecord {
    let now = Utc::now();
    WorkspaceTabRecord {
        id: tab_id.to_string(),
        workspace_id: workspace_id.to_string(),
        kind: kind.to_string(),
        title: "Tab".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({}),
    }
}

async fn actor_with_tab(
    dir: &tempfile::TempDir,
    tab: &WorkspaceTabRecord,
) -> (ServerActor, UnboundedReceiver<ClientFrame>) {
    let (handle, receiver) = ClientHandle::test_channels();
    let client = local_client(handle);
    let actor = test_actor(dir, HashMap::from([(1, client)]), HashMap::new()).await;
    actor
        .runtime_store
        .upsert_workspace_tab(tab.clone())
        .await
        .unwrap();
    (actor, receiver)
}

async fn tab_exists(actor: &ServerActor, tab_id: &str) -> bool {
    actor
        .runtime_store
        .find_workspace_tab(tab_id)
        .await
        .unwrap()
        .is_some()
}

async fn request(
    actor: &mut ServerActor,
    receiver: &mut UnboundedReceiver<ClientFrame>,
    inbox_receiver: &mut UnboundedReceiver<ServerCommand>,
    request_type: &str,
    payload: Value,
) -> Value {
    actor
        .handle_line(
            1,
            json!({
                "id": 1,
                "type": request_type,
                "payload": payload,
            })
            .to_string(),
        )
        .await;
    loop {
        tokio::select! {
            command = inbox_receiver.recv() => {
                actor.handle(command.expect("the completion should be delivered")).await;
            }
            frame = receiver.recv() => {
                let response = frame
                    .expect("the response should be delivered")
                    .as_json()
                    .expect("the response should be JSON");
                if response["id"] == 1 {
                    return response;
                }
            }
        }
    }
}

#[tokio::test]
async fn tab_removal_deletes_the_record() {
    let dir = tempfile::tempdir().unwrap();
    let tab = workspace_tab("editor-tab", "workspace", "editor");
    let (mut actor, mut receiver) = actor_with_tab(&dir, &tab).await;
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    let response = request(
        &mut actor,
        &mut receiver,
        &mut inbox_receiver,
        "tab.remove",
        json!({"id": tab.id}),
    )
    .await;

    assert_eq!(response["ok"], true);
    assert!(!tab_exists(&actor, "editor-tab").await);
}

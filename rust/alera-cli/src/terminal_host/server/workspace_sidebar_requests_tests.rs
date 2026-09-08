use std::collections::HashMap;

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::json;

use super::actor_test_harness::{mobile_client, test_actor};
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::session::Session;

#[tokio::test]
async fn sidebar_agent_presence_includes_tab_title() {
    let dir = tempfile::tempdir().unwrap();
    let (mobile, _events) = ClientHandle::test_channels();
    let mut session = Session::driver_test_stub("session-1", 80, 24);
    session.workspace_id = "workspace-1".into();
    session.tab_id = "tab-1".into();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(2, mobile_client(mobile, "phone"))]),
        HashMap::from([("session-1".into(), session)]),
    )
    .await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab-1".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Map Monetization".into(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        })
        .await
        .unwrap();
    actor
        .agent_presence
        .update("session-1", "codex".into(), AgentPresenceState::Working);

    let snapshot = actor.workspace_sidebar_snapshot(2).await.unwrap();
    let presence = &snapshot["agentPresence"][0];
    assert_eq!(presence["tabId"], "tab-1");
    assert_eq!(presence["title"], "Map Monetization");
    assert_eq!(presence["agentType"], "codex");
    assert_eq!(presence["lastAssistantMessage"], serde_json::Value::Null);

    let listed = actor.agent_presence_items_with_titles().await.unwrap();
    assert_eq!(listed[0]["title"], "Map Monetization");
}

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

#[tokio::test]
async fn sidebar_snapshot_falls_back_to_the_first_primary_candidate() {
    let dir = tempfile::tempdir().unwrap();
    let (mobile, _events) = ClientHandle::test_channels();
    let actor = test_actor(
        &dir,
        HashMap::from([(2, mobile_client(mobile, "phone"))]),
        HashMap::new(),
    )
    .await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "setup".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Setup".into(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "primary".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Codex".into(),
            created_at: now + chrono::Duration::seconds(1),
            updated_at: now,
            payload: json!({}),
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "side".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Review".into(),
            created_at: now + chrono::Duration::seconds(2),
            updated_at: now,
            payload: json!({}),
        })
        .await
        .unwrap();

    let snapshot = actor.workspace_sidebar_snapshot(2).await.unwrap();
    assert_eq!(
        snapshot["workspaceMainTabIds"],
        json!({ "workspace-1": ["primary"] })
    );
}

#[tokio::test]
async fn sidebar_hides_voice_home_activity_presence_and_terminal_counts() {
    let dir = tempfile::tempdir().unwrap();
    let (mobile, _events) = ClientHandle::test_channels();
    let mut session = Session::driver_test_stub("home-session", 80, 24);
    session.workspace_id = alera_core::runtime::VOICE_HOME_WORKSPACE_ID.into();
    session.tab_id = "home-tab".into();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(2, mobile_client(mobile, "phone"))]),
        HashMap::from([("home-session".into(), session)]),
    )
    .await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "home-tab".into(),
            workspace_id: alera_core::runtime::VOICE_HOME_WORKSPACE_ID.into(),
            kind: "terminal".into(),
            title: "Voice".into(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        })
        .await
        .unwrap();
    actor
        .agent_presence
        .update("home-session", "codex".into(), AgentPresenceState::Working);
    actor
        .runtime_store
        .record_workspace_activity_batch(std::collections::BTreeMap::from([(
            alera_core::runtime::VOICE_HOME_WORKSPACE_ID.to_string(),
            now,
        )]))
        .await
        .unwrap();

    let snapshot = actor.workspace_sidebar_snapshot(2).await.unwrap();
    assert!(snapshot["agentPresence"].as_array().unwrap().is_empty());
    assert!(snapshot["activity"]
        .as_object()
        .unwrap()
        .get(alera_core::runtime::VOICE_HOME_WORKSPACE_ID)
        .is_none());
    assert!(snapshot["terminalTabCountByWorkspaceId"]
        .as_object()
        .unwrap()
        .get(alera_core::runtime::VOICE_HOME_WORKSPACE_ID)
        .is_none());
    assert!(snapshot["workspaceMainTabIds"]
        .as_object()
        .unwrap()
        .get(alera_core::runtime::VOICE_HOME_WORKSPACE_ID)
        .is_none());
}

#[tokio::test]
async fn sidebar_lists_a_slept_workspace_without_terminals() {
    let dir = tempfile::tempdir().unwrap();
    let (mobile, _events) = ClientHandle::test_channels();
    let mut session = Session::driver_test_stub("slept-session", 80, 24);
    session.workspace_id = "workspace-1".into();
    session.tab_id = "slept-tab".into();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(2, mobile_client(mobile, "phone"))]),
        HashMap::from([("slept-session".into(), session)]),
    )
    .await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "slept-tab".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Codex".into(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        })
        .await
        .unwrap();
    actor
        .agent_presence
        .update("slept-session", "codex".into(), AgentPresenceState::Done);
    actor
        .runtime_store
        .record_workspace_sleep("workspace-1")
        .await
        .unwrap();

    let snapshot = actor.workspace_sidebar_snapshot(2).await.unwrap();
    assert!(snapshot["agentPresence"].as_array().unwrap().is_empty());
    assert!(snapshot["terminalTabCountByWorkspaceId"]
        .as_object()
        .unwrap()
        .get("workspace-1")
        .is_none());
    assert_eq!(
        snapshot["sleptTabIdsByWorkspaceId"],
        json!({ "workspace-1": ["slept-tab"] })
    );
}

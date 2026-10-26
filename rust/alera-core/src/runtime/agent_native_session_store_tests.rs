use chrono::{Duration, Utc};
use serde_json::json;

use super::checkout_store_tests::{fixture, workspace};
use super::store::LOCAL_HOST_ID;
use super::{AgentNativeSessionRecord, WorkspaceKind};

fn record(workspace_id: &str, session_id: &str) -> AgentNativeSessionRecord {
    AgentNativeSessionRecord {
        workspace_id: workspace_id.into(),
        agent_type: "claude".into(),
        session_id: session_id.into(),
        ccs_profile: None,
        cwd: Some("/repo/feature".into()),
        tab_id: Some("tab".into()),
        settings: Some(json!({"model": "opus"})),
        first_seen_at: Utc::now(),
        last_seen_at: Utc::now(),
    }
}

#[tokio::test]
async fn a_refresh_keeps_fields_the_new_observation_omits() {
    let (_dir, store, _project) = fixture().await;
    store
        .insert_workspace(workspace(
            "feature",
            LOCAL_HOST_ID,
            "/repo/feature",
            WorkspaceKind::Linked,
        ))
        .await
        .unwrap();
    let first = record("feature", "sess-1");
    store.record_agent_native_session(&first).await.unwrap();
    let later = AgentNativeSessionRecord {
        ccs_profile: Some("work".into()),
        cwd: None,
        tab_id: None,
        settings: None,
        first_seen_at: first.first_seen_at + Duration::minutes(5),
        last_seen_at: first.last_seen_at + Duration::minutes(5),
        ..first.clone()
    };
    store.record_agent_native_session(&later).await.unwrap();
    let rows = store.list_agent_native_sessions("feature").await.unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].ccs_profile.as_deref(), Some("work"));
    assert_eq!(rows[0].cwd.as_deref(), Some("/repo/feature"));
    assert_eq!(rows[0].tab_id.as_deref(), Some("tab"));
    assert_eq!(rows[0].settings, Some(json!({"model": "opus"})));
    assert_eq!(
        rows[0].first_seen_at.timestamp_millis(),
        first.first_seen_at.timestamp_millis()
    );
    assert_eq!(
        rows[0].last_seen_at.timestamp_millis(),
        later.last_seen_at.timestamp_millis()
    );
}

#[tokio::test]
async fn ledger_rows_outlive_the_workspace_until_pruned() {
    let (_dir, store, _project) = fixture().await;
    store
        .insert_workspace(workspace(
            "feature",
            LOCAL_HOST_ID,
            "/repo/feature",
            WorkspaceKind::Linked,
        ))
        .await
        .unwrap();
    store
        .record_agent_native_session(&record("feature", "sess-1"))
        .await
        .unwrap();
    store.remove_workspace("feature", true).await.unwrap();
    assert_eq!(
        store
            .list_agent_native_sessions("feature")
            .await
            .unwrap()
            .len(),
        1
    );
    assert_eq!(store.prune_orphan_agent_native_sessions().await.unwrap(), 1);
    assert!(store
        .list_agent_native_sessions("feature")
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn sessions_of_other_live_workspaces_are_listed_as_outside() {
    let (_dir, store, _project) = fixture().await;
    for (id, path) in [("feature", "/repo/feature"), ("other", "/repo/other")] {
        store
            .insert_workspace(workspace(id, LOCAL_HOST_ID, path, WorkspaceKind::Linked))
            .await
            .unwrap();
    }
    for (workspace_id, session_id) in [
        ("feature", "shared"),
        ("feature", "private"),
        ("other", "shared"),
    ] {
        store
            .record_agent_native_session(&record(workspace_id, session_id))
            .await
            .unwrap();
    }
    assert_eq!(
        store
            .agent_native_sessions_outside("feature")
            .await
            .unwrap(),
        vec![("claude".to_string(), "shared".to_string())]
    );
    store.remove_workspace("other", true).await.unwrap();
    assert!(store
        .agent_native_sessions_outside("feature")
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn tabs_bound_before_the_ledger_seed_it_on_open() {
    let (dir, store, _project) = fixture().await;
    store
        .insert_workspace(workspace(
            "feature",
            LOCAL_HOST_ID,
            "/repo/feature",
            WorkspaceKind::Linked,
        ))
        .await
        .unwrap();
    for (id, payload) in [
        (
            "bound",
            json!({"agentNativeSessionId": "sess-1", "agentNativeSessionAgent": "codex",
            "agentNativeSessionSettings": {"model": "gpt-5"}}),
        ),
        ("plain", json!({"agentType": "codex"})),
    ] {
        store
            .upsert_workspace_tab(super::WorkspaceTabRecord {
                id: id.into(),
                workspace_id: "feature".into(),
                kind: "terminal".into(),
                title: id.into(),
                created_at: Utc::now(),
                updated_at: Utc::now(),
                payload,
            })
            .await
            .unwrap();
    }
    drop(store);
    let store = super::RuntimeStore::open(dir.path()).await.unwrap();
    let rows = store.list_agent_native_sessions("feature").await.unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].agent_type, "codex");
    assert_eq!(rows[0].session_id, "sess-1");
    assert_eq!(rows[0].tab_id.as_deref(), Some("bound"));
    assert_eq!(rows[0].settings, Some(json!({"model": "gpt-5"})));
}

#[tokio::test]
async fn a_workspace_transfer_moves_the_ledger_with_the_tabs() {
    let (_dir, store, _project) = fixture().await;
    let main = workspace("main", LOCAL_HOST_ID, "/repo", WorkspaceKind::Main);
    let child = workspace("child", LOCAL_HOST_ID, "/repo/child", WorkspaceKind::Linked);
    store.insert_workspace(main.clone()).await.unwrap();
    store.insert_workspace(child.clone()).await.unwrap();
    store
        .record_agent_native_session(&record("child", "sess-1"))
        .await
        .unwrap();
    store
        .record_agent_native_session(&record("child", "both"))
        .await
        .unwrap();
    store
        .record_agent_native_session(&AgentNativeSessionRecord {
            tab_id: Some("main-tab".into()),
            ..record("main", "both")
        })
        .await
        .unwrap();
    store
        .transfer_workspace_contents(&child, &main)
        .await
        .unwrap();
    assert!(store
        .list_agent_native_sessions("child")
        .await
        .unwrap()
        .is_empty());
    let moved = store.list_agent_native_sessions("main").await.unwrap();
    assert_eq!(moved.len(), 2);
    let both = moved.iter().find(|row| row.session_id == "both").unwrap();
    assert_eq!(both.tab_id.as_deref(), Some("main-tab"));
}

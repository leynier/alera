use chrono::{Duration, Utc};

use super::{
    RuntimeAgentQuotaSettings, RuntimeStore, SharedWorkbenchPrefsWriter, SharedWorkbenchSortBy,
    SharedWorkbenchViewPrefs, WorkbenchLayoutRecord, WorkspaceTabRecord,
};

#[tokio::test]
async fn desktop_initializes_shared_prefs_and_mobile_rejects_stale_revision() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let prefs = SharedWorkbenchViewPrefs {
        workspace_sort: SharedWorkbenchSortBy::Activity,
        ..SharedWorkbenchViewPrefs::default()
    };

    let desktop = store
        .update_shared_workbench_view_prefs(
            prefs.clone(),
            Some(0),
            SharedWorkbenchPrefsWriter::Desktop,
        )
        .await
        .unwrap();
    assert!(desktop.desktop_initialized);
    assert_eq!(desktop.revision, 1);

    let error = store
        .update_shared_workbench_view_prefs(prefs, Some(0), SharedWorkbenchPrefsWriter::Mobile)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("changed on desktop"));
}

#[tokio::test]
async fn workspace_activity_keeps_the_newest_timestamp() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let newer = Utc::now();
    let older = newer - Duration::minutes(1);

    store
        .record_workspace_activity("workspace-1", newer)
        .await
        .unwrap();
    store
        .record_workspace_activity("workspace-1", older)
        .await
        .unwrap();

    let recorded = store.list_workspace_activity().await.unwrap();
    assert_eq!(
        recorded.get("workspace-1").unwrap().timestamp_millis(),
        newer.timestamp_millis(),
    );
}

#[tokio::test]
async fn workspace_removal_confirmation_defaults_to_true() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();

    assert!(
        store
            .runtime_settings()
            .await
            .unwrap()
            .confirm_workspace_removal
    );
}

#[tokio::test]
async fn portable_settings_round_trip_project_confirmation_and_empty_quotas() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();

    store.set_confirm_project_removal(false).await.unwrap();
    store
        .set_agent_quota_settings(RuntimeAgentQuotaSettings {
            enabled_providers: Vec::new(),
            ..RuntimeAgentQuotaSettings::default()
        })
        .await
        .unwrap();

    let settings = store.runtime_settings().await.unwrap();
    assert!(!settings.confirm_project_removal);
    assert!(settings.agent_quotas.enabled_providers.is_empty());
}

#[tokio::test]
async fn tab_rename_preserves_payload_and_marks_manual_title() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "editor".to_string(),
            title: "Notes".to_string(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({"path": "readme.md"}),
        })
        .await
        .unwrap();

    let renamed = store
        .rename_workspace_tab("tab-1", "  Plan  ")
        .await
        .unwrap();

    assert_eq!(renamed.title, "Plan");
    assert_eq!(renamed.payload["path"], "readme.md");
    assert_eq!(renamed.payload["manualTitle"], true);
}

#[tokio::test]
async fn sleeping_workspace_removes_its_tabs_and_layout_only() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    for (id, workspace_id, kind) in [
        ("terminal-1", "workspace-1", "terminal"),
        ("editor-1", "workspace-1", "editor"),
        ("terminal-2", "workspace-2", "terminal"),
    ] {
        store
            .upsert_workspace_tab(WorkspaceTabRecord {
                id: id.to_string(),
                workspace_id: workspace_id.to_string(),
                kind: kind.to_string(),
                title: id.to_string(),
                created_at: now,
                updated_at: now,
                payload: serde_json::json!({}),
            })
            .await
            .unwrap();
    }
    store
        .upsert_workbench_layout(WorkbenchLayoutRecord {
            workspace_id: "workspace-1".to_string(),
            data: serde_json::json!({"activeTabId": "terminal-1"}),
        })
        .await
        .unwrap();
    store
        .upsert_workbench_layout(WorkbenchLayoutRecord {
            workspace_id: "workspace-2".to_string(),
            data: serde_json::json!({"activeTabId": "terminal-2"}),
        })
        .await
        .unwrap();

    store.sleep_workspace("workspace-1").await.unwrap();

    assert!(store
        .list_workspace_tabs("workspace-1")
        .await
        .unwrap()
        .is_empty());
    assert!(store
        .find_workbench_layout("workspace-1")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .list_workspace_tabs("workspace-2")
            .await
            .unwrap()
            .len(),
        1
    );
    assert!(store
        .find_workbench_layout("workspace-2")
        .await
        .unwrap()
        .is_some());
}

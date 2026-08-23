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
        show_pinned_workspaces_below: false,
        show_active_workspaces_only: true,
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
    assert!(!desktop.prefs.show_pinned_workspaces_below);
    assert!(desktop.prefs.show_active_workspaces_only);

    let error = store
        .update_shared_workbench_view_prefs(prefs, Some(0), SharedWorkbenchPrefsWriter::Mobile)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("changed on desktop"));
}

#[test]
fn legacy_shared_view_prefs_show_pinned_workspaces_below() {
    let mut encoded = serde_json::to_value(SharedWorkbenchViewPrefs::default()).unwrap();
    encoded
        .as_object_mut()
        .unwrap()
        .remove("showPinnedWorkspacesBelow");

    let restored: SharedWorkbenchViewPrefs = serde_json::from_value(encoded).unwrap();

    assert!(restored.show_pinned_workspaces_below);
    assert!(restored.source_control_root_by_workspace_id.is_empty());
}

#[test]
fn shared_view_prefs_preserve_source_control_roots() {
    let mut prefs = SharedWorkbenchViewPrefs::default();
    prefs
        .source_control_root_by_workspace_id
        .insert("workspace-1".to_string(), "apps/web".to_string());

    let restored: SharedWorkbenchViewPrefs =
        serde_json::from_value(serde_json::to_value(&prefs).unwrap()).unwrap();

    assert_eq!(
        restored
            .source_control_root_by_workspace_id
            .get("workspace-1")
            .map(String::as_str),
        Some("apps/web")
    );
}

#[test]
fn legacy_shared_view_prefs_show_all_workspaces() {
    let mut encoded = serde_json::to_value(SharedWorkbenchViewPrefs::default()).unwrap();
    encoded
        .as_object_mut()
        .unwrap()
        .remove("showActiveWorkspacesOnly");

    let restored: SharedWorkbenchViewPrefs = serde_json::from_value(encoded).unwrap();

    assert!(!restored.show_active_workspaces_only);
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
            selected_claude_profile: "work".to_string(),
            unpinned_quota_keys: vec!["claude:default".to_string(), "codex".to_string()],
            ..RuntimeAgentQuotaSettings::default()
        })
        .await
        .unwrap();

    let settings = store.runtime_settings().await.unwrap();
    assert!(!settings.confirm_project_removal);
    assert!(settings.agent_quotas.enabled_providers.is_empty());
    assert_eq!(settings.agent_quotas.selected_claude_profile, "work");
    assert_eq!(
        settings.agent_quotas.unpinned_quota_keys,
        ["claude:default", "codex"]
    );
}

#[tokio::test]
async fn default_agent_profile_setting_round_trips_and_clears() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();

    store
        .set_default_agent_profile_id(Some("  prof_codex  "))
        .await
        .unwrap();
    assert_eq!(
        store
            .runtime_settings()
            .await
            .unwrap()
            .default_agent_profile_id
            .as_deref(),
        Some("prof_codex")
    );

    store.set_default_agent_profile_id(None).await.unwrap();
    assert_eq!(
        store
            .runtime_settings()
            .await
            .unwrap()
            .default_agent_profile_id,
        None
    );
}

#[tokio::test]
async fn default_agent_profile_setting_round_trips_and_clears() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();

    store
        .set_default_agent_profile_id(Some("  prof_codex  "))
        .await
        .unwrap();
    assert_eq!(
        store
            .runtime_settings()
            .await
            .unwrap()
            .default_agent_profile_id
            .as_deref(),
        Some("prof_codex")
    );

    store.set_default_agent_profile_id(None).await.unwrap();
    assert_eq!(
        store
            .runtime_settings()
            .await
            .unwrap()
            .default_agent_profile_id,
        None
    );
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
async fn workspace_tab_removal_is_idempotent() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "terminal".to_string(),
            title: "Terminal".to_string(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({}),
        })
        .await
        .unwrap();

    store.remove_workspace_tab("tab-1").await.unwrap();
    store.remove_workspace_tab("tab-1").await.unwrap();

    assert!(store.find_workspace_tab("tab-1").await.unwrap().is_none());
}

#[tokio::test]
async fn generic_browser_tab_upsert_sanitizes_or_removes_unsafe_urls() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    let mut tab = WorkspaceTabRecord {
        id: "browser-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: "browser".to_string(),
        title: "Browser".to_string(),
        created_at: now,
        updated_at: now,
        payload: serde_json::json!({
            "browserProfileId": "default",
            "browserUrl": "https://example.com/docs",
            "browserRuntimeTitle": format!(" \u{0}Docs\n{} ", "🚀".repeat(300)),
            "zoom": 1.25,
        }),
    };

    tab = store.upsert_workspace_tab(tab).await.unwrap();
    assert_eq!(tab.payload["browserUrl"], "https://example.com/docs");
    assert_eq!(
        tab.payload["browserRuntimeTitle"].as_str().unwrap().len(),
        super::BROWSER_TITLE_MAX_BYTES
    );
    assert!(!tab.payload["browserRuntimeTitle"]
        .as_str()
        .unwrap()
        .chars()
        .any(char::is_control));
    assert_eq!(tab.payload["zoom"], 1.25);
    let persisted = store
        .find_workspace_tab("browser-1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(persisted.payload, tab.payload);

    tab.payload["browserUrl"] =
        serde_json::json!("https://user:password@example.com/oauth/callback?code=secret#token");
    tab.payload["browserRuntimeTitle"] = serde_json::json!("Private Account");
    tab.title = "Private Account".to_string();
    tab = store.upsert_workspace_tab(tab).await.unwrap();
    assert_eq!(tab.payload["browserUrl"], "https://example.com/");
    assert!(tab.payload.get("browserRuntimeTitle").is_none());
    assert_eq!(tab.title, "Browser");

    tab.payload["browserUrl"] = serde_json::json!("file:///Users/me/private.txt");
    tab = store.upsert_workspace_tab(tab).await.unwrap();
    assert!(tab.payload.get("browserUrl").is_none());
    assert!(store
        .find_workspace_tab("browser-1")
        .await
        .unwrap()
        .unwrap()
        .payload
        .get("browserUrl")
        .is_none());

    tab.payload = serde_json::json!(["https://example.com/?token=secret"]);
    tab = store.upsert_workspace_tab(tab).await.unwrap();
    assert_eq!(tab.payload, serde_json::json!({}));
}

#[tokio::test]
async fn new_sensitive_browser_tabs_cannot_seed_a_page_controlled_title() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();

    let saved = store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "sensitive-browser".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "browser".to_string(),
            title: "Private Account".to_string(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({
                "browserProfileId": "default",
                "browserUrl": "https://example.com/?auth=secret",
                "browserRuntimeTitle": "Private Account",
            }),
        })
        .await
        .unwrap();

    assert_eq!(saved.title, "New Tab");
    assert_eq!(saved.payload["browserUrl"], "https://example.com/");
    assert!(saved.payload.get("browserRuntimeTitle").is_none());
}

#[tokio::test]
async fn browser_payload_normalization_does_not_change_other_tab_kinds() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    let saved = store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "editor-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "editor".to_string(),
            title: "Editor".to_string(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({"browserUrl": "file:///Users/me/private.txt"}),
        })
        .await
        .unwrap();

    assert_eq!(saved.payload["browserUrl"], "file:///Users/me/private.txt");
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

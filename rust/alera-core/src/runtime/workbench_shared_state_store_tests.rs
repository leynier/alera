use chrono::{Duration, Utc};

use super::{
    RuntimeStore, SharedWorkbenchPrefsWriter, SharedWorkbenchSortBy, SharedWorkbenchViewPrefs,
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

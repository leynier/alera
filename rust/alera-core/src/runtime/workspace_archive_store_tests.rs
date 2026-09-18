use chrono::Utc;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::Row;

use super::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
    RUNTIME_DATABASE_FILE_NAME,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn project(id: &str) -> Project {
    let now = Utc::now();
    Project {
        id: id.to_string(),
        name: id.to_string(),
        repo_path: format!("/tmp/{id}"),
        created_at: now,
        updated_at: now,
        kind: ProjectKind::GitRepository,
    }
}

fn workspace(id: &str, project_id: &str) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.to_string(),
        instance_id: format!("inst-{id}"),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: project_id.to_string(),
        name: id.to_string(),
        branch: Some("main".to_string()),
        path: format!("/tmp/{project_id}/{id}"),
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        is_archived: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

#[tokio::test]
async fn workspace_archive_roundtrip_preserves_tabs_and_layout() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("w", "p")).await.unwrap();
    store
        .upsert_workspace_tab(super::WorkspaceTabRecord {
            id: "tab-1".to_string(),
            workspace_id: "w".to_string(),
            kind: "terminal".to_string(),
            title: "tab-1".to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: serde_json::json!({"agentNativeSessionId": "sess-1"}),
        })
        .await
        .unwrap();
    store
        .upsert_workbench_layout(super::WorkbenchLayoutRecord {
            workspace_id: "w".to_string(),
            data: serde_json::json!({"activeTabId": "tab-1"}),
        })
        .await
        .unwrap();

    let archived = store.set_workspace_archived("w", true).await.unwrap();
    assert!(archived.is_archived);
    let unarchived = store.set_workspace_archived("w", false).await.unwrap();
    assert!(!unarchived.is_archived);

    assert_eq!(store.list_workspace_tabs("w").await.unwrap().len(), 1);
    assert!(store.find_workbench_layout("w").await.unwrap().is_some());
    assert!(store
        .set_workspace_archived("missing", true)
        .await
        .unwrap_err()
        .to_string()
        .contains("workspace not found"));
}

#[tokio::test]
async fn workspace_archive_column_is_added_to_legacy_runtime_databases() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(RUNTIME_DATABASE_FILE_NAME);
    let pool = SqlitePoolOptions::new()
        .connect_with(
            SqliteConnectOptions::new()
                .filename(path)
                .create_if_missing(true),
        )
        .await
        .unwrap();
    sqlx::query(
        "CREATE TABLE workspaces (
            id TEXT PRIMARY KEY,
            instanceId TEXT NOT NULL,
            hostId TEXT NOT NULL,
            projectId TEXT NOT NULL,
            name TEXT NOT NULL,
            branch TEXT,
            path TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            kind TEXT NOT NULL,
            status TEXT NOT NULL,
            sourceBranch TEXT,
            reusesExistingBranch INTEGER NOT NULL DEFAULT 0,
            isPinned INTEGER NOT NULL DEFAULT 0
        )",
    )
    .execute(&pool)
    .await
    .unwrap();
    pool.close().await;

    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let columns = sqlx::query("PRAGMA table_info(workspaces)")
        .fetch_all(store.pool())
        .await
        .unwrap();

    assert!(columns.iter().any(|row| {
        row.try_get::<String, _>("name")
            .is_ok_and(|name| name == "isArchived")
    }));
}

use chrono::Utc;

use super::{RuntimeStore, WorkspaceTabRecord};

// This trigger belongs to workspaceTabs, so dropping codexChatState leaves it behind.
const LEGACY_CODEX_SCHEMA: &[&str] = &[
    "CREATE TABLE codexChatState (threadId TEXT PRIMARY KEY, tabId TEXT NOT NULL, revision INTEGER NOT NULL, stateJson TEXT NOT NULL)",
    "CREATE INDEX codexChatStateTab ON codexChatState(tabId)",
    "CREATE TRIGGER codexChatStateDeleteTab AFTER DELETE ON workspaceTabs BEGIN DELETE FROM codexChatState WHERE tabId = OLD.id; END",
];

#[tokio::test]
async fn opening_another_store_preserves_state_used_by_the_running_host() {
    let dir = tempfile::tempdir().unwrap();
    let host_store = RuntimeStore::open(dir.path()).await.unwrap();
    for statement in LEGACY_CODEX_SCHEMA {
        sqlx::query(*statement)
            .execute(host_store.pool())
            .await
            .unwrap();
    }
    let pending_state = r#"{"messages":[{"status":"queued"}]}"#;
    sqlx::query("INSERT INTO codexChatState VALUES ('thread-1', 'legacy-codex', 1, ?)")
        .bind(pending_state)
        .execute(host_store.pool())
        .await
        .unwrap();

    let client_store = RuntimeStore::open(dir.path()).await.unwrap();
    let state: String =
        sqlx::query_scalar("SELECT stateJson FROM codexChatState WHERE threadId = 'thread-1'")
            .fetch_one(host_store.pool())
            .await
            .unwrap();
    assert_eq!(state, pending_state);
    let trigger_count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM sqlite_master WHERE name = 'codexChatStateDeleteTab'",
    )
    .fetch_one(host_store.pool())
    .await
    .unwrap();
    assert_eq!(trigger_count, 1);
    client_store.pool().close().await;
    host_store.pool().close().await;
}

async fn verify_legacy_codex_migration(table_already_dropped: bool) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    let terminal = WorkspaceTabRecord {
        id: "terminal-1".into(),
        workspace_id: "workspace-1".into(),
        kind: "terminal".into(),
        title: "Codex".into(),
        created_at: now,
        updated_at: now,
        payload: serde_json::json!({"initialCommand": "codex"}),
    };
    store.upsert_workspace_tab(terminal.clone()).await.unwrap();
    let persisted_terminal = store
        .find_workspace_tab(&terminal.id)
        .await
        .unwrap()
        .unwrap();
    for kind in ["mobileEmulator", "browser", "codex"] {
        store
            .upsert_workspace_tab(WorkspaceTabRecord {
                id: format!("legacy-{kind}"),
                kind: kind.into(),
                ..terminal.clone()
            })
            .await
            .unwrap();
    }
    for statement in LEGACY_CODEX_SCHEMA {
        sqlx::query(*statement).execute(store.pool()).await.unwrap();
    }
    sqlx::query("INSERT INTO codexChatState VALUES ('thread-1', 'legacy-codex', 1, '{}')")
        .execute(store.pool())
        .await
        .unwrap();
    if table_already_dropped {
        sqlx::query("DROP TABLE codexChatState")
            .execute(store.pool())
            .await
            .unwrap();
    }
    store.pool().close().await;

    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store.retire_removed_features().await.unwrap();
    let tabs = store.list_workspace_tabs("workspace-1").await.unwrap();
    assert_eq!(tabs.len(), 1);
    assert_eq!(
        serde_json::to_value(&tabs[0]).unwrap(),
        serde_json::to_value(&persisted_terminal).unwrap()
    );
    let legacy_objects: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM sqlite_master WHERE name IN ('codexChatState', 'codexChatStateTab', 'codexChatStateDeleteTab')",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(legacy_objects, 0);
    store.pool().close().await;

    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store.retire_removed_features().await.unwrap();
    assert_eq!(
        store
            .list_workspace_tabs("workspace-1")
            .await
            .unwrap()
            .len(),
        1
    );
    store.remove_workspace_tab(&terminal.id).await.unwrap();
    assert!(store
        .list_workspace_tabs("workspace-1")
        .await
        .unwrap()
        .is_empty());
    store.pool().close().await;
}

#[tokio::test]
async fn legacy_codex_migration_allows_startup_cleanup() {
    verify_legacy_codex_migration(false).await;
}

#[tokio::test]
async fn legacy_codex_migration_recovers_after_failed_feature_cut_startup() {
    verify_legacy_codex_migration(true).await;
}

#[tokio::test]
async fn legacy_codex_migration_recovers_with_no_workspace_tabs() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    for statement in LEGACY_CODEX_SCHEMA {
        sqlx::query(*statement).execute(store.pool()).await.unwrap();
    }
    sqlx::query("DROP TABLE codexChatState")
        .execute(store.pool())
        .await
        .unwrap();
    store.pool().close().await;

    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store.retire_removed_features().await.unwrap();
    assert!(store
        .list_workspace_tabs("workspace-1")
        .await
        .unwrap()
        .is_empty());
    store.pool().close().await;
}

#[tokio::test]
async fn feature_retirement_rolls_back_schema_and_data_when_tab_cleanup_fails() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    for statement in LEGACY_CODEX_SCHEMA {
        sqlx::query(*statement).execute(store.pool()).await.unwrap();
    }
    sqlx::query("INSERT INTO codexChatState VALUES ('thread-1', 'legacy-codex', 1, '{}')")
        .execute(store.pool())
        .await
        .unwrap();
    let now = Utc::now();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "legacy-codex".into(),
            workspace_id: "workspace-1".into(),
            kind: "codex".into(),
            title: "Pending Chat".into(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({"threadId": "thread-1"}),
        })
        .await
        .unwrap();
    sqlx::query(
        "CREATE TRIGGER failFeatureRetirement BEFORE DELETE ON workspaceTabs BEGIN SELECT RAISE(ABORT, 'blocked retirement'); END",
    )
    .execute(store.pool())
    .await
    .unwrap();

    let error = store.retire_removed_features().await.unwrap_err();
    assert!(error.to_string().contains("blocked retirement"));
    let state: String = sqlx::query_scalar("SELECT stateJson FROM codexChatState")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(state, "{}");
    let objects: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM sqlite_master WHERE name IN ('codexChatState', 'codexChatStateTab', 'codexChatStateDeleteTab')",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(objects, 3);
    assert!(store
        .find_workspace_tab("legacy-codex")
        .await
        .unwrap()
        .is_some());

    sqlx::query("DROP TRIGGER failFeatureRetirement")
        .execute(store.pool())
        .await
        .unwrap();
    store.retire_removed_features().await.unwrap();
    assert!(store
        .find_workspace_tab("legacy-codex")
        .await
        .unwrap()
        .is_none());
    store.pool().close().await;
}

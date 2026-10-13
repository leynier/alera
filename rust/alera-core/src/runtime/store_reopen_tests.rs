use sqlx::Row;

use super::RuntimeStore;

async fn data_version(conn: &mut sqlx::SqliteConnection) -> i64 {
    sqlx::query("PRAGMA data_version")
        .fetch_one(&mut *conn)
        .await
        .unwrap()
        .get(0)
}

/// CLI commands open the store next to a live runtime. A commit on that open
/// invalidates the runtime's read snapshot, and a deferred transaction that
/// then writes fails with SQLITE_BUSY_SNAPSHOT, which the busy timeout does
/// not retry.
#[tokio::test]
async fn reopening_a_current_store_commits_nothing() {
    let dir = tempfile::tempdir().unwrap();
    let runtime = RuntimeStore::open_as_runtime_owner(dir.path())
        .await
        .unwrap();
    let mut conn = runtime.pool().acquire().await.unwrap();
    let before = data_version(&mut conn).await;

    let cli = RuntimeStore::open(dir.path()).await.unwrap();
    cli.pool().close().await;

    assert_eq!(data_version(&mut conn).await, before);
}

/// A view an older host left behind still gets the current definition.
#[tokio::test]
async fn reopening_replaces_an_outdated_view() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    for statement in [
        "DROP VIEW orchestrationBoardRuns",
        "CREATE VIEW orchestrationBoardRuns AS SELECT 1 AS outdated",
    ] {
        sqlx::query(statement).execute(store.pool()).await.unwrap();
    }
    store.pool().close().await;

    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let sql: String = sqlx::query_scalar(
        "SELECT sql FROM sqlite_master WHERE type = 'view' AND name = 'orchestrationBoardRuns'",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert!(!sql.contains("outdated"), "{sql}");
}

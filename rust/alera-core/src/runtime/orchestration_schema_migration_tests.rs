use super::store_runs_v3_reset::RUNS_V3_BACKUP_FILE_NAME;
use super::store_runs_v3_reset_tests::drop_v3_orchestration;
use super::{OrchestrationMessageType, RuntimeStore};

/// A schema-1 store (no version key, no workspace columns) has no run that
/// maps onto v3, so it resets like v2: runs go, the external inbox stays.
#[tokio::test]
async fn legacy_v1_orchestration_schema_resets_to_v3() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let mut conn = store.pool().acquire().await.unwrap();
    drop_v3_orchestration(&mut conn).await;
    for statement in [
        "DELETE FROM runtimeMetadata WHERE key = 'orchestration.schemaVersion'",
        "CREATE TABLE orchestrationMessages (
            id TEXT NOT NULL, from_handle TEXT NOT NULL, to_handle TEXT NOT NULL,
            subject TEXT NOT NULL, body TEXT NOT NULL DEFAULT '', type TEXT NOT NULL,
            priority TEXT NOT NULL, thread_id TEXT, payload TEXT, read INTEGER NOT NULL DEFAULT 0,
            sequence INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL,
            delivered_at TEXT
        )",
        "CREATE TABLE orchestrationTasks (
            id TEXT PRIMARY KEY, parent_id TEXT, created_by_terminal_handle TEXT,
            task_title TEXT, display_name TEXT, spec TEXT NOT NULL, status TEXT NOT NULL,
            deps TEXT NOT NULL DEFAULT '[]', result TEXT, created_at TEXT NOT NULL,
            completed_at TEXT
        )",
        "CREATE TABLE orchestrationDispatchContexts (
            id TEXT PRIMARY KEY, task_id TEXT NOT NULL, assignee_handle TEXT,
            status TEXT NOT NULL, failure_count INTEGER NOT NULL DEFAULT 0,
            last_failure TEXT, dispatched_at TEXT, completed_at TEXT,
            created_at TEXT NOT NULL, last_heartbeat_at TEXT
        )",
        "CREATE TABLE orchestrationDecisionGates (
            id TEXT PRIMARY KEY, task_id TEXT NOT NULL, question TEXT NOT NULL,
            options TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL, resolution TEXT,
            created_at TEXT NOT NULL, resolved_at TEXT
        )",
        "CREATE TABLE orchestrationCoordinatorRuns (
            id TEXT PRIMARY KEY, spec TEXT NOT NULL, status TEXT NOT NULL,
            coordinator_handle TEXT, poll_interval_ms INTEGER NOT NULL,
            created_at TEXT NOT NULL, completed_at TEXT
        )",
        "INSERT INTO orchestrationTasks VALUES
         ('task-v1', NULL, 'owner', NULL, 'Legacy Task', 'work', 'dispatched', '[]',
          NULL, '2026-01-01 00:00:00', NULL)",
        "INSERT INTO orchestrationDispatchContexts VALUES
         ('dispatch-v1', 'task-v1', 'worker', 'dispatched', 0, NULL,
          '2026-01-01 00:01:00', NULL, '2026-01-01 00:01:00', NULL)",
        "INSERT INTO orchestrationMessages VALUES
         ('message-v1', 'worker', 'owner', 'done', 'body', 'status', 'normal',
          NULL, NULL, 0, 1, '2026-01-01 00:02:00', NULL)",
        "INSERT INTO orchestrationMessages VALUES
         ('question-v1', 'ext:ci', 'worker', 'Ask', 'Ready?', 'decision_gate', 'high',
          NULL, NULL, 1, 2, '2026-01-01 00:02:30', '2026-01-01 00:02:31')",
        "INSERT INTO orchestrationDecisionGates VALUES
         ('gate-v1', 'task-v1', 'Proceed?', '[]', 'pending', NULL,
          '2026-01-01 00:03:00', NULL)",
        "INSERT INTO orchestrationCoordinatorRuns VALUES
         ('run-v1', 'coordinate', 'running', 'owner', 2000,
          '2026-01-01 00:00:00', NULL)",
    ] {
        sqlx::query(statement).execute(&mut *conn).await.unwrap();
    }
    drop(conn);
    store.pool().close().await;
    drop(store);

    let migrated = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        migrated
            .get_metadata("orchestration.schemaVersion")
            .await
            .unwrap()
            .as_deref(),
        Some("3")
    );
    assert!(dir.path().join(RUNS_V3_BACKUP_FILE_NAME).exists());
    assert!(migrated
        .orchestration_task_by_id("task-v1")
        .await
        .unwrap()
        .is_none());
    assert!(migrated
        .orchestration_dispatch_by_id("dispatch-v1")
        .await
        .unwrap()
        .is_none());
    assert!(migrated
        .orchestration_coordinator_run_by_id("run-v1")
        .await
        .unwrap()
        .is_none());
    assert!(migrated
        .list_orchestration_gates(None, None)
        .await
        .unwrap()
        .is_empty());
    let messages = migrated.recent_orchestration_messages(10).await.unwrap();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].id, "question-v1");
    assert_eq!(messages[0].message_type, OrchestrationMessageType::Question);
    assert_eq!(messages[0].state, "read");
}

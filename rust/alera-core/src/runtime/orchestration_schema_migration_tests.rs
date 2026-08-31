use super::RuntimeStore;

#[tokio::test]
async fn legacy_orchestration_schema_migrates_without_losing_records() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    sqlx::query("DROP VIEW orchestrationBoardRuns")
        .execute(store.pool())
        .await
        .unwrap();
    for table in [
        "workflowStageGates",
        "workflowApprovalChallenges",
        "workflowTaskEvidence",
        "workflowDecisions",
        "workflowPlanTasks",
        "workflowPlanRevisions",
        "workflowRuns",
        "orchestrationAuditEvents",
        "orchestrationDecisionGates",
        "orchestrationDispatchContexts",
        "orchestrationMessages",
        "orchestrationTasks",
        "orchestrationCoordinatorRuns",
    ] {
        sqlx::query(sqlx::AssertSqlSafe(format!("DROP TABLE IF EXISTS {table}")))
            .execute(store.pool())
            .await
            .unwrap();
    }
    sqlx::query("DELETE FROM runtimeMetadata WHERE key = 'orchestration.schemaVersion'")
        .execute(store.pool())
        .await
        .unwrap();
    for statement in [
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
    ] {
        sqlx::query(statement).execute(store.pool()).await.unwrap();
    }
    sqlx::query(
        "INSERT INTO orchestrationTasks VALUES
         ('task-v1', NULL, 'owner', NULL, 'Legacy Task', 'work', 'dispatched', '[]',
          NULL, '2026-01-01 00:00:00', NULL)",
    )
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO orchestrationDispatchContexts VALUES
         ('dispatch-v1', 'task-v1', 'worker', 'dispatched', 0, NULL,
          '2026-01-01 00:01:00', NULL, '2026-01-01 00:01:00', NULL)",
    )
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO orchestrationMessages VALUES
         ('message-v1', 'worker', 'owner', 'done', 'body', 'status', 'normal',
          NULL, NULL, 0, 1, '2026-01-01 00:02:00', NULL)",
    )
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO orchestrationDecisionGates VALUES
         ('gate-v1', 'task-v1', 'Proceed?', '[]', 'pending', NULL,
          '2026-01-01 00:03:00', NULL)",
    )
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO orchestrationCoordinatorRuns VALUES
         ('run-v1', 'coordinate', 'running', 'owner', 2000,
          '2026-01-01 00:00:00', NULL)",
    )
    .execute(store.pool())
    .await
    .unwrap();
    drop(store);

    let migrated = RuntimeStore::open(dir.path()).await.unwrap();
    let task = migrated
        .orchestration_task_by_id("task-v1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.workspace_id, "global");
    assert_eq!(task.coordinator_handle, "owner");
    let dispatch = migrated
        .orchestration_dispatch_by_id("dispatch-v1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(dispatch.workspace_id, "global");
    assert_eq!(
        dispatch.accepted_at.as_deref(),
        dispatch.dispatched_at.as_deref()
    );
    let messages = migrated.orchestration_inbox(10).await.unwrap();
    assert_eq!(messages[0].id, "message-v1");
    assert_eq!(messages[0].state, "queued");
    assert_eq!(
        migrated.list_orchestration_gates(None, None).await.unwrap()[0].id,
        "gate-v1"
    );
    assert_eq!(
        migrated
            .orchestration_coordinator_run_by_id("run-v1")
            .await
            .unwrap()
            .unwrap()
            .workspace_id,
        "global"
    );
    assert_eq!(
        migrated
            .get_metadata("orchestration.schemaVersion")
            .await
            .unwrap()
            .as_deref(),
        Some("2")
    );
}

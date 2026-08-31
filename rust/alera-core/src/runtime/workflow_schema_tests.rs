use super::RuntimeStore;

#[tokio::test]
async fn workflow_schema_does_not_reference_the_board_before_its_migration() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let mut tx = store.pool().begin().await.unwrap();
    let triggers: Vec<String> = sqlx::query_scalar(
        "SELECT name FROM sqlite_schema WHERE type = 'trigger' AND name GLOB 'board_*'",
    )
    .fetch_all(&mut *tx)
    .await
    .unwrap();
    for trigger in triggers {
        assert!(trigger
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_'));
        sqlx::query(sqlx::AssertSqlSafe(format!("DROP TRIGGER {trigger}")))
            .execute(&mut *tx)
            .await
            .unwrap();
    }
    for statement in [
        "DROP VIEW orchestrationBoardRuns",
        "DROP TABLE orchestrationBoardRevision",
    ] {
        sqlx::query(statement).execute(&mut *tx).await.unwrap();
    }
    tx.commit().await.unwrap();

    store.migrate_workflow_plans().await.unwrap();
    let statements = [
        "EXPLAIN DELETE FROM orchestrationCoordinatorRuns",
        "EXPLAIN UPDATE orchestrationTasks SET result = NULL",
        "EXPLAIN DELETE FROM workflowTaskEvidence",
    ];
    for statement in statements {
        sqlx::query(statement)
            .fetch_all(store.pool())
            .await
            .unwrap();
    }

    store.migrate_orchestration_board().await.unwrap();
    let mut connections = Vec::new();
    for _ in 0..4 {
        connections.push(store.pool().acquire().await.unwrap());
    }
    for connection in &mut connections {
        for statement in statements {
            sqlx::query(statement)
                .fetch_all(&mut **connection)
                .await
                .unwrap();
        }
    }
}

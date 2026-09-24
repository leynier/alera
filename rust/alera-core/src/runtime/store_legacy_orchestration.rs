use super::*;

impl RuntimeStore {
    pub(super) async fn migrate_legacy_orchestration_schema(&self) -> Result<()> {
        let current = self.get_metadata("orchestration.schemaVersion").await?;
        match current.as_deref() {
            Some(super::super::orchestration_message_store::ORCHESTRATION_SCHEMA_VERSION) => {
                return Ok(())
            }
            Some(other) => anyhow::bail!(
                "unsupported orchestration schema version {other}; refusing destructive migration"
            ),
            None => {}
        }
        let task_columns = sqlx::query("PRAGMA table_info(orchestrationTasks)")
            .fetch_all(&self.pool)
            .await?;
        if task_columns.is_empty()
            || task_columns.iter().any(|row| {
                row.try_get::<String, _>("name")
                    .is_ok_and(|name| name == "workspace_id")
            })
        {
            return Ok(());
        }

        let mut tx = self.pool.begin().await?;
        for index in [
            "orchestrationMessagesIdIdx",
            "orchestrationMessagesInboxIdx",
            "orchestrationMessagesUndeliveredIdx",
            "orchestrationMessagesThreadIdx",
            "orchestrationTasksStatusIdx",
            "orchestrationTasksParentIdx",
            "orchestrationDispatchTaskIdx",
            "orchestrationDispatchStatusIdx",
            "orchestrationGatesTaskIdx",
        ] {
            sqlx::query(sqlx::AssertSqlSafe(format!("DROP INDEX IF EXISTS {index}")))
                .execute(&mut *tx)
                .await?;
        }
        for table in [
            "orchestrationMessages",
            "orchestrationTasks",
            "orchestrationDispatchContexts",
            "orchestrationDecisionGates",
            "orchestrationCoordinatorRuns",
        ] {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "ALTER TABLE {table} RENAME TO {table}LegacyV1"
            )))
            .execute(&mut *tx)
            .await?;
        }
        for statement in super::super::orchestration_message_store::ORCHESTRATION_SCHEMA {
            sqlx::query(*statement).execute(&mut *tx).await?;
        }
        sqlx::query(
            "INSERT INTO orchestrationMessages \
             (id, from_handle, to_handle, subject, body, type, priority, thread_id, payload, \
              read, sequence, created_at, delivered_at, state) \
             SELECT id, from_handle, to_handle, subject, body, type, priority, thread_id, payload, \
                    read, sequence, created_at, delivered_at, \
                    CASE WHEN read != 0 THEN 'read' \
                         WHEN delivered_at IS NOT NULL THEN 'delivered' ELSE 'queued' END \
             FROM orchestrationMessagesLegacyV1",
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO orchestrationTasks \
             (id, parent_id, created_by_terminal_handle, task_title, display_name, spec, status, \
              deps, result, created_at, completed_at, workspace_id, coordinator_handle) \
             SELECT id, parent_id, created_by_terminal_handle, task_title, display_name, spec, status, \
                    deps, result, created_at, completed_at, 'global', \
                    COALESCE(created_by_terminal_handle, 'coord') \
             FROM orchestrationTasksLegacyV1",
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO orchestrationDispatchContexts \
             (id, task_id, assignee_handle, status, failure_count, last_failure, dispatched_at, \
              completed_at, created_at, last_heartbeat_at, workspace_id, coordinator_handle, \
              accepted_at, last_activity_at) \
             SELECT d.id, d.task_id, d.assignee_handle, d.status, d.failure_count, d.last_failure, \
                    d.dispatched_at, d.completed_at, d.created_at, d.last_heartbeat_at, \
                    t.workspace_id, t.coordinator_handle, \
                    CASE WHEN d.status = 'dispatched' THEN d.dispatched_at ELSE NULL END, \
                    COALESCE(d.last_heartbeat_at, d.dispatched_at, d.created_at) \
             FROM orchestrationDispatchContextsLegacyV1 d \
             JOIN orchestrationTasks t ON t.id = d.task_id",
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO orchestrationDecisionGates \
             (id, task_id, question, options, status, resolution, created_at, resolved_at) \
             SELECT id, task_id, question, options, status, resolution, created_at, resolved_at \
             FROM orchestrationDecisionGatesLegacyV1",
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO orchestrationCoordinatorRuns \
             (id, spec, status, coordinator_handle, poll_interval_ms, created_at, completed_at, \
              workspace_id, max_concurrent, last_activity_at) \
             SELECT id, spec, status, coordinator_handle, poll_interval_ms, created_at, completed_at, \
                    'global', 4, created_at \
             FROM orchestrationCoordinatorRunsLegacyV1",
        )
        .execute(&mut *tx)
        .await?;
        for table in [
            "orchestrationMessagesLegacyV1",
            "orchestrationTasksLegacyV1",
            "orchestrationDispatchContextsLegacyV1",
            "orchestrationDecisionGatesLegacyV1",
            "orchestrationCoordinatorRunsLegacyV1",
        ] {
            sqlx::query(sqlx::AssertSqlSafe(format!("DROP TABLE {table}")))
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await?;
        Ok(())
    }
}

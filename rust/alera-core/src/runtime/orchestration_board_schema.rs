use anyhow::Result;

use super::RuntimeStore;

// The revision changes in the same transaction as its evidence. Rolled-back
// changes cannot invalidate a cursor, and reconnects do not reset the sequence.
impl RuntimeStore {
    pub(super) async fn migrate_orchestration_board(&self) -> Result<()> {
        for statement in BOARD_SCHEMA {
            sqlx::query(*statement).execute(self.pool()).await?;
        }
        for table in [
            "orchestrationCoordinatorRuns",
            "orchestrationTasks",
            "orchestrationDispatchContexts",
            "orchestrationDecisionGates",
            "orchestrationAuditEvents",
            "workspaces",
            "projects",
        ] {
            for operation in ["INSERT", "UPDATE", "DELETE"] {
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "CREATE TRIGGER IF NOT EXISTS board_{table}_{operation}
                     AFTER {operation} ON {table} BEGIN
                     UPDATE orchestrationBoardRevision SET revision = revision + 1 WHERE id = 1; END"
                )))
                .execute(self.pool())
                .await?;
            }
        }
        Ok(())
    }
}

const BOARD_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS orchestrationBoardRevision (
        id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL
    )",
    "INSERT OR IGNORE INTO orchestrationBoardRevision VALUES (1, 0)",
    "CREATE INDEX IF NOT EXISTS orchestrationBoardRunsPageIdx
        ON orchestrationCoordinatorRuns(created_at DESC, id DESC)",
    "CREATE INDEX IF NOT EXISTS orchestrationBoardTasksRunIdx
        ON orchestrationTasks(run_id, status)",
    "CREATE INDEX IF NOT EXISTS orchestrationBoardAuditTargetIdx
        ON orchestrationAuditEvents(target_id, created_at DESC, id DESC)",
    "CREATE VIEW IF NOT EXISTS orchestrationBoardRuns AS
     WITH tasks AS (
         SELECT run_id, COUNT(*) AS task_count,
             SUM(status = 'completed') AS completed_count,
             SUM(status = 'dispatched') AS running_count,
             SUM(status = 'failed') AS failed_count,
             SUM(status = 'stalled') AS stalled_count,
             SUM(status = 'blocked') AS blocked_count
         FROM orchestrationTasks GROUP BY run_id
     ), gates AS (
         SELECT t.run_id, COUNT(*) AS pending_gate_count
         FROM orchestrationDecisionGates g
         JOIN orchestrationTasks t ON t.id = g.task_id
         WHERE g.status = 'pending' GROUP BY t.run_id
     )
     SELECT r.id, substr(r.spec, 1, 256) AS objective, r.status,
         r.workspace_id, substr(w.name, 1, 256) AS workspace_name,
         w.projectId AS project_id, substr(p.name, 1, 256) AS project_name,
         r.created_at, r.last_activity_at,
         r.execution_policy_status AS policy_status,
         COALESCE(t.task_count, 0) AS task_count,
         COALESCE(t.completed_count, 0) AS completed_count,
         COALESCE(t.running_count, 0) AS running_count,
         COALESCE(t.failed_count, 0) AS failed_count,
         COALESCE(t.stalled_count, 0) AS stalled_count,
         COALESCE(t.blocked_count, 0) AS blocked_count,
         COALESCE(g.pending_gate_count, 0) AS pending_gate_count,
         CASE
             WHEN r.status IN ('completed','stopped') THEN 'history'
             WHEN r.status = 'failed'
                 OR r.execution_policy_status IN ('draft','rejected')
                 OR COALESCE(t.failed_count, 0) > 0
                 OR COALESCE(t.stalled_count, 0) > 0
                 OR COALESCE(t.blocked_count, 0) > 0
                 OR COALESCE(g.pending_gate_count, 0) > 0 THEN 'attention'
             ELSE 'active'
         END AS bucket
     FROM orchestrationCoordinatorRuns r
     LEFT JOIN tasks t ON t.run_id = r.id
     LEFT JOIN gates g ON g.run_id = r.id
     LEFT JOIN workspaces w ON w.id = r.workspace_id
     LEFT JOIN projects p ON p.id = w.projectId",
];

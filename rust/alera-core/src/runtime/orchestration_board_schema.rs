use anyhow::Result;

use super::RuntimeStore;

// The revision changes in the same transaction as its evidence. Rolled-back
// changes cannot invalidate a cursor, and reconnects do not reset the sequence.
impl RuntimeStore {
    pub(super) async fn migrate_orchestration_board(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("DROP VIEW IF EXISTS orchestrationBoardRuns")
            .execute(&mut *tx)
            .await?;
        for statement in BOARD_SCHEMA {
            sqlx::query(*statement).execute(&mut *tx).await?;
        }
        // Install these only after every referenced table exists; pooled SQLite
        // connections must never cache a schema with dangling trigger bodies.
        for table in [
            "orchestrationCoordinatorRuns",
            "orchestrationTasks",
            "orchestrationDispatchContexts",
            "orchestrationDecisionGates",
            "orchestrationAuditEvents",
            "workspaces",
            "projects",
            "workflowRuns",
            "workflowPlanRevisions",
            "workflowDecisions",
            "workflowStageGates",
            "workflowTaskEvidence",
            "workflowWorkspaces",
            "workflowIntegrations",
            "workflowLaunches",
        ] {
            for operation in ["INSERT", "UPDATE", "DELETE"] {
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "CREATE TRIGGER IF NOT EXISTS board_{table}_{operation}
                     AFTER {operation} ON {table} BEGIN
                     UPDATE orchestrationBoardRevision SET revision = revision + 1 WHERE id = 1; END"
                )))
                .execute(&mut *tx)
                .await?;
            }
        }
        tx.commit().await?;
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
     ), pending_gates AS (
         SELECT t.run_id
         FROM orchestrationDecisionGates g
         JOIN orchestrationTasks t ON t.id = g.task_id
         WHERE g.status = 'pending'
         UNION ALL
         SELECT g.run_id FROM workflowStageGates g
         JOIN workflowRuns w ON w.run_id = g.run_id AND w.revision = g.revision
         WHERE g.status = 'pending' AND w.status = 'approved'
           AND EXISTS(SELECT 1 FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id = p.task_id
               WHERE p.run_id = g.run_id AND p.revision = g.revision AND t.stage_id = g.stage_id)
           AND NOT EXISTS(SELECT 1 FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id = p.task_id
               LEFT JOIN workflowTaskEvidence e ON e.task_id = p.task_id
               WHERE p.run_id = g.run_id AND p.revision = g.revision AND t.stage_id = g.stage_id
                 AND (t.status <> 'completed' OR e.task_id IS NULL))
     ), gates AS (
         SELECT run_id, COUNT(*) AS pending_gate_count FROM pending_gates GROUP BY run_id
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
                 OR COALESCE(g.pending_gate_count, 0) > 0
                 OR EXISTS(SELECT 1 FROM workflowLaunches l JOIN workflowRuns wr ON wr.run_id = l.run_id
                     WHERE l.run_id = r.id AND l.revision = wr.revision AND l.status = 'attention'
                       AND NOT EXISTS(SELECT 1 FROM workflowTaskEvidence e WHERE e.task_id = l.task_id)
                       AND NOT EXISTS(SELECT 1 FROM workflowLaunches newer
                           WHERE newer.task_id = l.task_id AND newer.sequence > l.sequence))
                 OR EXISTS(SELECT 1 FROM workflowIntegrations i JOIN workflowRuns wr ON wr.run_id = i.run_id
                     WHERE i.run_id = r.id AND i.state IN ('conflict','attention')
                       AND (i.state = 'attention' OR i.revision = wr.revision)
                       AND NOT EXISTS(SELECT 1 FROM workflowTaskEvidence e WHERE e.task_id = i.task_id))
                 OR EXISTS(SELECT 1 FROM workflowIntegrations i JOIN workflowRuns wr ON wr.run_id = i.run_id
                     WHERE i.run_id = r.id AND i.state = 'integrated' AND i.revision = wr.revision
                       AND NOT EXISTS(SELECT 1 FROM workflowTaskEvidence e WHERE e.task_id = i.task_id))
                 OR EXISTS(SELECT 1 FROM workflowWorkspaces x JOIN workflowRuns wr ON wr.run_id = x.run_id
                     WHERE x.run_id = r.id AND x.phase = 'attention'
                       AND (x.task_id IS NULL OR x.revision = wr.revision)
                       AND NOT EXISTS(SELECT 1 FROM workflowWorkspaces newer
                           WHERE newer.run_id = x.run_id AND newer.task_id IS x.task_id AND newer.attempt > x.attempt))
                 THEN 'attention'
             ELSE 'active'
         END AS bucket
     FROM orchestrationCoordinatorRuns r
     LEFT JOIN tasks t ON t.run_id = r.id
     LEFT JOIN gates g ON g.run_id = r.id
     LEFT JOIN workspaces w ON w.id = r.workspace_id
     LEFT JOIN projects p ON p.id = w.projectId",
];

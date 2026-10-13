use anyhow::Result;
use sqlx::SqliteConnection;

use super::orchestration_gate_store::RUN_PENDING_PLAN_GATE_SQL;

// Every table whose rows the board projects. The revision changes in the same
// transaction as its evidence, so rolled-back changes cannot invalidate a
// cursor and reconnects do not reset the sequence.
const BOARD_SOURCE_TABLES: &[&str] = &[
    "orchestrationCoordinatorRuns",
    "orchestrationTasks",
    "orchestrationDispatchContexts",
    "orchestrationAuditEvents",
    "runGates",
    "runEvents",
    "workspaces",
    "projects",
    "runPlanRevisions",
    "runTaskEvidence",
    "runWorkspaces",
    "runIntegrations",
    "runLaunches",
    "runCancellationTargets",
    "runCleanup",
    "runCleanupResources",
];

pub(super) async fn install_board_schema(conn: &mut SqliteConnection) -> Result<()> {
    for statement in BOARD_SCHEMA {
        sqlx::query(*statement).execute(&mut *conn).await?;
    }
    super::schema_object_replacement::replace_schema_object(conn, &board_runs_view()).await?;
    // Install these only after every referenced table exists; pooled SQLite
    // connections must never cache a schema with dangling trigger bodies.
    for table in BOARD_SOURCE_TABLES {
        for operation in ["INSERT", "UPDATE", "DELETE"] {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "CREATE TRIGGER IF NOT EXISTS board_{table}_{operation}
                 AFTER {operation} ON {table} BEGIN
                 UPDATE orchestrationBoardRevision SET revision = revision + 1 WHERE id = 1; END"
            )))
            .execute(&mut *conn)
            .await?;
        }
    }
    Ok(())
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
];

/// Pending gates a person can act on now: every pending gate except a stage
/// gate whose stage is not finished yet. `{gate}` names the `runGates` row.
pub(super) const DUE_GATE_SQL: &str =
    "({gate}.status = 'pending' AND ({gate}.kind <> 'stage' OR {gate}.evidence_digest IS NOT NULL))";

/// Attention: a gate is due, a task failed, stalled or is blocked, the run
/// or its coordinator asks for attention, or a launch, workspace,
/// integration, cancellation or cleanup needs a person. History: completed,
/// failed with nothing left to settle, or cancelled once its cancellation
/// settled. Everything else is active.
fn board_runs_view() -> String {
    let plan_gate_pending = RUN_PENDING_PLAN_GATE_SQL.replace("{run}", "r");
    let due = DUE_GATE_SQL.replace("{gate}", "g");
    format!(
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
         SELECT COALESCE(g.run_id, t.run_id) AS run_id, g.kind
         FROM runGates g
         LEFT JOIN orchestrationTasks t ON t.id = g.task_id
         WHERE {due}
     ), gates AS (
         SELECT run_id, COUNT(*) AS pending_gate_count,
             group_concat(DISTINCT kind) AS pending_gate_kinds
         FROM pending_gates GROUP BY run_id
     ), runs AS (
         SELECT r.*, {plan_gate_pending} AS plan_gate_pending FROM orchestrationCoordinatorRuns r
     ), settling AS (
         SELECT r.id AS run_id,
             EXISTS(SELECT 1 FROM runCleanup WHERE run_id=r.id AND abandoned=0 AND state='attention') AS cleanup_attention,
             EXISTS(SELECT 1 FROM runCleanup WHERE run_id=r.id AND abandoned=0 AND state='applying') AS cleanup_applying,
             EXISTS(SELECT 1 FROM runIntegrations WHERE run_id=r.id AND cancelled=0 AND state='attention') AS integration_attention,
             EXISTS(SELECT 1 FROM runIntegrations WHERE run_id=r.id AND cancelled=0
                 AND state IN ('pending','prepared')) AS integration_pending,
             EXISTS(SELECT 1 FROM runCancellationTargets WHERE run_id=r.id AND state='attention') AS cancellation_attention
         FROM orchestrationCoordinatorRuns r
     )
     SELECT r.id, substr(r.spec, 1, 256) AS objective, r.status,
         r.workspace_id, substr(w.name, 1, 256) AS workspace_name,
         w.projectId AS project_id, substr(p.name, 1, 256) AS project_name,
         r.created_at, r.last_activity_at, r.completed_at,
         r.plan_gate_pending,
         r.isolation, r.approval_required, r.plan_revision, r.attention_reason,
         r.coordinator_state, r.paused_by, r.control_sequence,
         COALESCE(t.task_count, 0) AS task_count,
         COALESCE(t.completed_count, 0) AS completed_count,
         COALESCE(t.running_count, 0) AS running_count,
         COALESCE(t.failed_count, 0) AS failed_count,
         COALESCE(t.stalled_count, 0) AS stalled_count,
         COALESCE(t.blocked_count, 0) AS blocked_count,
         COALESCE(g.pending_gate_count, 0) AS pending_gate_count,
         COALESCE(g.pending_gate_kinds, '') AS pending_gate_kinds,
         s.cleanup_attention, s.cleanup_applying,
         CASE
             WHEN s.cleanup_attention THEN 'attention'
             WHEN s.cleanup_applying THEN 'active'
             WHEN r.status = 'cancelled' AND s.integration_attention THEN 'attention'
             WHEN r.status = 'cancelled' AND s.integration_pending THEN 'active'
             WHEN r.status = 'cancelled' AND s.cancellation_attention THEN 'attention'
             WHEN r.status = 'failed' AND (s.integration_attention OR s.cancellation_attention)
                 THEN 'attention'
             WHEN r.status IN ('completed','failed')
                 OR (r.status = 'cancelled' AND r.completed_at IS NOT NULL) THEN 'history'
             WHEN r.status = 'cancelled' THEN 'active'
             WHEN r.attention_reason IS NOT NULL
                 OR r.coordinator_state = 'attention'
                 OR COALESCE(t.failed_count, 0) > 0
                 OR COALESCE(t.stalled_count, 0) > 0
                 OR COALESCE(t.blocked_count, 0) > 0
                 OR COALESCE(g.pending_gate_count, 0) > 0
                 OR EXISTS(SELECT 1 FROM runLaunches l
                     WHERE l.run_id = r.id AND l.revision = r.plan_revision AND l.status = 'attention'
                       AND NOT EXISTS(SELECT 1 FROM runTaskEvidence e WHERE e.task_id = l.task_id)
                       AND NOT EXISTS(SELECT 1 FROM runLaunches newer
                           WHERE newer.task_id = l.task_id AND newer.sequence > l.sequence)
                       AND NOT EXISTS(SELECT 1 FROM runWorkspaces newer
                           WHERE newer.run_id = l.run_id AND newer.task_id IS l.task_id
                             AND newer.attempt > (SELECT attempt FROM runWorkspaces
                                 WHERE id = l.workspace_id)))
                 OR EXISTS(SELECT 1 FROM runIntegrations i
                     WHERE i.run_id = r.id AND i.cancelled=0 AND i.state IN ('conflict','attention')
                       AND (i.state = 'attention' OR i.revision = r.plan_revision)
                       AND NOT EXISTS(SELECT 1 FROM runTaskEvidence e WHERE e.task_id = i.task_id))
                 OR EXISTS(SELECT 1 FROM runIntegrations i
                     WHERE i.run_id = r.id AND i.state = 'integrated' AND i.revision = r.plan_revision
                       AND NOT EXISTS(SELECT 1 FROM runTaskEvidence e WHERE e.task_id = i.task_id))
                 OR EXISTS(SELECT 1 FROM runWorkspaces x
                     WHERE x.run_id = r.id AND x.phase = 'attention'
                       AND (x.task_id IS NULL OR x.revision = r.plan_revision)
                       AND NOT EXISTS(SELECT 1 FROM runWorkspaces newer
                           WHERE newer.run_id = x.run_id AND newer.task_id IS x.task_id AND newer.attempt > x.attempt))
                 THEN 'attention'
             ELSE 'active'
         END AS bucket
     FROM runs r
     LEFT JOIN tasks t ON t.run_id = r.id
     LEFT JOIN gates g ON g.run_id = r.id
     LEFT JOIN settling s ON s.run_id = r.id
     LEFT JOIN workspaces w ON w.id = r.workspace_id
     LEFT JOIN projects p ON p.id = w.projectId"
    )
}

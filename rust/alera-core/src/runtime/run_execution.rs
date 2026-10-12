//! Scheduling state of an isolated run, read from its run row: the current
//! plan revision, the `runs.control` sequence and the attention reason.

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::{Row, Sqlite, Transaction};

use super::run_event_store::{record_run_event, NewRunEvent, RunActorKind, RunEventKind};
use super::run_plan::workflow_text;
use super::RuntimeStore;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowExecutionState {
    pub run_id: String,
    pub revision: i64,
    pub sequence: i64,
    pub status: String,
    #[serde(default)]
    pub attention: Option<String>,
}

pub(super) async fn install_execution_schema(conn: &mut sqlx::SqliteConnection) -> Result<()> {
    sqlx::query("CREATE INDEX IF NOT EXISTS runIntegrationWorkspaceSequence ON runIntegrations(workspace_id,sequence DESC)")
        .execute(&mut *conn).await?;
    sqlx::query("DROP TRIGGER IF EXISTS runDispatchRequiresRunning")
        .execute(&mut *conn)
        .await?;
    // Planning, approval, pauses and finished runs never dispatch, whichever
    // path (scheduler, coordinator or manual dispatch) asks.
    sqlx::query(
        "CREATE TRIGGER runDispatchRequiresRunning
        BEFORE INSERT ON orchestrationDispatchContexts
        WHEN EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns r
            WHERE r.id = NEW.run_id AND r.status <> 'running')
        BEGIN SELECT RAISE(ABORT, 'run is not running; dispatch waits for its plan or a resume'); END",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS runCommandReceipts (
            request_id TEXT PRIMARY KEY, request_digest TEXT NOT NULL,
            run_id TEXT NOT NULL REFERENCES orchestrationCoordinatorRuns(id) ON DELETE CASCADE,
            receipt TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS runExecutionRunning ON orchestrationCoordinatorRuns(isolation,status,id)",
    )
    .execute(&mut *conn)
    .await?;
    super::run_cancellation::migrate(conn).await
}

const EXECUTION_COLUMNS: &str = "id AS run_id, plan_revision AS revision, \
    control_sequence AS sequence, status, attention_reason AS attention";

impl RuntimeStore {
    /// The scheduling state of an isolated run with an accepted plan.
    pub async fn workflow_execution(&self, run: &str) -> Result<Option<WorkflowExecutionState>> {
        workflow_text(run, 160)?;
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {EXECUTION_COLUMNS} FROM orchestrationCoordinatorRuns
            WHERE id = ? AND isolation = 'isolated' AND plan_revision IS NOT NULL"
        )))
        .bind(run)
        .fetch_optional(self.pool())
        .await?
        .map(decode)
        .transpose()
    }

    /// Running isolated runs, a page at a time, for the scheduler pump.
    pub async fn workflow_execution_page(
        &self,
        after: Option<&str>,
    ) -> Result<Vec<WorkflowExecutionState>> {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {EXECUTION_COLUMNS} FROM orchestrationCoordinatorRuns
            WHERE isolation = 'isolated' AND status = 'running' AND plan_revision IS NOT NULL
            AND (? IS NULL OR id > ?) ORDER BY id LIMIT 25"
        )))
        .bind(after)
        .bind(after)
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(decode)
        .collect()
    }

    /// Pauses a running run for a person. The runtime never resumes it by
    /// itself: only `runs.control resume` clears the attention reason.
    pub async fn pause_workflow_execution_for_attention(
        &self,
        run: &str,
        revision: i64,
        sequence: i64,
        reason: &str,
    ) -> Result<bool> {
        sequence
            .checked_add(1)
            .ok_or_else(|| anyhow!("run control sequence exhausted"))?;
        let reason = reason.chars().take(1000).collect::<String>();
        let mut tx = self.pool().begin().await?;
        let changed = sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET status = 'paused', paused_by = 'runtime',
                attention_reason = ?, control_sequence = control_sequence + 1,
                last_activity_at = datetime('now')
            WHERE id = ? AND plan_revision = ? AND control_sequence = ? AND status = 'running'",
        )
        .bind(&reason)
        .bind(run)
        .bind(revision)
        .bind(sequence)
        .execute(&mut *tx)
        .await?
        .rows_affected()
            == 1;
        if changed {
            let mut event = NewRunEvent::new(run, RunEventKind::Attention);
            event.actor_kind = Some(RunActorKind::Runtime);
            event.summary = &reason;
            record_run_event(&mut tx, &event).await?;
        }
        tx.commit().await?;
        Ok(changed)
    }
}

/// Isolated work only advances while its run is running the given revision.
pub(super) async fn require_running(
    tx: &mut Transaction<'_, Sqlite>,
    run: &str,
    revision: i64,
) -> Result<()> {
    let running: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns WHERE id = ?
            AND plan_revision = ? AND status = 'running')",
    )
    .bind(run)
    .bind(revision)
    .fetch_one(&mut **tx)
    .await?;
    if !running {
        bail!("run is paused or belongs to an obsolete plan");
    }
    Ok(())
}

fn decode(row: sqlx::sqlite::SqliteRow) -> Result<WorkflowExecutionState> {
    Ok(WorkflowExecutionState {
        run_id: row.try_get("run_id")?,
        revision: row.try_get("revision")?,
        sequence: row.try_get("sequence")?,
        status: row.try_get("status")?,
        attention: row.try_get("attention")?,
    })
}

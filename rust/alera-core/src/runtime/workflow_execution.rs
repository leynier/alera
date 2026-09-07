use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::{Row, Sqlite, Transaction};

use super::workflow_plan::{workflow_digest, workflow_text};
use super::RuntimeStore;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ControlWorkflowExecution {
    pub request_id: String,
    pub run_id: String,
    pub revision: i64,
    pub expected_sequence: i64,
    pub action: WorkflowExecutionAction,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkflowExecutionAction {
    Start,
    Pause,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowExecutionState {
    pub run_id: String,
    pub revision: i64,
    pub sequence: i64,
    pub status: String,
}

impl RuntimeStore {
    pub(super) async fn migrate_workflow_execution(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS workflowExecution (
                run_id TEXT PRIMARY KEY REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
                revision INTEGER NOT NULL, sequence INTEGER NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('running','paused'))
            )",
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "CREATE TRIGGER IF NOT EXISTS workflowExecutionDispatchGuard
            BEFORE INSERT ON orchestrationDispatchContexts
            WHEN EXISTS(SELECT 1 FROM workflowExecution e JOIN workflowRuns w ON w.run_id=e.run_id
                WHERE e.run_id=NEW.run_id AND (e.status <> 'running' OR e.revision <> w.revision))
            BEGIN SELECT RAISE(ABORT, 'workflow execution is paused or obsolete'); END",
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS workflowExecutionCommands (
                request_id TEXT PRIMARY KEY, request_digest TEXT NOT NULL,
                run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
                receipt TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )",
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn workflow_execution(&self, run: &str) -> Result<Option<WorkflowExecutionState>> {
        workflow_text(run, 160)?;
        sqlx::query("SELECT * FROM workflowExecution WHERE run_id = ?")
            .bind(run)
            .fetch_optional(self.pool())
            .await?
            .map(decode)
            .transpose()
    }

    /// Commands retain their original receipts. Replaying Start after a later
    /// Pause acknowledges the old command without resuming the run.
    pub async fn control_workflow_execution(
        &self,
        request: &ControlWorkflowExecution,
    ) -> Result<WorkflowExecutionState> {
        workflow_text(&request.request_id, 160)?;
        workflow_text(&request.run_id, 160)?;
        if request.revision < 1 || request.expected_sequence < 0 {
            bail!("invalid workflow execution revision or sequence");
        }
        let digest = workflow_digest(request)?;
        let mut tx = self.pool().begin().await?;
        // Serialize the receipt check with competing commands and dispatch.
        sqlx::query("UPDATE workflowRuns SET revision = revision WHERE run_id = ?")
            .bind(&request.run_id)
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query(
            "SELECT request_digest, receipt FROM workflowExecutionCommands WHERE request_id = ?",
        )
        .bind(&request.request_id)
        .fetch_optional(&mut *tx)
        .await?
        {
            if row.try_get::<String, _>("request_digest")? != digest {
                bail!("workflow execution request id has different contents");
            }
            return Ok(serde_json::from_str(&row.try_get::<String, _>("receipt")?)?);
        }
        let approved: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowRuns w
                JOIN orchestrationCoordinatorRuns c ON c.id = w.run_id
                WHERE w.run_id = ? AND w.revision = ? AND w.status = 'approved'
                AND c.status IN ('idle','running'))",
        )
        .bind(&request.run_id)
        .bind(request.revision)
        .fetch_one(&mut *tx)
        .await?;
        if !approved {
            bail!("execution requires the current approved workflow plan");
        }
        let current: Option<i64> =
            sqlx::query_scalar("SELECT sequence FROM workflowExecution WHERE run_id = ?")
                .bind(&request.run_id)
                .fetch_optional(&mut *tx)
                .await?;
        if current.unwrap_or(0) != request.expected_sequence {
            bail!("workflow execution changed; refresh before changing its state");
        }
        let sequence = request
            .expected_sequence
            .checked_add(1)
            .ok_or_else(|| anyhow!("workflow execution sequence exhausted"))?;
        let status = match request.action {
            WorkflowExecutionAction::Start => "running",
            WorkflowExecutionAction::Pause => "paused",
        };
        let receipt = WorkflowExecutionState {
            run_id: request.run_id.clone(),
            revision: request.revision,
            sequence,
            status: status.into(),
        };
        sqlx::query(
            "INSERT INTO workflowExecution(run_id,revision,sequence,status) VALUES (?,?,?,?)
            ON CONFLICT(run_id) DO UPDATE SET revision=excluded.revision,
                sequence=excluded.sequence,status=excluded.status",
        )
        .bind(&request.run_id)
        .bind(request.revision)
        .bind(sequence)
        .bind(status)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO workflowExecutionCommands(request_id,request_digest,run_id,receipt)
                VALUES (?,?,?,?)",
        )
        .bind(&request.request_id)
        .bind(digest)
        .bind(&request.run_id)
        .bind(serde_json::to_string(&receipt)?)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(receipt)
    }
}

pub(super) async fn require_running(
    tx: &mut Transaction<'_, Sqlite>,
    run: &str,
    revision: i64,
) -> Result<()> {
    let blocked: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM workflowExecution WHERE run_id = ?
            AND (revision <> ? OR status <> 'running'))",
    )
    .bind(run)
    .bind(revision)
    .fetch_one(&mut **tx)
    .await?;
    if blocked {
        bail!("workflow execution is paused or belongs to an obsolete plan");
    }
    Ok(())
}

fn decode(row: sqlx::sqlite::SqliteRow) -> Result<WorkflowExecutionState> {
    Ok(WorkflowExecutionState {
        run_id: row.try_get("run_id")?,
        revision: row.try_get("revision")?,
        sequence: row.try_get("sequence")?,
        status: row.try_get("status")?,
    })
}

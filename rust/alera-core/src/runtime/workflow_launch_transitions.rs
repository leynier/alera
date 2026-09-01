use anyhow::{bail, Result};
use sqlx::Row;

use super::workflow_launch_store::decode;
use super::workflow_launch_validation::inputs;
use super::workflow_plan::workflow_digest;
use super::{RuntimeStore, WorkflowLaunchInputs, WorkflowLaunchRecord, WorkflowLaunchStatus};

impl RuntimeStore {
    /// Called after host-owned process teardown, or while reconciling a missing
    /// host session. It never reuses the old attempt or reopens a completed task.
    pub async fn settle_workflow_launch_without_session(
        &self,
        terminal: &str,
        reason: &str,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        let Some(row) = sqlx::query("SELECT l.*, d.status AS dispatch_status FROM workflowLaunches l
            LEFT JOIN orchestrationDispatchContexts d ON d.id = l.dispatch_id WHERE l.terminal_handle = ?")
            .bind(terminal).fetch_optional(&mut *tx).await? else { return Ok(()); };
        let record = decode(&row)?;
        if row
            .try_get::<Option<String>, _>("dispatch_status")?
            .as_deref()
            == Some("completed")
        {
            return Ok(());
        }
        let reason = reason.chars().take(1000).collect::<String>();
        sqlx::query("UPDATE workflowLaunches SET status = 'attention', error = ?, updated_at = datetime('now') WHERE id = ?")
            .bind(&reason).bind(&record.id).execute(&mut *tx).await?;
        sqlx::query("UPDATE workflowWorkspaces SET phase = 'attention', error = ?, updated_at = datetime('now') WHERE id = ?")
            .bind(&reason).bind(&record.request.workspace_id).execute(&mut *tx).await?;
        sqlx::query("UPDATE orchestrationDispatchContexts SET status = 'startup_failed', startup_error = ?, completed_at = datetime('now')
            WHERE id = ? AND status IN ('pending','awaiting_acceptance','dispatched','stalled')")
            .bind(&reason).bind(&record.dispatch_id).execute(&mut *tx).await?;
        sqlx::query("UPDATE orchestrationTasks SET status = 'pending' WHERE id = ? AND status IN ('dispatched','ready','stalled','failed')
            AND EXISTS(SELECT 1 FROM workflowRuns WHERE run_id = ? AND revision = ? AND status = 'approved')
            AND NOT EXISTS(SELECT 1 FROM workflowWorkspaces WHERE task_id = ? AND attempt > (SELECT attempt FROM workflowWorkspaces WHERE id = ?))")
            .bind(&record.request.task_id).bind(&record.request.run_id).bind(record.request.revision)
            .bind(&record.request.task_id).bind(&record.request.workspace_id).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(())
    }
    /// One-shot claim immediately before spawning, never during replay/recovery.
    pub async fn claim_workflow_launch(&self, id: &str) -> Result<WorkflowLaunchInputs> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query("SELECT * FROM workflowLaunches WHERE id = ?")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
        let record = decode(&row)?;
        if record.status != WorkflowLaunchStatus::Reserved {
            bail!("workflow launch has already been claimed");
        }
        let frozen: WorkflowLaunchInputs =
            serde_json::from_str(&row.try_get::<String, _>("inputs")?)?;
        let current = inputs(&mut tx, &record.request, true).await?;
        if workflow_digest(&frozen)? != workflow_digest(&current)? {
            bail!("workflow launch inputs changed");
        }
        let valid: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM orchestrationDispatchContexts d
            JOIN workflowWorkspaces w ON w.dispatch_id = d.id WHERE d.id = ? AND w.id = ?
            AND d.status = 'awaiting_acceptance' AND d.assignee_handle = ?)",
        )
        .bind(&record.dispatch_id)
        .bind(&record.request.workspace_id)
        .bind(&record.terminal_handle)
        .fetch_one(&mut *tx)
        .await?;
        if !valid {
            bail!("workflow launch dispatch is no longer awaiting acceptance");
        }
        sqlx::query("UPDATE workflowLaunches SET status = 'starting', updated_at = datetime('now') WHERE id = ?")
            .bind(id).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(frozen)
    }

    /// Revalidates the durable launch immediately before a host process may
    /// start. Git preflight runs outside this transaction, so cancellation or
    /// a reviewed plan change may have invalidated the earlier claim.
    pub async fn require_workflow_launch_spawnable(&self, id: &str) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query("SELECT * FROM workflowLaunches WHERE id = ?")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
        let record = decode(&row)?;
        if record.status != WorkflowLaunchStatus::Starting {
            bail!("workflow launch is no longer starting");
        }
        let frozen: WorkflowLaunchInputs =
            serde_json::from_str(&row.try_get::<String, _>("inputs")?)?;
        let current = inputs(&mut tx, &record.request, true).await?;
        if workflow_digest(&frozen)? != workflow_digest(&current)? {
            bail!("workflow launch inputs changed");
        }
        let valid: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM orchestrationDispatchContexts d
            JOIN workflowWorkspaces w ON w.dispatch_id = d.id
            WHERE d.id = ? AND d.task_id = ? AND d.run_id = ? AND d.workspace_id = ?
              AND d.status = 'awaiting_acceptance' AND d.assignee_handle = ?
              AND w.id = ? AND w.run_id = ? AND w.revision = ? AND w.task_id = ?)",
        )
        .bind(&record.dispatch_id)
        .bind(&record.request.task_id)
        .bind(&record.request.run_id)
        .bind(&record.request.workspace_id)
        .bind(&record.terminal_handle)
        .bind(&record.request.workspace_id)
        .bind(&record.request.run_id)
        .bind(record.request.revision)
        .bind(&record.request.task_id)
        .fetch_one(&mut *tx)
        .await?;
        if !valid {
            bail!("workflow launch dispatch is no longer awaiting acceptance");
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn mark_workflow_launch_started(&self, id: &str) -> Result<WorkflowLaunchRecord> {
        let changed = sqlx::query("UPDATE workflowLaunches SET status = 'started', updated_at = datetime('now') WHERE id = ? AND status = 'starting'")
            .bind(id).execute(self.pool()).await?.rows_affected();
        if changed != 1 {
            bail!("workflow launch is not starting");
        }
        self.workflow_launch(id).await
    }

    /// Attention alone does not release concurrency or authorize a retry: the
    /// host must first verify the old process is gone and settle its dispatch.
    pub async fn workflow_launch_attention(
        &self,
        id: &str,
        error: &str,
    ) -> Result<WorkflowLaunchRecord> {
        sqlx::query("UPDATE workflowLaunches SET status = 'attention', error = ?, updated_at = datetime('now') WHERE id = ?")
            .bind(error.chars().take(1000).collect::<String>()).bind(id).execute(self.pool()).await?;
        self.workflow_launch(id).await
    }
}

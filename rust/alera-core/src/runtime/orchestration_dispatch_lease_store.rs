//! A dispatch between hand-off and outcome: acceptance, activity, startup
//! failure, and the lease sweep that stalls or lists idle dispatches.

use anyhow::{anyhow, bail, Result};

use super::orchestration_dispatch_store::{dispatch_from_row, DISPATCH_COLUMNS};
use super::run_event_store::{record_dispatch_run_event, RunEventKind};
use super::{
    ActivityOutcome, OrchestrationDispatchContext, OrchestrationDispatchStatus, RuntimeStore,
};

impl RuntimeStore {
    pub async fn accept_orchestration_dispatch(
        &self,
        dispatch_id: &str,
        assignee_handle: &str,
        context_token_hash: &str,
    ) -> Result<OrchestrationDispatchContext> {
        let mut tx = self.pool().begin().await?;
        let previous: Option<String> =
            sqlx::query_scalar("SELECT status FROM orchestrationDispatchContexts WHERE id = ?")
                .bind(dispatch_id)
                .fetch_optional(&mut *tx)
                .await?;
        let result = sqlx::query(
            "UPDATE orchestrationDispatchContexts \
             SET status = 'dispatched', accepted_at = COALESCE(accepted_at, datetime('now')), \
                 last_activity_at = datetime('now') \
             WHERE id = ? AND assignee_handle = ? \
             AND (context_token_hash = ? OR context_token_hash IS NULL) \
             AND status IN ('awaiting_acceptance','dispatched')",
        )
        .bind(dispatch_id)
        .bind(assignee_handle)
        .bind(context_token_hash)
        .execute(&mut *tx)
        .await?;
        if result.rows_affected() == 0 {
            bail!("dispatch acceptance rejected: stale context or wrong assignee");
        }
        if previous.as_deref() == Some("awaiting_acceptance") {
            record_dispatch_run_event(&mut tx, dispatch_id, RunEventKind::Accepted, "", None)
                .await?;
        }
        tx.commit().await?;
        self.orchestration_dispatch_by_id(dispatch_id)
            .await?
            .ok_or_else(|| anyhow!("dispatch context not found after acceptance: {dispatch_id}"))
    }

    /// Renews the lease of an active dispatch. A stalled dispatch that shows
    /// activity again is a worker that was only slow: it returns to
    /// `dispatched` together with its task.
    pub async fn record_orchestration_activity(
        &self,
        dispatch_id: &str,
    ) -> Result<ActivityOutcome> {
        let mut tx = self.pool().begin().await?;
        let renewed = sqlx::query(
            "UPDATE orchestrationDispatchContexts SET last_activity_at = datetime('now') \
             WHERE id = ? AND status = 'dispatched'",
        )
        .bind(dispatch_id)
        .execute(&mut *tx)
        .await?
        .rows_affected()
            > 0;
        let outcome = if renewed {
            ActivityOutcome::Recorded
        } else if revive_stalled_dispatch(&mut tx, dispatch_id).await? {
            ActivityOutcome::Revived
        } else {
            return Ok(ActivityOutcome::Ignored);
        };
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET last_activity_at = datetime('now') \
             WHERE id = (SELECT run_id FROM orchestrationDispatchContexts WHERE id = ?)",
        )
        .bind(dispatch_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(outcome)
    }

    pub async fn fail_orchestration_startup(
        &self,
        dispatch_id: &str,
        error: &str,
    ) -> Result<OrchestrationDispatchContext> {
        let mut tx = self.pool().begin().await?;
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts WHERE id = ?"
        )))
        .bind(dispatch_id)
        .fetch_optional(&mut *tx)
        .await?;
        let ctx = row
            .map(dispatch_from_row)
            .transpose()?
            .ok_or_else(|| anyhow!("dispatch context not found: {dispatch_id}"))?;
        if ctx.status == OrchestrationDispatchStatus::StartupFailed {
            return Ok(ctx);
        }
        if ctx.status != OrchestrationDispatchStatus::AwaitingAcceptance {
            bail!("dispatch {dispatch_id} is not awaiting acceptance");
        }
        sqlx::query(
            "UPDATE orchestrationDispatchContexts SET status = 'startup_failed', startup_error = ?, \
             completed_at = datetime('now') WHERE id = ?",
        )
        .bind(error)
        .bind(dispatch_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE orchestrationTasks SET startup_failure_count = startup_failure_count + 1, \
             status = CASE WHEN startup_failure_count + 1 >= 3 THEN 'stalled' ELSE 'ready' END, \
             stalled_at = CASE WHEN startup_failure_count + 1 >= 3 THEN datetime('now') ELSE NULL END \
             WHERE id = ?",
        )
        .bind(&ctx.task_id)
        .execute(&mut *tx)
        .await?;
        let stalled: bool =
            sqlx::query_scalar("SELECT status = 'stalled' FROM orchestrationTasks WHERE id = ?")
                .bind(&ctx.task_id)
                .fetch_one(&mut *tx)
                .await?;
        let (kind, summary) = if stalled {
            (
                RunEventKind::TaskStalled,
                format!("Startup failed three times: {error}"),
            )
        } else {
            (RunEventKind::TaskFailed, format!("Startup failed: {error}"))
        };
        record_dispatch_run_event(
            &mut tx,
            dispatch_id,
            kind,
            &summary,
            Some(serde_json::json!({ "willRetry": !stalled })),
        )
        .await?;
        tx.commit().await?;
        self.orchestration_dispatch_by_id(dispatch_id)
            .await?
            .ok_or_else(|| anyhow!("dispatch context not found after startup failure"))
    }

    pub async fn stall_expired_orchestration_dispatches(
        &self,
        threshold_iso: &str,
    ) -> Result<Vec<OrchestrationDispatchContext>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE status = 'dispatched' AND COALESCE(last_activity_at, accepted_at, dispatched_at) < ?"
        )))
        .bind(threshold_iso)
        .fetch_all(self.pool())
        .await?;
        let contexts: Vec<_> = rows
            .into_iter()
            .map(dispatch_from_row)
            .collect::<Result<_>>()?;
        for ctx in &contexts {
            let mut tx = self.pool().begin().await?;
            let stalled = sqlx::query(
                "UPDATE orchestrationDispatchContexts SET status = 'stalled' WHERE id = ? AND status = 'dispatched'",
            )
            .bind(&ctx.id)
            .execute(&mut *tx)
            .await?
            .rows_affected()
                > 0;
            if stalled {
                record_dispatch_run_event(
                    &mut tx,
                    &ctx.id,
                    RunEventKind::TaskStalled,
                    "No activity within the lease.",
                    None,
                )
                .await?;
            }
            sqlx::query(
                "UPDATE orchestrationTasks SET status = 'stalled', stalled_at = datetime('now') WHERE id = ?",
            )
            .bind(&ctx.task_id)
            .execute(&mut *tx)
            .await?;
            tx.commit().await?;
        }
        Ok(contexts)
    }

    /// Dispatches no worker command has accepted since before the threshold
    /// (ISO lexicographic comparison). Workflow attempts are left out: their
    /// launch keeps its own startup timer.
    pub async fn unaccepted_orchestration_dispatches(
        &self,
        threshold_iso: &str,
    ) -> Result<Vec<OrchestrationDispatchContext>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE status = 'awaiting_acceptance' AND dispatched_at < ? \
             AND NOT EXISTS(SELECT 1 FROM runLaunches l \
                 WHERE l.dispatch_id = orchestrationDispatchContexts.id)"
        )))
        .bind(threshold_iso)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(dispatch_from_row).collect()
    }
}

/// Returns a stalled dispatch and its task to `dispatched`. A workflow
/// attempt whose launch no longer allows it (the run was cancelled, or the
/// attempt was settled) stays stalled.
async fn revive_stalled_dispatch(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    dispatch_id: &str,
) -> Result<bool> {
    let revived = sqlx::query(
        "UPDATE orchestrationDispatchContexts \
         SET status = 'dispatched', last_activity_at = datetime('now') \
         WHERE id = ? AND status = 'stalled'",
    )
    .bind(dispatch_id)
    .execute(&mut **tx)
    .await;
    let revived = match revived {
        Ok(result) => result.rows_affected() > 0,
        Err(sqlx::Error::Database(error)) if error.message().contains("workflow dispatch") => false,
        Err(error) => return Err(error.into()),
    };
    if revived {
        sqlx::query(
            "UPDATE orchestrationTasks SET status = 'dispatched', stalled_at = NULL \
             WHERE id = (SELECT task_id FROM orchestrationDispatchContexts WHERE id = ?) \
             AND status = 'stalled'",
        )
        .bind(dispatch_id)
        .execute(&mut **tx)
        .await?;
    }
    Ok(revived)
}

//! How a dispatch ends: failure (with the circuit breaker) or completion.

use anyhow::{anyhow, bail, Result};
use sqlx::Row;

use super::orchestration_dispatch_store::{
    dispatch_from_row, DISPATCH_COLUMNS, ORCHESTRATION_CIRCUIT_BREAKER_THRESHOLD,
};
use super::orchestration_task_store::refresh_pending_dependents_after_task_status;
use super::run_event_store::{
    record_dispatch_run_event, record_run_event, NewRunEvent, RunEventKind,
};
use super::{
    OrchestrationDispatchContext, OrchestrationDispatchStatus, OrchestrationTaskStatus,
    RuntimeStore,
};

impl RuntimeStore {
    /// Records a dispatch failure. Below the circuit-breaker threshold the
    /// task returns to `ready` (deps are already satisfied - `pending` would
    /// strand it because promotion only runs when a dep completes). At the
    /// threshold the dispatch is circuit-broken and the task fails.
    pub async fn fail_orchestration_dispatch(
        &self,
        dispatch_id: &str,
        error: &str,
    ) -> Result<OrchestrationDispatchContext> {
        self.fail_orchestration_dispatch_with_result(dispatch_id, error, None)
            .await
    }

    pub async fn fail_orchestration_dispatch_with_result(
        &self,
        dispatch_id: &str,
        error: &str,
        result: Option<&str>,
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
        let new_failure_count = ctx.failure_count + 1;
        let circuit_broken = new_failure_count >= ORCHESTRATION_CIRCUIT_BREAKER_THRESHOLD;
        let dispatch_status = if circuit_broken {
            OrchestrationDispatchStatus::CircuitBroken
        } else {
            OrchestrationDispatchStatus::Failed
        };
        let task_status = if circuit_broken {
            OrchestrationTaskStatus::Failed
        } else {
            OrchestrationTaskStatus::Ready
        };
        sqlx::query(
            "UPDATE orchestrationDispatchContexts \
             SET status = ?, failure_count = ?, last_failure = ?, completed_at = datetime('now') \
             WHERE id = ?",
        )
        .bind(dispatch_status.as_str())
        .bind(new_failure_count)
        .bind(error)
        .bind(dispatch_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE orchestrationTasks \
             SET status = ?, result = COALESCE(?, result), \
                 completed_at = CASE WHEN ? = 'failed' THEN datetime('now') ELSE NULL END \
             WHERE id = ?",
        )
        .bind(task_status.as_str())
        .bind(result)
        .bind(task_status.as_str())
        .bind(&ctx.task_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE orchestrationMessages SET state = 'obsolete', obsolete_at = datetime('now') \
             WHERE dispatch_id = ? AND state = 'queued'",
        )
        .bind(dispatch_id)
        .execute(&mut *tx)
        .await?;
        if task_status == OrchestrationTaskStatus::Failed {
            refresh_pending_dependents_after_task_status(&mut tx, &ctx.task_id).await?;
        }
        record_dispatch_run_event(
            &mut tx,
            dispatch_id,
            RunEventKind::TaskFailed,
            error,
            Some(serde_json::json!({ "willRetry": !circuit_broken })),
        )
        .await?;
        tx.commit().await?;
        self.orchestration_dispatch_by_id(dispatch_id)
            .await?
            .ok_or_else(|| anyhow!("dispatch context not found after update: {dispatch_id}"))
    }

    pub async fn complete_orchestration_dispatch(
        &self,
        dispatch_id: &str,
        assignee_handle: &str,
        result: &str,
    ) -> Result<OrchestrationDispatchContext> {
        self.complete_orchestration_dispatch_at_sha(dispatch_id, assignee_handle, result, None)
            .await
    }

    pub async fn complete_workflow_orchestration_dispatch(
        &self,
        dispatch_id: &str,
        assignee_handle: &str,
        result: &str,
        completion_sha: &str,
    ) -> Result<OrchestrationDispatchContext> {
        if completion_sha.len() != 40
            || !completion_sha
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
        {
            bail!("workflow completion requires an exact committed result SHA");
        }
        self.complete_orchestration_dispatch_at_sha(
            dispatch_id,
            assignee_handle,
            result,
            Some(completion_sha),
        )
        .await
    }

    async fn complete_orchestration_dispatch_at_sha(
        &self,
        dispatch_id: &str,
        assignee_handle: &str,
        result: &str,
        completion_sha: Option<&str>,
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
        let workflow_dispatch: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM runLaunches WHERE dispatch_id = ?)")
                .bind(dispatch_id)
                .fetch_one(&mut *tx)
                .await?;
        if workflow_dispatch != completion_sha.is_some() {
            bail!("workflow dispatch completion must include its exact result SHA");
        }
        if ctx.status == OrchestrationDispatchStatus::Completed {
            if ctx.assignee_handle.as_deref() != Some(assignee_handle) {
                bail!("dispatch completion rejected: inactive context or wrong assignee");
            }
            let task_status: Option<String> =
                sqlx::query("SELECT status FROM orchestrationTasks WHERE id = ?")
                    .bind(&ctx.task_id)
                    .fetch_optional(&mut *tx)
                    .await?
                    .map(|row| row.try_get("status"))
                    .transpose()?;
            if task_status.as_deref() != Some("completed") {
                bail!("dispatch completion rejected: dispatch closed without task completion");
            }
            if ctx.completion_sha.as_deref() != completion_sha {
                bail!("dispatch completion rejected: committed result SHA changed");
            }
            if workflow_dispatch {
                clear_resolved_workflow_launch_attention(&mut tx, dispatch_id).await?;
                tx.commit().await?;
            }
            return Ok(ctx);
        }
        if !matches!(
            ctx.status,
            OrchestrationDispatchStatus::Dispatched | OrchestrationDispatchStatus::Stalled
        ) || ctx.assignee_handle.as_deref() != Some(assignee_handle)
        {
            bail!("dispatch completion rejected: inactive context or wrong assignee");
        }
        super::orchestration_contract_store::validate_task_contract_completion(
            &mut tx,
            &ctx.task_id,
            result,
        )
        .await?;
        sqlx::query(
            "UPDATE orchestrationDispatchContexts SET status = 'completed', \
             completed_at = datetime('now'), last_activity_at = datetime('now'), \
             completion_sha = ? WHERE id = ?",
        )
        .bind(completion_sha)
        .bind(dispatch_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE orchestrationTasks SET status = 'completed', result = ?, \
             completed_at = datetime('now') WHERE id = ?",
        )
        .bind(result)
        .bind(&ctx.task_id)
        .execute(&mut *tx)
        .await?;
        if workflow_dispatch {
            clear_resolved_workflow_launch_attention(&mut tx, dispatch_id).await?;
        }
        if let Some(run_id) = ctx.run_id.as_deref() {
            // An isolated attempt's result is a commit in its own worktree, so
            // the timeline can open the exact diff; a shared task only names
            // the workspace it ran in.
            let launch =
                sqlx::query("SELECT workspace_id, base_sha FROM runLaunches WHERE dispatch_id = ?")
                    .bind(dispatch_id)
                    .fetch_optional(&mut *tx)
                    .await?;
            let payload = match launch {
                Some(launch) => serde_json::json!({
                    "workspaceId": launch.try_get::<String, _>("workspace_id")?,
                    "sha": completion_sha,
                    "baseSha": launch.try_get::<String, _>("base_sha")?,
                }),
                None => serde_json::json!({ "workspaceId": ctx.workspace_id }),
            };
            let mut event = NewRunEvent::new(run_id, RunEventKind::TaskCompleted);
            event.task_id = Some(&ctx.task_id);
            event.dispatch_id = Some(dispatch_id);
            event.summary = assignee_handle;
            event.payload = Some(payload);
            record_run_event(&mut tx, &event).await?;
        }
        refresh_pending_dependents_after_task_status(&mut tx, &ctx.task_id).await?;
        sqlx::query(
            "UPDATE orchestrationMessages SET state = 'obsolete', obsolete_at = datetime('now') \
             WHERE dispatch_id = ? AND state = 'queued'",
        )
        .bind(dispatch_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.orchestration_dispatch_by_id(dispatch_id)
            .await?
            .ok_or_else(|| anyhow!("dispatch context not found after completion"))
    }
}

async fn clear_resolved_workflow_launch_attention(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    dispatch_id: &str,
) -> Result<()> {
    // A successful immutable completion resolves a worker's earlier escalation.
    // Keep the launch receipt while leaving integration Attention independent.
    sqlx::query(
        "UPDATE runLaunches SET status = 'started', error = NULL, updated_at = datetime('now')
        WHERE dispatch_id = ? AND status = 'attention'",
    )
    .bind(dispatch_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

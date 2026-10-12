use anyhow::{anyhow, bail, Result};
use sqlx::sqlite::SqliteRow;
use sqlx::Row;

use super::orchestration_message_store::orchestration_id;
use super::{OrchestrationDispatchContext, OrchestrationDispatchStatus, RuntimeStore};

pub const ORCHESTRATION_CIRCUIT_BREAKER_THRESHOLD: i64 = 3;

pub(super) const DISPATCH_COLUMNS: &str = "id, task_id, assignee_handle, status, failure_count, \
     last_failure, dispatched_at, completed_at, created_at, run_id, workspace_id, \
     coordinator_handle, accepted_at, last_activity_at, context_token_hash, terminal_policy, startup_error, completion_sha, agent_profile, agent_quota_group";

pub(super) fn dispatch_from_row(row: SqliteRow) -> Result<OrchestrationDispatchContext> {
    let status_raw: String = row.try_get("status")?;
    Ok(OrchestrationDispatchContext {
        id: row.try_get("id")?,
        task_id: row.try_get("task_id")?,
        assignee_handle: row.try_get("assignee_handle")?,
        status: OrchestrationDispatchStatus::parse(&status_raw)
            .unwrap_or(OrchestrationDispatchStatus::Pending),
        failure_count: row.try_get("failure_count")?,
        last_failure: row.try_get("last_failure")?,
        dispatched_at: row.try_get("dispatched_at")?,
        completed_at: row.try_get("completed_at")?,
        created_at: row.try_get("created_at")?,
        run_id: row.try_get("run_id")?,
        workspace_id: row.try_get("workspace_id")?,
        coordinator_handle: row.try_get("coordinator_handle")?,
        accepted_at: row.try_get("accepted_at")?,
        last_activity_at: row.try_get("last_activity_at")?,
        context_token_hash: row.try_get("context_token_hash")?,
        terminal_policy: row.try_get("terminal_policy")?,
        startup_error: row.try_get("startup_error")?,
        completion_sha: row.try_get("completion_sha")?,
        agent_profile: row.try_get("agent_profile")?,
        agent_quota_group: row.try_get("agent_quota_group")?,
    })
}

impl RuntimeStore {
    // --- Dispatch contexts ---

    /// Assigns a ready task to a terminal. Enforces the single-active-dispatch
    /// lock per terminal and carries the failure count forward across retries
    /// so the circuit breaker accumulates.
    pub async fn create_orchestration_dispatch(
        &self,
        task_id: &str,
        assignee_handle: &str,
    ) -> Result<OrchestrationDispatchContext> {
        let dispatch = self
            .create_scoped_orchestration_dispatch(
                task_id,
                assignee_handle,
                None,
                "global",
                "coordinator",
                None,
                "keep-open",
            )
            .await?;
        self.accept_orchestration_dispatch(&dispatch.id, assignee_handle, "")
            .await
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn create_scoped_orchestration_dispatch(
        &self,
        task_id: &str,
        assignee_handle: &str,
        run_id: Option<&str>,
        workspace_id: &str,
        coordinator_handle: &str,
        context_token_hash: Option<&str>,
        terminal_policy: &str,
    ) -> Result<OrchestrationDispatchContext> {
        let mut tx = self.pool().begin().await?;
        let task_status: Option<String> =
            sqlx::query("SELECT status FROM orchestrationTasks WHERE id = ?")
                .bind(task_id)
                .fetch_optional(&mut *tx)
                .await?
                .map(|row| row.try_get("status"))
                .transpose()?;
        match task_status.as_deref() {
            None => bail!("orchestration task not found: {task_id}"),
            Some("ready") => {}
            Some(other) => bail!("task {task_id} is not ready (status: {other})"),
        }
        let busy: Option<String> = sqlx::query(
            "SELECT id FROM orchestrationDispatchContexts \
             WHERE assignee_handle = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled') LIMIT 1",
        )
        .bind(assignee_handle)
        .fetch_optional(&mut *tx)
        .await?
        .map(|row| row.try_get("id"))
        .transpose()?;
        if busy.is_some() {
            bail!("terminal {assignee_handle} already has an active dispatch");
        }
        let carried_failures: i64 = sqlx::query(
            "SELECT COALESCE(MAX(failure_count), 0) AS count \
             FROM orchestrationDispatchContexts WHERE task_id = ?",
        )
        .bind(task_id)
        .fetch_one(&mut *tx)
        .await?
        .try_get("count")?;
        let id = orchestration_id("ctx");
        super::run_dispatch::create_run_dispatch(
            &mut tx,
            &super::run_dispatch::NewRunDispatch {
                id: &id,
                task_id,
                run_id,
                workspace_id,
                context_token_hash,
                failure_count: carried_failures,
                target: super::run_dispatch::DispatchTarget::Terminal {
                    handle: assignee_handle,
                    coordinator_handle,
                    terminal_policy,
                },
            },
        )
        .await?;
        tx.commit().await?;
        self.orchestration_dispatch_by_id(&id)
            .await?
            .ok_or_else(|| anyhow!("inserted dispatch context not found"))
    }

    pub async fn orchestration_dispatch_by_id(
        &self,
        id: &str,
    ) -> Result<Option<OrchestrationDispatchContext>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts WHERE id = ?"
        )))
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(dispatch_from_row).transpose()
    }

    /// The current active dispatch for a task, if any.
    pub async fn active_orchestration_dispatch_for_task(
        &self,
        task_id: &str,
    ) -> Result<Option<OrchestrationDispatchContext>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled') \
             ORDER BY rowid DESC LIMIT 1"
        )))
        .bind(task_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(dispatch_from_row).transpose()
    }

    pub async fn active_orchestration_dispatch_for_handle(
        &self,
        assignee_handle: &str,
    ) -> Result<Option<OrchestrationDispatchContext>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE assignee_handle = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled') \
             ORDER BY rowid DESC LIMIT 1"
        )))
        .bind(assignee_handle)
        .fetch_optional(self.pool())
        .await?;
        row.map(dispatch_from_row).transpose()
    }

    pub async fn latest_orchestration_dispatch_for_handle(
        &self,
        assignee_handle: &str,
    ) -> Result<Option<OrchestrationDispatchContext>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE assignee_handle = ? ORDER BY rowid DESC LIMIT 1"
        )))
        .bind(assignee_handle)
        .fetch_optional(self.pool())
        .await?;
        row.map(dispatch_from_row).transpose()
    }

    pub async fn list_orchestration_dispatches_for_task(
        &self,
        task_id: &str,
    ) -> Result<Vec<OrchestrationDispatchContext>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE task_id = ? ORDER BY rowid ASC"
        )))
        .bind(task_id)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(dispatch_from_row).collect()
    }
}

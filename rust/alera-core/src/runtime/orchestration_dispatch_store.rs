use anyhow::{anyhow, bail, Result};
use sqlx::sqlite::SqliteRow;
use sqlx::Row;

use super::orchestration_message_store::orchestration_id;
use super::orchestration_task_store::{
    parse_string_array, refresh_pending_dependents_after_task_status,
};
use super::{
    OrchestrationDecisionGate, OrchestrationDispatchContext, OrchestrationDispatchStatus,
    OrchestrationGateStatus, OrchestrationTaskStatus, RuntimeStore,
};

pub const ORCHESTRATION_CIRCUIT_BREAKER_THRESHOLD: i64 = 3;

const DISPATCH_COLUMNS: &str = "id, task_id, assignee_handle, status, failure_count, \
     last_failure, dispatched_at, completed_at, created_at, last_heartbeat_at, run_id, workspace_id, \
     coordinator_handle, accepted_at, last_activity_at, context_token_hash, completion_policy, \
     terminal_policy, startup_error, completion_sha, agent_profile, agent_quota_group";

const GATE_COLUMNS: &str =
    "id, task_id, question, options, status, resolution, created_at, resolved_at";

fn dispatch_from_row(row: SqliteRow) -> Result<OrchestrationDispatchContext> {
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
        last_heartbeat_at: row.try_get("last_heartbeat_at")?,
        run_id: row.try_get("run_id")?,
        workspace_id: row.try_get("workspace_id")?,
        coordinator_handle: row.try_get("coordinator_handle")?,
        accepted_at: row.try_get("accepted_at")?,
        last_activity_at: row.try_get("last_activity_at")?,
        context_token_hash: row.try_get("context_token_hash")?,
        completion_policy: row.try_get("completion_policy")?,
        terminal_policy: row.try_get("terminal_policy")?,
        startup_error: row.try_get("startup_error")?,
        completion_sha: row.try_get("completion_sha")?,
        agent_profile: row.try_get("agent_profile")?,
        agent_quota_group: row.try_get("agent_quota_group")?,
    })
}

fn gate_from_row(row: SqliteRow) -> Result<OrchestrationDecisionGate> {
    let status_raw: String = row.try_get("status")?;
    let options_raw: String = row.try_get("options")?;
    Ok(OrchestrationDecisionGate {
        id: row.try_get("id")?,
        task_id: row.try_get("task_id")?,
        question: row.try_get("question")?,
        options: parse_string_array(&options_raw),
        status: OrchestrationGateStatus::parse(&status_raw)
            .unwrap_or(OrchestrationGateStatus::Pending),
        resolution: row.try_get("resolution")?,
        created_at: row.try_get("created_at")?,
        resolved_at: row.try_get("resolved_at")?,
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
                "return-immediately",
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
        completion_policy: &str,
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
        sqlx::query(
            "INSERT INTO orchestrationDispatchContexts \
             (id, task_id, assignee_handle, status, failure_count, dispatched_at, run_id, \
              workspace_id, coordinator_handle, context_token_hash, completion_policy, terminal_policy, \
              last_activity_at) \
             VALUES (?, ?, ?, 'awaiting_acceptance', ?, datetime('now'), ?, ?, ?, ?, ?, ?, datetime('now'))",
        )
        .bind(&id)
        .bind(task_id)
        .bind(assignee_handle)
        .bind(carried_failures)
        .bind(run_id)
        .bind(workspace_id)
        .bind(coordinator_handle)
        .bind(context_token_hash)
        .bind(completion_policy)
        .bind(terminal_policy)
        .execute(&mut *tx)
        .await?;
        sqlx::query("UPDATE orchestrationTasks SET status = 'dispatched' WHERE id = ?")
            .bind(task_id)
            .execute(&mut *tx)
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
        tx.commit().await?;
        self.orchestration_dispatch_by_id(dispatch_id)
            .await?
            .ok_or_else(|| anyhow!("dispatch context not found after update: {dispatch_id}"))
    }

    /// Records a heartbeat only while the dispatch is still active, so a
    /// straggler from a completed or failed context cannot refresh liveness.
    pub async fn record_orchestration_heartbeat(&self, dispatch_id: &str) -> Result<bool> {
        let result = sqlx::query(
            "UPDATE orchestrationDispatchContexts \
             SET last_heartbeat_at = datetime('now') \
             WHERE id = ? AND status IN ('dispatched','awaiting_acceptance')",
        )
        .bind(dispatch_id)
        .execute(self.pool())
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn accept_orchestration_dispatch(
        &self,
        dispatch_id: &str,
        assignee_handle: &str,
        context_token_hash: &str,
    ) -> Result<OrchestrationDispatchContext> {
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
        .execute(self.pool())
        .await?;
        if result.rows_affected() == 0 {
            bail!("dispatch acceptance rejected: stale context or wrong assignee");
        }
        self.orchestration_dispatch_by_id(dispatch_id)
            .await?
            .ok_or_else(|| anyhow!("dispatch context not found after acceptance: {dispatch_id}"))
    }

    pub async fn record_orchestration_activity(&self, dispatch_id: &str) -> Result<bool> {
        let mut tx = self.pool().begin().await?;
        let result = sqlx::query(
            "UPDATE orchestrationDispatchContexts SET last_activity_at = datetime('now') \
             WHERE id = ? AND status = 'dispatched'",
        )
        .bind(dispatch_id)
        .execute(&mut *tx)
        .await?;
        if result.rows_affected() > 0 {
            sqlx::query(
                "UPDATE orchestrationCoordinatorRuns SET last_activity_at = datetime('now') \
                 WHERE id = (SELECT run_id FROM orchestrationDispatchContexts WHERE id = ?)",
            )
            .bind(dispatch_id)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(result.rows_affected() > 0)
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
        tx.commit().await?;
        self.orchestration_dispatch_by_id(dispatch_id)
            .await?
            .ok_or_else(|| anyhow!("dispatch context not found after startup failure"))
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
        let workflow_dispatch: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowLaunches WHERE dispatch_id = ?)",
        )
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
            return Ok(ctx);
        }
        if ctx.status != OrchestrationDispatchStatus::Dispatched
            || ctx.assignee_handle.as_deref() != Some(assignee_handle)
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
            sqlx::query(
                "UPDATE orchestrationDispatchContexts SET status = 'stalled' WHERE id = ? AND status = 'dispatched'",
            )
            .bind(&ctx.id)
            .execute(&mut *tx)
            .await?;
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

    pub async fn expire_unaccepted_orchestration_dispatches(
        &self,
        threshold_iso: &str,
    ) -> Result<Vec<OrchestrationDispatchContext>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE status = 'awaiting_acceptance' AND dispatched_at < ? \
             AND NOT EXISTS(SELECT 1 FROM workflowLaunches l \
                 WHERE l.dispatch_id = orchestrationDispatchContexts.id)"
        )))
        .bind(threshold_iso)
        .fetch_all(self.pool())
        .await?;
        let contexts: Vec<_> = rows
            .into_iter()
            .map(dispatch_from_row)
            .collect::<Result<_>>()?;
        let mut expired = Vec::with_capacity(contexts.len());
        for ctx in contexts {
            expired.push(
                self.fail_orchestration_startup(&ctx.id, "dispatch acceptance timed out")
                    .await?,
            );
        }
        Ok(expired)
    }

    /// Dispatched contexts whose dispatch and last heartbeat both predate the
    /// threshold (ISO lexicographic comparison).
    pub async fn stale_orchestration_dispatches(
        &self,
        threshold_iso: &str,
    ) -> Result<Vec<OrchestrationDispatchContext>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE status IN ('dispatched','awaiting_acceptance') AND dispatched_at < ? \
             AND (last_heartbeat_at IS NULL OR last_heartbeat_at < ?)"
        )))
        .bind(threshold_iso)
        .bind(threshold_iso)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(dispatch_from_row).collect()
    }

    // --- Decision gates ---

    /// Creates a gate: blocks the task and completes its active dispatch so
    /// the worker terminal is released while the question is pending.
    pub async fn create_orchestration_gate(
        &self,
        task_id: &str,
        question: &str,
        options: &[String],
    ) -> Result<OrchestrationDecisionGate> {
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
            Some("ready") | Some("dispatched") => {}
            Some(other) => bail!("task {task_id} cannot be gated while {other}"),
        }
        let id = orchestration_id("gate");
        sqlx::query(
            "INSERT INTO orchestrationDecisionGates (id, task_id, question, options) \
             VALUES (?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(task_id)
        .bind(question)
        .bind(serde_json::to_string(options)?)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE orchestrationDispatchContexts \
             SET status = 'completed', completed_at = datetime('now') \
             WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled')",
        )
        .bind(task_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query("UPDATE orchestrationTasks SET status = 'blocked' WHERE id = ?")
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        self.orchestration_gate_by_id(&id)
            .await?
            .ok_or_else(|| anyhow!("inserted decision gate not found"))
    }

    pub async fn orchestration_gate_by_id(
        &self,
        id: &str,
    ) -> Result<Option<OrchestrationDecisionGate>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {GATE_COLUMNS} FROM orchestrationDecisionGates WHERE id = ?"
        )))
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(gate_from_row).transpose()
    }

    /// Resolves a gate and returns the task to `ready` when it is still
    /// blocked, so the coordinator can re-dispatch it with the resolution
    /// included in the next preamble.
    pub async fn resolve_orchestration_gate(
        &self,
        gate_id: &str,
        resolution: &str,
    ) -> Result<OrchestrationDecisionGate> {
        let mut tx = self.pool().begin().await?;
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {GATE_COLUMNS} FROM orchestrationDecisionGates WHERE id = ?"
        )))
        .bind(gate_id)
        .fetch_optional(&mut *tx)
        .await?;
        let gate = row
            .map(gate_from_row)
            .transpose()?
            .ok_or_else(|| anyhow!("decision gate not found: {gate_id}"))?;
        if gate.status != OrchestrationGateStatus::Pending {
            bail!("decision gate {gate_id} is not pending");
        }
        sqlx::query(
            "UPDATE orchestrationDecisionGates \
             SET status = 'resolved', resolution = ?, resolved_at = datetime('now') \
             WHERE id = ?",
        )
        .bind(resolution)
        .bind(gate_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE orchestrationTasks SET status = 'ready' \
             WHERE id = ? AND status = 'blocked'",
        )
        .bind(&gate.task_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.orchestration_gate_by_id(gate_id)
            .await?
            .ok_or_else(|| anyhow!("decision gate not found after update: {gate_id}"))
    }

    pub async fn list_orchestration_gates(
        &self,
        task_id: Option<&str>,
        status: Option<OrchestrationGateStatus>,
    ) -> Result<Vec<OrchestrationDecisionGate>> {
        let mut sql = format!("SELECT {GATE_COLUMNS} FROM orchestrationDecisionGates");
        let mut clauses = Vec::new();
        if task_id.is_some() {
            clauses.push("task_id = ?");
        }
        if status.is_some() {
            clauses.push("status = ?");
        }
        if !clauses.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&clauses.join(" AND "));
        }
        sql.push_str(" ORDER BY created_at ASC, rowid ASC");
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        if let Some(task_id) = task_id {
            query = query.bind(task_id);
        }
        if let Some(status) = status {
            query = query.bind(status.as_str());
        }
        let rows = query.fetch_all(self.pool()).await?;
        rows.into_iter().map(gate_from_row).collect()
    }
}

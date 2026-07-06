use anyhow::{anyhow, bail, Result};
use sqlx::sqlite::SqliteRow;
use sqlx::Row;

use super::orchestration_message_store::orchestration_id;
use super::orchestration_task_store::{
    parse_string_array, refresh_pending_dependents_after_task_status,
};
use super::{
    OrchestrationCoordinatorRun, OrchestrationCoordinatorStatus, OrchestrationDecisionGate,
    OrchestrationDispatchContext, OrchestrationDispatchStatus, OrchestrationGateStatus,
    OrchestrationTaskStatus, RuntimeStore,
};

pub const ORCHESTRATION_CIRCUIT_BREAKER_THRESHOLD: i64 = 3;

const DISPATCH_COLUMNS: &str = "id, task_id, assignee_handle, status, failure_count, \
     last_failure, dispatched_at, completed_at, created_at, last_heartbeat_at";

const GATE_COLUMNS: &str =
    "id, task_id, question, options, status, resolution, created_at, resolved_at";

const RUN_COLUMNS: &str =
    "id, spec, status, coordinator_handle, poll_interval_ms, created_at, completed_at";

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

fn run_from_row(row: SqliteRow) -> Result<OrchestrationCoordinatorRun> {
    let status_raw: String = row.try_get("status")?;
    Ok(OrchestrationCoordinatorRun {
        id: row.try_get("id")?,
        spec: row.try_get("spec")?,
        status: OrchestrationCoordinatorStatus::parse(&status_raw)
            .unwrap_or(OrchestrationCoordinatorStatus::Idle),
        coordinator_handle: row.try_get("coordinator_handle")?,
        poll_interval_ms: row.try_get("poll_interval_ms")?,
        created_at: row.try_get("created_at")?,
        completed_at: row.try_get("completed_at")?,
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
             WHERE assignee_handle = ? AND status IN ('pending','dispatched') LIMIT 1",
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
             (id, task_id, assignee_handle, status, failure_count, dispatched_at) \
             VALUES (?, ?, ?, 'dispatched', ?, datetime('now'))",
        )
        .bind(&id)
        .bind(task_id)
        .bind(assignee_handle)
        .bind(carried_failures)
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
        let row = sqlx::query(&format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts WHERE id = ?"
        ))
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
        let row = sqlx::query(&format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE task_id = ? AND status IN ('pending','dispatched') \
             ORDER BY rowid DESC LIMIT 1"
        ))
        .bind(task_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(dispatch_from_row).transpose()
    }

    pub async fn active_orchestration_dispatch_for_handle(
        &self,
        assignee_handle: &str,
    ) -> Result<Option<OrchestrationDispatchContext>> {
        let row = sqlx::query(&format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE assignee_handle = ? AND status IN ('pending','dispatched') \
             ORDER BY rowid DESC LIMIT 1"
        ))
        .bind(assignee_handle)
        .fetch_optional(self.pool())
        .await?;
        row.map(dispatch_from_row).transpose()
    }

    pub async fn list_orchestration_dispatches_for_task(
        &self,
        task_id: &str,
    ) -> Result<Vec<OrchestrationDispatchContext>> {
        let rows = sqlx::query(&format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE task_id = ? ORDER BY rowid ASC"
        ))
        .bind(task_id)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(dispatch_from_row).collect()
    }

    /// Records a dispatch failure. Below the circuit-breaker threshold the
    /// task returns to `ready` (deps are already satisfied — `pending` would
    /// strand it because promotion only runs when a dep completes). At the
    /// threshold the dispatch is circuit-broken and the task fails.
    pub async fn fail_orchestration_dispatch(
        &self,
        dispatch_id: &str,
        error: &str,
    ) -> Result<OrchestrationDispatchContext> {
        let mut tx = self.pool().begin().await?;
        let row = sqlx::query(&format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts WHERE id = ?"
        ))
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
             SET status = ?, \
                 completed_at = CASE WHEN ? = 'failed' THEN datetime('now') ELSE NULL END \
             WHERE id = ?",
        )
        .bind(task_status.as_str())
        .bind(task_status.as_str())
        .bind(&ctx.task_id)
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
             WHERE id = ? AND status = 'dispatched'",
        )
        .bind(dispatch_id)
        .execute(self.pool())
        .await?;
        Ok(result.rows_affected() > 0)
    }

    /// Dispatched contexts whose dispatch and last heartbeat both predate the
    /// threshold (ISO lexicographic comparison).
    pub async fn stale_orchestration_dispatches(
        &self,
        threshold_iso: &str,
    ) -> Result<Vec<OrchestrationDispatchContext>> {
        let rows = sqlx::query(&format!(
            "SELECT {DISPATCH_COLUMNS} FROM orchestrationDispatchContexts \
             WHERE status = 'dispatched' AND dispatched_at < ? \
             AND (last_heartbeat_at IS NULL OR last_heartbeat_at < ?)"
        ))
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
             WHERE task_id = ? AND status IN ('pending','dispatched')",
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
        let row = sqlx::query(&format!(
            "SELECT {GATE_COLUMNS} FROM orchestrationDecisionGates WHERE id = ?"
        ))
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
        let row = sqlx::query(&format!(
            "SELECT {GATE_COLUMNS} FROM orchestrationDecisionGates WHERE id = ?"
        ))
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
        let mut query = sqlx::query(&sql);
        if let Some(task_id) = task_id {
            query = query.bind(task_id);
        }
        if let Some(status) = status {
            query = query.bind(status.as_str());
        }
        let rows = query.fetch_all(self.pool()).await?;
        rows.into_iter().map(gate_from_row).collect()
    }

    // --- Coordinator runs ---

    pub async fn create_orchestration_coordinator_run(
        &self,
        spec: &str,
        coordinator_handle: Option<&str>,
        poll_interval_ms: i64,
    ) -> Result<OrchestrationCoordinatorRun> {
        let mut tx = self.pool().begin().await?;
        let active: Option<String> = sqlx::query(
            "SELECT id FROM orchestrationCoordinatorRuns WHERE status = 'running' LIMIT 1",
        )
        .fetch_optional(&mut *tx)
        .await?
        .map(|row| row.try_get("id"))
        .transpose()?;
        if let Some(active_id) = active {
            bail!("a coordinator run is already active: {active_id}");
        }
        let id = orchestration_id("run");
        sqlx::query(
            "INSERT INTO orchestrationCoordinatorRuns \
             (id, spec, status, coordinator_handle, poll_interval_ms) \
             VALUES (?, ?, 'running', ?, ?)",
        )
        .bind(&id)
        .bind(spec)
        .bind(coordinator_handle)
        .bind(poll_interval_ms)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.orchestration_coordinator_run_by_id(&id)
            .await?
            .ok_or_else(|| anyhow!("inserted coordinator run not found"))
    }

    pub async fn orchestration_coordinator_run_by_id(
        &self,
        id: &str,
    ) -> Result<Option<OrchestrationCoordinatorRun>> {
        let row = sqlx::query(&format!(
            "SELECT {RUN_COLUMNS} FROM orchestrationCoordinatorRuns WHERE id = ?"
        ))
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(run_from_row).transpose()
    }

    pub async fn active_orchestration_coordinator_run(
        &self,
    ) -> Result<Option<OrchestrationCoordinatorRun>> {
        let row = sqlx::query(&format!(
            "SELECT {RUN_COLUMNS} FROM orchestrationCoordinatorRuns \
             WHERE status = 'running' ORDER BY created_at DESC LIMIT 1"
        ))
        .fetch_optional(self.pool())
        .await?;
        row.map(run_from_row).transpose()
    }

    pub async fn finish_orchestration_coordinator_run(
        &self,
        id: &str,
        status: OrchestrationCoordinatorStatus,
    ) -> Result<()> {
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns \
             SET status = ?, completed_at = datetime('now') WHERE id = ?",
        )
        .bind(status.as_str())
        .bind(id)
        .execute(self.pool())
        .await?;
        Ok(())
    }
}

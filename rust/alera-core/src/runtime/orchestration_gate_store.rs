//! `runGates`: every decision a person or the runtime must take before a task
//! or run continues. Decision and stall gates belong to a task; plan and stage
//! gates belong to a run.
//!
//! Store errors that a client can act on start with a `gate_` code, so the
//! host can surface them as conflicts.

use anyhow::{anyhow, bail, Result};
use sqlx::sqlite::SqliteRow;
use sqlx::{Row, SqliteConnection};

use super::orchestration_message_store::orchestration_id;
use super::orchestration_task_store::parse_string_array;
use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::{OrchestrationDecisionGate, OrchestrationGateStatus, RunGateKind, RuntimeStore};

pub(super) const GATE_COLUMNS: &str = "id, run_id, task_id, kind, question, options, status, \
     resolution, created_at, resolved_at";

/// Whether a run has a plan gate nobody has resolved yet. `{run}` names the
/// `orchestrationCoordinatorRuns` row in the surrounding query.
pub(super) const RUN_PENDING_PLAN_GATE_SQL: &str = "EXISTS(SELECT 1 FROM runGates g \
     WHERE g.run_id = {run}.id AND g.kind = 'plan' AND g.status = 'pending')";

pub const PLAN_GATE_APPROVE: &str = "approve";
pub const PLAN_GATE_REQUEST_CHANGES: &str = "requestChanges";
pub const PLAN_GATE_REJECT: &str = "reject";
/// The fixed options of `plan` and `stage` gates.
pub const RUN_GATE_OPTIONS: [&str; 3] = [
    PLAN_GATE_APPROVE,
    PLAN_GATE_REQUEST_CHANGES,
    PLAN_GATE_REJECT,
];

pub const STALL_GATE_KILL_AND_FAILOVER: &str = "killAndFailover";
pub const STALL_GATE_KEEP_WAITING: &str = "keepWaiting";
pub const STALL_GATE_ABORT_STAGE: &str = "abortStage";
/// The fixed options of a stall gate.
pub const STALL_GATE_OPTIONS: [&str; 3] = [
    STALL_GATE_KILL_AND_FAILOVER,
    STALL_GATE_KEEP_WAITING,
    STALL_GATE_ABORT_STAGE,
];
/// Internal resolution of a stall gate whose worker showed activity again.
/// It is never offered as an option and the stall processing ignores it.
pub const STALL_GATE_RESUMED: &str = "resumed";

pub(super) const PLAN_GATE_QUESTION: &str = "Approve the execution plan?";

/// Filters for [`RuntimeStore::list_gates`]; every field narrows the list.
#[derive(Debug, Clone, Default)]
pub struct GateFilter {
    pub run_id: Option<String>,
    pub task_id: Option<String>,
    pub kind: Option<RunGateKind>,
    pub status: Option<OrchestrationGateStatus>,
}

pub(super) fn gate_from_row(row: SqliteRow) -> Result<OrchestrationDecisionGate> {
    let status_raw: String = row.try_get("status")?;
    let kind_raw: String = row.try_get("kind")?;
    let options_raw: String = row.try_get("options")?;
    Ok(OrchestrationDecisionGate {
        id: row.try_get("id")?,
        run_id: row.try_get("run_id")?,
        task_id: row
            .try_get::<Option<String>, _>("task_id")?
            .unwrap_or_default(),
        kind: RunGateKind::parse(&kind_raw).unwrap_or(RunGateKind::Decision),
        question: row.try_get("question")?,
        options: parse_string_array(&options_raw),
        status: OrchestrationGateStatus::parse(&status_raw)
            .unwrap_or(OrchestrationGateStatus::Pending),
        resolution: row.try_get("resolution")?,
        created_at: row.try_get("created_at")?,
        resolved_at: row.try_get("resolved_at")?,
    })
}

/// Opens a task gate. The run is taken from the task, so a gate on a task
/// outside any run has no `run_id` and no timeline event.
pub(super) async fn insert_task_gate(
    conn: &mut SqliteConnection,
    kind: RunGateKind,
    task_id: &str,
    question: &str,
    options: &[String],
) -> Result<String> {
    let id = orchestration_id("gate");
    let run_id: Option<String> = sqlx::query_scalar(
        "INSERT INTO runGates (id, run_id, task_id, kind, question, options) \
         SELECT ?, run_id, id, ?, ?, ? FROM orchestrationTasks WHERE id = ? RETURNING run_id",
    )
    .bind(&id)
    .bind(kind.as_str())
    .bind(question)
    .bind(serde_json::to_string(options)?)
    .bind(task_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or_else(|| anyhow!("orchestration task not found: {task_id}"))?;
    if let Some(run_id) = run_id.as_deref() {
        let mut event = NewRunEvent::new(run_id, RunEventKind::GateOpened);
        event.task_id = Some(task_id);
        event.gate_id = Some(&id);
        event.summary = question;
        event.payload = Some(serde_json::json!({ "kind": kind.as_str() }));
        record_run_event(conn, &event).await?;
    }
    Ok(id)
}

impl RuntimeStore {
    /// Creates a decision gate: blocks the task and completes its active
    /// dispatch so the worker terminal is released while the question is pending.
    pub async fn create_orchestration_gate(
        &self,
        task_id: &str,
        question: &str,
        options: &[String],
    ) -> Result<OrchestrationDecisionGate> {
        let mut tx = self.pool().begin().await?;
        let task_status: Option<String> =
            sqlx::query_scalar("SELECT status FROM orchestrationTasks WHERE id = ?")
                .bind(task_id)
                .fetch_optional(&mut *tx)
                .await?;
        match task_status.as_deref() {
            None => bail!("orchestration task not found: {task_id}"),
            Some("ready") | Some("dispatched") => {}
            Some(other) => bail!("task {task_id} cannot be gated while {other}"),
        }
        let id =
            insert_task_gate(&mut tx, RunGateKind::Decision, task_id, question, options).await?;
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
            "SELECT {GATE_COLUMNS} FROM runGates WHERE id = ?"
        )))
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(gate_from_row).transpose()
    }

    /// Gates matching every given filter, oldest first.
    pub async fn list_gates(&self, filter: &GateFilter) -> Result<Vec<OrchestrationDecisionGate>> {
        let mut sql = format!("SELECT {GATE_COLUMNS} FROM runGates WHERE 1 = 1");
        if filter.run_id.is_some() {
            sql.push_str(" AND run_id = ?");
        }
        if filter.task_id.is_some() {
            sql.push_str(" AND task_id = ?");
        }
        if filter.kind.is_some() {
            sql.push_str(" AND kind = ?");
        }
        if filter.status.is_some() {
            sql.push_str(" AND status = ?");
        }
        sql.push_str(" ORDER BY created_at ASC, rowid ASC");
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        if let Some(run_id) = &filter.run_id {
            query = query.bind(run_id);
        }
        if let Some(task_id) = &filter.task_id {
            query = query.bind(task_id);
        }
        if let Some(kind) = filter.kind {
            query = query.bind(kind.as_str());
        }
        if let Some(status) = filter.status {
            query = query.bind(status.as_str());
        }
        let rows = query.fetch_all(self.pool()).await?;
        rows.into_iter().map(gate_from_row).collect()
    }

    /// Task gates (decision and stall), oldest first.
    pub async fn list_orchestration_gates(
        &self,
        task_id: Option<&str>,
        status: Option<OrchestrationGateStatus>,
    ) -> Result<Vec<OrchestrationDecisionGate>> {
        let mut gates = self
            .list_gates(&GateFilter {
                task_id: task_id.map(str::to_string),
                status,
                ..GateFilter::default()
            })
            .await?;
        gates.retain(|gate| matches!(gate.kind, RunGateKind::Decision | RunGateKind::Stall));
        Ok(gates)
    }

    /// Every gate of a run, any kind, oldest first.
    pub async fn list_run_gates(&self, run_id: &str) -> Result<Vec<OrchestrationDecisionGate>> {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {GATE_COLUMNS} FROM runGates WHERE run_id = ? ORDER BY rowid ASC"
        )))
        .bind(run_id)
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(gate_from_row)
        .collect()
    }
}

pub(super) fn prefixed_gate_columns(alias: &str) -> String {
    GATE_COLUMNS
        .split(", ")
        .map(|column| format!("{alias}.{column}"))
        .collect::<Vec<_>>()
        .join(", ")
}

//! Coordinator run rows: creation, lookup, lifecycle, and ownership transfer.
//! Split out of the dispatch store so each file covers one lifecycle object.

use anyhow::{anyhow, bail, Result};
use sqlx::sqlite::SqliteRow;
use sqlx::Row;

use super::orchestration_message_store::orchestration_id;
use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::{OrchestrationCoordinatorRun, OrchestrationCoordinatorStatus, RuntimeStore};

/// Run columns for a query over `orchestrationCoordinatorRuns` without an alias.
pub(super) fn run_columns() -> String {
    "id, spec, status, coordinator_handle, poll_interval_ms, created_at, completed_at, \
     workspace_id, max_concurrent, last_activity_at, stop_reason, execution_policy, \
     approval_required, stall_policy, paused_by, isolation, attention_reason, plan_revision, \
     control_sequence, coordinator_tab_id"
        .to_string()
}

/// Same predicate as `OrchestrationCoordinatorRun::holds_workspace`.
pub(super) const RUN_HOLDS_WORKSPACE_SQL: &str = "(status IN ('planning','awaitingApproval',\
     'running','paused') OR (status = 'cancelled' AND completed_at IS NULL))";

/// How a shared run starts: whether its plan waits for a person's approval
/// before any worker is dispatched, and how stalled workers are handled.
#[derive(Debug, Clone, Copy)]
pub struct NewRunPlan<'a> {
    pub approval_required: bool,
    pub stall_policy: &'a str,
}

impl Default for NewRunPlan<'_> {
    fn default() -> Self {
        Self {
            approval_required: false,
            stall_policy: "ask",
        }
    }
}

pub(super) fn run_from_row(row: SqliteRow) -> Result<OrchestrationCoordinatorRun> {
    let status_raw: String = row.try_get("status")?;
    Ok(OrchestrationCoordinatorRun {
        id: row.try_get("id")?,
        spec: row.try_get("spec")?,
        status: OrchestrationCoordinatorStatus::parse(&status_raw)
            .unwrap_or(OrchestrationCoordinatorStatus::Paused),
        coordinator_handle: row.try_get("coordinator_handle")?,
        poll_interval_ms: row.try_get("poll_interval_ms")?,
        created_at: row.try_get("created_at")?,
        completed_at: row.try_get("completed_at")?,
        workspace_id: row.try_get("workspace_id")?,
        max_concurrent: row.try_get("max_concurrent")?,
        last_activity_at: row.try_get("last_activity_at")?,
        stop_reason: row.try_get("stop_reason")?,
        execution_policy: row.try_get("execution_policy")?,
        approval_required: row.try_get("approval_required")?,
        stall_policy: row.try_get("stall_policy")?,
        paused_by: row.try_get("paused_by")?,
        isolation: row.try_get("isolation")?,
        attention_reason: row.try_get("attention_reason")?,
        plan_revision: row.try_get("plan_revision")?,
        control_sequence: row.try_get("control_sequence")?,
        coordinator_tab_id: row.try_get("coordinator_tab_id")?,
    })
}

impl RuntimeStore {
    // --- Coordinator runs ---

    pub async fn create_orchestration_coordinator_run(
        &self,
        spec: &str,
        coordinator_handle: Option<&str>,
        poll_interval_ms: i64,
    ) -> Result<OrchestrationCoordinatorRun> {
        self.create_scoped_orchestration_coordinator_run(
            spec,
            coordinator_handle,
            poll_interval_ms,
            "global",
            4,
        )
        .await
    }

    pub async fn create_scoped_orchestration_coordinator_run(
        &self,
        spec: &str,
        coordinator_handle: Option<&str>,
        poll_interval_ms: i64,
        workspace_id: &str,
        max_concurrent: i64,
    ) -> Result<OrchestrationCoordinatorRun> {
        self.create_planned_orchestration_coordinator_run(
            spec,
            coordinator_handle,
            poll_interval_ms,
            workspace_id,
            max_concurrent,
            NewRunPlan::default(),
        )
        .await
    }

    /// Creates a shared run. With `approval_required` it starts `planning`
    /// and waits for a plan; otherwise it starts `running`.
    pub async fn create_planned_orchestration_coordinator_run(
        &self,
        spec: &str,
        coordinator_handle: Option<&str>,
        poll_interval_ms: i64,
        workspace_id: &str,
        max_concurrent: i64,
        plan: NewRunPlan<'_>,
    ) -> Result<OrchestrationCoordinatorRun> {
        let mut tx = self.pool().begin().await?;
        let active: Option<String> = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT id FROM orchestrationCoordinatorRuns \
             WHERE workspace_id = ? AND {RUN_HOLDS_WORKSPACE_SQL} LIMIT 1"
        )))
        .bind(workspace_id)
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
             (id, spec, status, coordinator_handle, poll_interval_ms, workspace_id, max_concurrent, \
              approval_required, stall_policy, isolation) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'shared')",
        )
        .bind(&id)
        .bind(spec)
        .bind(if plan.approval_required {
            OrchestrationCoordinatorStatus::Planning.as_str()
        } else {
            OrchestrationCoordinatorStatus::Running.as_str()
        })
        .bind(coordinator_handle)
        .bind(poll_interval_ms)
        .bind(workspace_id)
        .bind(max_concurrent)
        .bind(plan.approval_required)
        .bind(plan.stall_policy)
        .execute(&mut *tx)
        .await?;
        let mut created = NewRunEvent::new(&id, RunEventKind::Created);
        created.summary = spec;
        record_run_event(&mut tx, &created).await?;
        tx.commit().await?;
        self.orchestration_coordinator_run_by_id(&id)
            .await?
            .ok_or_else(|| anyhow!("inserted coordinator run not found"))
    }

    pub async fn orchestration_coordinator_run_by_id(
        &self,
        id: &str,
    ) -> Result<Option<OrchestrationCoordinatorRun>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {} FROM orchestrationCoordinatorRuns WHERE id = ?",
            run_columns()
        )))
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(run_from_row).transpose()
    }

    pub async fn active_orchestration_coordinator_run(
        &self,
    ) -> Result<Option<OrchestrationCoordinatorRun>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {} FROM orchestrationCoordinatorRuns \
             WHERE status = 'running' ORDER BY created_at DESC LIMIT 1",
            run_columns()
        )))
        .fetch_optional(self.pool())
        .await?;
        row.map(run_from_row).transpose()
    }

    /// Running shared runs whose coordinator the runtime did not launch.
    pub async fn running_shared_runs(&self) -> Result<Vec<OrchestrationCoordinatorRun>> {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {} FROM orchestrationCoordinatorRuns \
             WHERE status = 'running' AND isolation = 'shared' AND coordinator_tab_id IS NULL \
             ORDER BY created_at LIMIT 200",
            run_columns()
        )))
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(run_from_row)
        .collect()
    }

    pub async fn list_orchestration_coordinator_runs(
        &self,
        workspace_id: Option<&str>,
    ) -> Result<Vec<OrchestrationCoordinatorRun>> {
        let mut sql = format!("SELECT {} FROM orchestrationCoordinatorRuns", run_columns());
        if workspace_id.is_some() {
            sql.push_str(" WHERE workspace_id = ?");
        }
        sql.push_str(" ORDER BY created_at DESC, id DESC");
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        if let Some(workspace_id) = workspace_id {
            query = query.bind(workspace_id);
        }
        query
            .fetch_all(self.pool())
            .await?
            .into_iter()
            .map(run_from_row)
            .collect()
    }

    pub async fn finish_orchestration_coordinator_run(
        &self,
        id: &str,
        status: OrchestrationCoordinatorStatus,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        let changed = sqlx::query(
            "UPDATE orchestrationCoordinatorRuns \
             SET status = ?, completed_at = datetime('now'), paused_by = NULL \
             WHERE id = ? AND status NOT IN ('completed','failed','cancelled')",
        )
        .bind(status.as_str())
        .bind(id)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if changed == 1 {
            let kind = match status {
                OrchestrationCoordinatorStatus::Completed => Some(RunEventKind::Completed),
                OrchestrationCoordinatorStatus::Failed => Some(RunEventKind::Failed),
                OrchestrationCoordinatorStatus::Cancelled => Some(RunEventKind::Cancelled),
                _ => None,
            };
            if let Some(kind) = kind {
                let mut event = NewRunEvent::new(id, kind);
                event.actor_kind = Some(super::RunActorKind::Runtime);
                record_run_event(&mut tx, &event).await?;
            }
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn stop_orchestration_coordinator_run(&self, id: &str, reason: &str) -> Result<()> {
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns \
             SET status = 'cancelled', completed_at = datetime('now'), stop_reason = ? \
             WHERE id = ?",
        )
        .bind(reason)
        .bind(id)
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn transfer_orchestration_run_coordinator(
        &self,
        run_id: &str,
        actor_handle: &str,
        new_coordinator_handle: &str,
        reason: &str,
        force: bool,
    ) -> Result<OrchestrationCoordinatorRun> {
        let run = self
            .orchestration_coordinator_run_by_id(run_id)
            .await?
            .ok_or_else(|| anyhow!("coordinator run not found: {run_id}"))?;
        if !force && run.coordinator_handle.as_deref() != Some(actor_handle) {
            bail!("only the current coordinator can transfer this run; use --force for audited recovery");
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationCoordinatorRuns SET coordinator_handle = ? WHERE id = ?")
            .bind(new_coordinator_handle)
            .bind(run_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE orchestrationTasks SET coordinator_handle = ? WHERE run_id = ?")
            .bind(new_coordinator_handle)
            .bind(run_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "UPDATE orchestrationDispatchContexts SET coordinator_handle = ? \
             WHERE run_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled')",
        )
        .bind(new_coordinator_handle)
        .bind(run_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.insert_orchestration_audit_event(
            Some(actor_handle),
            if force {
                "run.transfer.force"
            } else {
                "run.transfer"
            },
            run_id,
            reason,
        )
        .await?;
        self.orchestration_coordinator_run_by_id(run_id)
            .await?
            .ok_or_else(|| anyhow!("run not found after transfer"))
    }
}

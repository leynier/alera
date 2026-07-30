//! Coordinator run rows: creation, lookup, lifecycle, and ownership transfer.
//! Split out of the dispatch store so each file covers one lifecycle object.

use anyhow::{anyhow, bail, Result};
use sqlx::sqlite::SqliteRow;
use sqlx::Row;

use super::orchestration_message_store::orchestration_id;
use super::{
    OrchestrationCoordinatorRun, OrchestrationCoordinatorStatus, OrchestrationPolicyStatus,
    RuntimeStore,
};

pub(super) const RUN_COLUMNS: &str =
    "id, spec, status, coordinator_handle, poll_interval_ms, created_at, completed_at, \
     workspace_id, max_concurrent, last_activity_at, stop_reason, execution_policy, \
     execution_policy_status, execution_policy_updated_at";

pub(super) fn run_from_row(row: SqliteRow) -> Result<OrchestrationCoordinatorRun> {
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
        workspace_id: row.try_get("workspace_id")?,
        max_concurrent: row.try_get("max_concurrent")?,
        last_activity_at: row.try_get("last_activity_at")?,
        stop_reason: row.try_get("stop_reason")?,
        execution_policy: row.try_get("execution_policy")?,
        execution_policy_status: row
            .try_get::<Option<String>, _>("execution_policy_status")?
            .and_then(|value| OrchestrationPolicyStatus::parse(&value))
            .unwrap_or_default(),
        execution_policy_updated_at: row.try_get("execution_policy_updated_at")?,
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
        let mut tx = self.pool().begin().await?;
        let active: Option<String> = sqlx::query(
            "SELECT id FROM orchestrationCoordinatorRuns \
             WHERE workspace_id = ? AND status IN ('running','stopping') LIMIT 1",
        )
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
             (id, spec, status, coordinator_handle, poll_interval_ms, workspace_id, max_concurrent) \
             VALUES (?, ?, 'running', ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(spec)
        .bind(coordinator_handle)
        .bind(poll_interval_ms)
        .bind(workspace_id)
        .bind(max_concurrent)
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
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RUN_COLUMNS} FROM orchestrationCoordinatorRuns WHERE id = ?"
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
            "SELECT {RUN_COLUMNS} FROM orchestrationCoordinatorRuns \
             WHERE status = 'running' ORDER BY created_at DESC LIMIT 1"
        )))
        .fetch_optional(self.pool())
        .await?;
        row.map(run_from_row).transpose()
    }

    pub async fn list_orchestration_coordinator_runs(
        &self,
        workspace_id: Option<&str>,
    ) -> Result<Vec<OrchestrationCoordinatorRun>> {
        let mut sql = format!("SELECT {RUN_COLUMNS} FROM orchestrationCoordinatorRuns");
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

    pub async fn stop_orchestration_coordinator_run(&self, id: &str, reason: &str) -> Result<()> {
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns \
             SET status = 'stopped', completed_at = datetime('now'), stop_reason = ? \
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

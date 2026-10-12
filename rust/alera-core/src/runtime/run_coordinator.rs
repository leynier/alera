//! The coordinator terminal a run launches while it plans. Its identity and
//! launch state live on the run row (`coordinator_tab_id`, `coordinator_state`,
//! `coordinator_error`).

use anyhow::{anyhow, bail, Result};
use serde::Serialize;
use sqlx::Row;

use super::run_event_store::{record_run_event, NewRunEvent, RunActorKind, RunEventKind};
use super::RuntimeStore;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCoordinatorReceipt {
    pub run_id: String,
    pub tab_id: String,
    pub workspace_id: String,
    pub profile_id: Option<String>,
    /// `reserved`, `started` or `attention`.
    pub status: String,
    pub error: Option<String>,
}

const RECEIPT_COLUMNS: &str = "id, coordinator_tab_id, workspace_id, coordinator_profile_id, \
    coordinator_state, coordinator_error";

fn receipt(row: sqlx::sqlite::SqliteRow) -> Result<WorkflowCoordinatorReceipt> {
    Ok(WorkflowCoordinatorReceipt {
        run_id: row.try_get("id")?,
        tab_id: row.try_get("coordinator_tab_id")?,
        workspace_id: row.try_get("workspace_id")?,
        profile_id: row.try_get("coordinator_profile_id")?,
        status: row.try_get("coordinator_state")?,
        error: row.try_get("coordinator_error")?,
    })
}

impl RuntimeStore {
    pub async fn workflow_coordinator_for_terminal(
        &self,
        terminal: &str,
    ) -> Result<Option<WorkflowCoordinatorReceipt>> {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RECEIPT_COLUMNS} FROM orchestrationCoordinatorRuns
            WHERE coordinator_tab_id = ? AND coordinator_state <> 'none'"
        )))
        .bind(terminal)
        .fetch_optional(self.pool())
        .await?
        .map(receipt)
        .transpose()
    }

    pub async fn workflow_coordinator(
        &self,
        run_id: &str,
    ) -> Result<Option<WorkflowCoordinatorReceipt>> {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RECEIPT_COLUMNS} FROM orchestrationCoordinatorRuns
            WHERE id = ? AND coordinator_tab_id IS NOT NULL AND coordinator_state <> 'none'"
        )))
        .bind(run_id)
        .fetch_optional(self.pool())
        .await?
        .map(receipt)
        .transpose()
    }

    /// A process-local permit is also required; reserved state alone cannot
    /// authorize replay after a crash or an ordinary terminal request.
    pub async fn require_workflow_coordinator_spawnable(&self, terminal: &str) -> Result<()> {
        let allowed: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns r
            WHERE r.coordinator_tab_id = ? AND r.coordinator_state = 'reserved'
              AND r.status = 'planning'
              AND NOT EXISTS(SELECT 1 FROM runCancellationTargets t
                  WHERE t.run_id = r.id AND t.kind = 'coordinator'))",
        )
        .bind(terminal)
        .fetch_one(self.pool())
        .await?;
        if !allowed {
            bail!("run coordinator launch is no longer authorized");
        }
        Ok(())
    }

    /// Reserves the run's coordinator terminal for another launch with the
    /// correction prompt. Only a planning run whose coordinator is not
    /// running may be relaunched; the tab id stays the same.
    pub async fn reserve_run_coordinator_relaunch(
        &self,
        run_id: &str,
    ) -> Result<WorkflowCoordinatorReceipt> {
        let changed = sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET coordinator_state = 'reserved',
                coordinator_error = NULL
            WHERE id = ? AND status = 'planning' AND coordinator_tab_id IS NOT NULL
              AND coordinator_state IN ('started','attention')",
        )
        .bind(run_id)
        .execute(self.pool())
        .await?
        .rows_affected();
        if changed != 1 {
            bail!("run coordinator cannot be relaunched");
        }
        self.workflow_coordinator(run_id)
            .await?
            .ok_or_else(|| anyhow!("run coordinator not found"))
    }

    pub async fn settle_workflow_coordinator(
        &self,
        run_id: &str,
        tab_id: &str,
        error: Option<&str>,
    ) -> Result<WorkflowCoordinatorReceipt> {
        let error = error.map(|value| value.chars().take(1024).collect::<String>());
        let status = if error.is_some() {
            "attention"
        } else {
            "started"
        };
        let mut tx = self.pool().begin().await?;
        let changed = sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET coordinator_state = ?, coordinator_error = ?
            WHERE id = ? AND coordinator_tab_id = ? AND coordinator_state = 'reserved'",
        )
        .bind(status)
        .bind(&error)
        .bind(run_id)
        .bind(tab_id)
        .execute(&mut *tx)
        .await?
        .rows_affected()
            == 1;
        if changed {
            let mut event = NewRunEvent::new(
                run_id,
                if error.is_some() {
                    RunEventKind::Attention
                } else {
                    RunEventKind::CoordinatorStarted
                },
            );
            event.actor_kind = Some(RunActorKind::Runtime);
            event.summary = error.as_deref().unwrap_or("");
            event.payload = Some(serde_json::json!({ "tabId": tab_id }));
            record_run_event(&mut tx, &event).await?;
        }
        tx.commit().await?;
        let receipt = self
            .workflow_coordinator(run_id)
            .await?
            .ok_or_else(|| anyhow!("coordinator reservation not found"))?;
        if receipt.tab_id != tab_id {
            bail!("coordinator terminal identity does not match");
        }
        Ok(receipt)
    }

    /// A coordinator that was launching or planning when the host stopped did
    /// not survive it. The run waits for a person instead of relaunching.
    pub async fn recover_workflow_coordinators(&self) -> Result<()> {
        sqlx::query("UPDATE orchestrationCoordinatorRuns SET coordinator_state = 'attention',
            coordinator_error = CASE WHEN coordinator_state = 'started'
                THEN 'Coordinator process did not survive the host restart. Inspect its retained terminal, then request changes or cancel the run.'
                ELSE 'Coordinator launch was interrupted. Inspect its terminal, then request changes or cancel the run.' END
            WHERE status = 'planning' AND coordinator_state IN ('reserved','started')")
            .execute(self.pool()).await?;
        Ok(())
    }
}

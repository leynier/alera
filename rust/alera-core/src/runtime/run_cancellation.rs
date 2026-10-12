use anyhow::{bail, Result};
use serde::Serialize;
use sqlx::{Row, Sqlite, Transaction};

use super::RuntimeStore;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCancellationTarget {
    pub id: String,
    /// The attempt launch a worker target stops; `None` for the coordinator.
    pub launch_id: Option<String>,
    pub run_id: String,
    pub terminal_handle: String,
    pub workspace_id: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorkflowTerminalShutdownState {
    Unstarted,
    Started,
    Verified,
}

pub(super) async fn migrate(conn: &mut sqlx::SqliteConnection) -> Result<()> {
    // A coordinator target names the coordinator terminal the run launched;
    // a worker target names its attempt launch, which owns the terminal.
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS runCancellationTargets (
        id TEXT PRIMARY KEY,
        launch_id TEXT UNIQUE REFERENCES runLaunches(id),
        run_id TEXT NOT NULL REFERENCES orchestrationCoordinatorRuns(id),
        kind TEXT NOT NULL DEFAULT 'worker' CHECK(kind IN ('worker','coordinator')),
        tab_id TEXT, workspace_id TEXT,
        state TEXT NOT NULL CHECK(state IN ('pending','settled','attention')),
        error TEXT,
        CHECK((kind = 'worker' AND launch_id IS NOT NULL AND tab_id IS NULL)
            OR (kind = 'coordinator' AND launch_id IS NULL AND tab_id IS NOT NULL
                AND workspace_id IS NOT NULL)))",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS runCancellationPending ON runCancellationTargets(state,run_id,id)")
        .execute(&mut *conn).await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS runCancellationRun ON runCancellationTargets(run_id,state)",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS runTerminalShutdowns (
        tab_id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('started','verified')))",
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// Stops every process a run started: its attempt workers and the coordinator
/// terminal the runtime launched for it. The caller holds the run's writer
/// fence. No process or Git mutation happens until this durable dispatch
/// barrier has committed.
pub(super) async fn cancel(
    tx: &mut Transaction<'_, Sqlite>,
    run: &str,
    reason: &str,
) -> Result<()> {
    sqlx::query(
        "INSERT OR IGNORE INTO runCancellationTargets(id,launch_id,run_id,kind,state)
        SELECT 'worker:'||id,id,run_id,'worker','pending' FROM runLaunches WHERE run_id=?",
    )
    .bind(run)
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "INSERT OR IGNORE INTO runCancellationTargets(id,run_id,kind,tab_id,workspace_id,state)
        SELECT 'coordinator:'||coordinator_tab_id,id,'coordinator',coordinator_tab_id,workspace_id,'pending'
        FROM orchestrationCoordinatorRuns WHERE id=? AND coordinator_tab_id IS NOT NULL",
    )
    .bind(run)
    .execute(&mut **tx)
    .await?;
    // Only a new, sequence-checked cancellation retries an identity failure.
    sqlx::query("UPDATE runCancellationTargets SET state='pending',error=NULL WHERE run_id=? AND state='attention'")
        .bind(run).execute(&mut **tx).await?;
    // Attention is never selected by automatic recovery. A new, sequence-checked
    // cancellation grants one more inspection of the existing immutable receipt.
    sqlx::query("UPDATE runIntegrations SET state=CASE WHEN receipt IS NULL THEN 'pending' ELSE 'prepared' END,error=NULL
        WHERE run_id=? AND cancelled=0 AND state='attention'")
        .bind(run).execute(&mut **tx).await?;
    sqlx::query("UPDATE orchestrationTasks SET status='cancelled',cancelled_at=datetime('now'),completed_at=datetime('now')
        WHERE run_id=? AND status NOT IN ('completed','failed','cancelled')")
        .bind(run).execute(&mut **tx).await?;
    sqlx::query(
        "UPDATE orchestrationDispatchContexts SET status='cancelled',completed_at=datetime('now')
        WHERE run_id=? AND status IN ('pending','dispatched','awaiting_acceptance','stalled')",
    )
    .bind(run)
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "UPDATE runGates SET status='invalidated',resolved_at=datetime('now')
        WHERE run_id=? AND status='pending'",
    )
    .bind(run)
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "UPDATE orchestrationCoordinatorRuns SET status='cancelled',paused_by=NULL,
        stop_reason=COALESCE(stop_reason,?),last_activity_at=datetime('now') WHERE id=?",
    )
    .bind(reason)
    .bind(run)
    .execute(&mut **tx)
    .await?;
    finish(tx, run).await
}

pub(super) async fn finish(tx: &mut Transaction<'_, Sqlite>, run: &str) -> Result<()> {
    sqlx::query(
        "UPDATE orchestrationCoordinatorRuns SET completed_at=datetime('now')
        WHERE id=? AND status='cancelled' AND completed_at IS NULL
        AND NOT EXISTS(SELECT 1 FROM runCancellationTargets WHERE run_id=? AND state<>'settled')",
    )
    .bind(run)
    .bind(run)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

impl RuntimeStore {
    pub async fn workflow_terminal_shutdown_state(
        &self,
        tab: &str,
        workspace: &str,
    ) -> Result<WorkflowTerminalShutdownState> {
        let row = sqlx::query("SELECT workspace_id,state FROM runTerminalShutdowns WHERE tab_id=?")
            .bind(tab)
            .fetch_optional(self.pool())
            .await?;
        let Some(row) = row else {
            return Ok(WorkflowTerminalShutdownState::Unstarted);
        };
        if row.try_get::<String, _>("workspace_id")? != workspace {
            bail!("workflow terminal shutdown belongs to another workspace");
        }
        match row.try_get::<&str, _>("state")? {
            "started" => Ok(WorkflowTerminalShutdownState::Started),
            "verified" => Ok(WorkflowTerminalShutdownState::Verified),
            _ => bail!("workflow terminal shutdown has an invalid state"),
        }
    }

    /// Commit the process-closure barrier before removing a live session.
    /// A host restart cannot turn a lost process guard into a successful retry.
    pub async fn begin_workflow_terminal_shutdown(&self, tab: &str, workspace: &str) -> Result<()> {
        let changed = sqlx::query(
            "INSERT INTO runTerminalShutdowns(tab_id,workspace_id,state) VALUES(?,?,'started') ON CONFLICT(tab_id) DO NOTHING",
        )
        .bind(tab)
        .bind(workspace)
        .execute(self.pool())
        .await?;
        if changed.rows_affected() != 1 {
            bail!("workflow terminal shutdown already started; process closure remains unverified");
        }
        Ok(())
    }

    pub async fn verify_workflow_terminal_shutdown(
        &self,
        tab: &str,
        workspace: &str,
    ) -> Result<()> {
        let changed = sqlx::query(
            "UPDATE runTerminalShutdowns SET state='verified' WHERE tab_id=? AND workspace_id=? AND state IN ('started','verified')",
        )
        .bind(tab)
        .bind(workspace)
        .execute(self.pool())
        .await?;
        if changed.rows_affected() != 1 {
            bail!("workflow terminal shutdown identity changed");
        }
        Ok(())
    }

    pub async fn workflow_cancellation_page(&self) -> Result<Vec<WorkflowCancellationTarget>> {
        sqlx::query("SELECT c.id,c.launch_id,c.run_id,COALESCE(l.workspace_id,c.workspace_id) AS workspace_id,
            COALESCE(l.terminal_handle,c.tab_id) AS terminal_handle
            FROM runCancellationTargets c LEFT JOIN runLaunches l ON l.id=c.launch_id AND l.run_id=c.run_id
            JOIN orchestrationCoordinatorRuns r ON r.id=c.run_id WHERE c.state='pending' AND r.status='cancelled'
            ORDER BY c.run_id,c.id LIMIT 25")
            .fetch_all(self.pool()).await?.into_iter().map(|row| Ok(WorkflowCancellationTarget {
                id: row.try_get("id")?, launch_id: row.try_get("launch_id")?, run_id: row.try_get("run_id")?,
                workspace_id: row.try_get("workspace_id")?, terminal_handle: row.try_get("terminal_handle")?,
            })).collect()
    }

    pub async fn settle_workflow_cancellation(
        &self,
        target: &WorkflowCancellationTarget,
        error: Option<&str>,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET control_sequence=control_sequence WHERE id=?",
        )
        .bind(&target.run_id)
        .execute(&mut *tx)
        .await?;
        validate(&mut tx, target, false).await?;
        if error.is_none() {
            require_terminal_shutdown_settle(
                &mut tx,
                &target.terminal_handle,
                &target.workspace_id,
            )
            .await?;
        }
        sqlx::query(
            "UPDATE runCancellationTargets SET state=?,error=? WHERE id=? AND state='pending'",
        )
        .bind(if error.is_some() {
            "attention"
        } else {
            "settled"
        })
        .bind(error.map(|value| value.chars().take(1000).collect::<String>()))
        .bind(&target.id)
        .execute(&mut *tx)
        .await?;
        finish(&mut tx, &target.run_id).await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn require_workflow_cancellation_target(
        &self,
        target: &WorkflowCancellationTarget,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        validate(&mut tx, target, true).await
    }
}

pub(super) async fn require_terminal_shutdown_settle(
    tx: &mut Transaction<'_, Sqlite>,
    tab: &str,
    workspace: &str,
) -> Result<()> {
    let row = sqlx::query("SELECT workspace_id,state FROM runTerminalShutdowns WHERE tab_id=?")
        .bind(tab)
        .fetch_optional(&mut **tx)
        .await?;
    if let Some(row) = row {
        if row.try_get::<String, _>("workspace_id")? != workspace
            || row.try_get::<String, _>("state")? != "verified"
        {
            bail!("workflow terminal process closure remains unverified");
        }
    }
    Ok(())
}

async fn validate(
    tx: &mut Transaction<'_, Sqlite>,
    target: &WorkflowCancellationTarget,
    pending_only: bool,
) -> Result<()> {
    let valid: bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM runCancellationTargets c
        LEFT JOIN runLaunches l ON l.id=c.launch_id AND l.run_id=c.run_id
        JOIN orchestrationCoordinatorRuns r ON r.id=c.run_id
        WHERE c.id=? AND c.launch_id IS ? AND c.run_id=? AND COALESCE(l.workspace_id,c.workspace_id)=?
        AND COALESCE(l.terminal_handle,c.tab_id)=? AND r.status='cancelled' AND (?=0 OR c.state='pending'))")
        .bind(&target.id).bind(&target.launch_id).bind(&target.run_id).bind(&target.workspace_id).bind(&target.terminal_handle).bind(pending_only)
        .fetch_one(&mut **tx).await?;
    if !valid {
        bail!("run cancellation identity changed");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        require_terminal_shutdown_settle, RuntimeStore, WorkflowTerminalShutdownState as State,
    };

    #[tokio::test]
    async fn terminal_shutdown_evidence_survives_restart_and_rejects_other_owners() {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        assert_eq!(
            store
                .workflow_terminal_shutdown_state("tab", "owner")
                .await
                .unwrap(),
            State::Unstarted
        );
        store
            .begin_workflow_terminal_shutdown("tab", "owner")
            .await
            .unwrap();
        assert!(store
            .begin_workflow_terminal_shutdown("tab", "owner")
            .await
            .is_err());
        assert!(store
            .workflow_terminal_shutdown_state("tab", "foreign")
            .await
            .is_err());
        drop(store);
        let reopened = RuntimeStore::open(dir.path()).await.unwrap();
        assert_eq!(
            reopened
                .workflow_terminal_shutdown_state("tab", "owner")
                .await
                .unwrap(),
            State::Started
        );
        let mut transaction = reopened.pool().begin().await.unwrap();
        assert!(
            require_terminal_shutdown_settle(&mut transaction, "tab", "owner")
                .await
                .is_err()
        );
        transaction.rollback().await.unwrap();
        assert!(reopened
            .verify_workflow_terminal_shutdown("tab", "foreign")
            .await
            .is_err());
        reopened
            .verify_workflow_terminal_shutdown("tab", "owner")
            .await
            .unwrap();
        reopened
            .verify_workflow_terminal_shutdown("tab", "owner")
            .await
            .unwrap();
        assert_eq!(
            reopened
                .workflow_terminal_shutdown_state("tab", "owner")
                .await
                .unwrap(),
            State::Verified
        );
        let mut transaction = reopened.pool().begin().await.unwrap();
        require_terminal_shutdown_settle(&mut transaction, "tab", "owner")
            .await
            .unwrap();
        transaction.rollback().await.unwrap();
    }
}

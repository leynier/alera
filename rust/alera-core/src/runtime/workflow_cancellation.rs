use anyhow::{bail, Result};
use serde::Serialize;
use sqlx::{Row, Sqlite, Transaction};

use super::RuntimeStore;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCancellationTarget {
    pub launch_id: Option<String>,
    pub proposal_id: Option<String>,
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

pub(super) async fn migrate(tx: &mut Transaction<'_, Sqlite>) -> Result<()> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS workflowCancellationTargets (
        id TEXT PRIMARY KEY,
        launch_id TEXT UNIQUE REFERENCES workflowLaunches(id),
        proposal_id TEXT UNIQUE REFERENCES workflowCoordinators(proposal_id),
        run_id TEXT NOT NULL REFERENCES workflowRuns(run_id),
        state TEXT NOT NULL CHECK(state IN ('pending','settled','attention')),
        error TEXT, CHECK((launch_id IS NULL) <> (proposal_id IS NULL)))",
    )
    .execute(&mut **tx)
    .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS workflowCancellationPending ON workflowCancellationTargets(state,run_id,id)")
        .execute(&mut **tx).await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS workflowCancellationRun ON workflowCancellationTargets(run_id,state)")
        .execute(&mut **tx).await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS workflowProposalRun ON workflowProposalDrafts(json_extract(document,'$.request.runId'))")
        .execute(&mut **tx).await?;
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS workflowTerminalShutdowns (
        tab_id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('started','verified')))",
    )
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// The caller holds the execution-command writer fence. No process or Git
/// mutation happens until this durable dispatch barrier has committed.
pub(super) async fn cancel(tx: &mut Transaction<'_, Sqlite>, run: &str) -> Result<()> {
    sqlx::query("UPDATE workflowRuns SET status='cancelled' WHERE run_id=?")
        .bind(run)
        .execute(&mut **tx)
        .await?;
    sqlx::query(
        "INSERT OR IGNORE INTO workflowCancellationTargets(id,launch_id,run_id,state)
        SELECT 'worker:'||id,id,run_id,'pending' FROM workflowLaunches WHERE run_id=?",
    )
    .bind(run)
    .execute(&mut **tx)
    .await?;
    sqlx::query("INSERT OR IGNORE INTO workflowCancellationTargets(id,proposal_id,run_id,state)
        SELECT 'coordinator:'||c.proposal_id,c.proposal_id,p.run_id,'pending'
        FROM workflowCoordinators c JOIN workflowPlanRevisions p ON p.request_id=c.proposal_id WHERE p.run_id=?")
        .bind(run).execute(&mut **tx).await?;
    sqlx::query("INSERT OR IGNORE INTO workflowCancellationTargets(id,proposal_id,run_id,state)
        SELECT 'coordinator:'||c.proposal_id,c.proposal_id,?,'pending' FROM workflowProposalDrafts d
        JOIN workflowCoordinators c ON c.proposal_id=d.id WHERE json_extract(d.document,'$.request.runId')=?")
        .bind(run).bind(run).execute(&mut **tx).await?;
    // Only a new, sequence-checked Cancel command retries an identity failure.
    sqlx::query("UPDATE workflowCancellationTargets SET state='pending',error=NULL WHERE run_id=? AND state='attention'")
        .bind(run).execute(&mut **tx).await?;
    // Attention is never selected by automatic recovery. A new, sequence-checked
    // cancellation grants one more inspection of the existing immutable receipt.
    sqlx::query("UPDATE workflowIntegrations SET state=CASE WHEN receipt IS NULL THEN 'pending' ELSE 'prepared' END,error=NULL
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
    sqlx::query("UPDATE orchestrationCoordinatorRuns SET status='stopping',stop_reason='Workflow cancelled by the user.' WHERE id=?")
        .bind(run).execute(&mut **tx).await?;
    finish(tx, run).await
}

async fn finish(tx: &mut Transaction<'_, Sqlite>, run: &str) -> Result<()> {
    sqlx::query("UPDATE orchestrationCoordinatorRuns SET status='stopped',completed_at=datetime('now')
        WHERE id=? AND EXISTS(SELECT 1 FROM workflowRuns WHERE run_id=? AND status='cancelled')
        AND NOT EXISTS(SELECT 1 FROM workflowCancellationTargets WHERE run_id=? AND state<>'settled')")
        .bind(run).bind(run).bind(run).execute(&mut **tx).await?;
    Ok(())
}

impl RuntimeStore {
    pub async fn workflow_terminal_shutdown_state(
        &self,
        tab: &str,
        workspace: &str,
    ) -> Result<WorkflowTerminalShutdownState> {
        let row =
            sqlx::query("SELECT workspace_id,state FROM workflowTerminalShutdowns WHERE tab_id=?")
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
            "INSERT INTO workflowTerminalShutdowns(tab_id,workspace_id,state) VALUES(?,?,'started') ON CONFLICT(tab_id) DO NOTHING",
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
            "UPDATE workflowTerminalShutdowns SET state='verified' WHERE tab_id=? AND workspace_id=? AND state IN ('started','verified')",
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
        sqlx::query("SELECT c.launch_id,c.proposal_id,c.run_id,COALESCE(l.workspace_id,p.workspace_id) AS workspace_id,
            COALESCE(l.terminal_handle,p.tab_id) AS terminal_handle
            FROM workflowCancellationTargets c LEFT JOIN workflowLaunches l ON l.id=c.launch_id AND l.run_id=c.run_id
            LEFT JOIN workflowCoordinators p ON p.proposal_id=c.proposal_id
            JOIN workflowRuns w ON w.run_id=c.run_id WHERE c.state='pending' AND w.status='cancelled'
            ORDER BY c.run_id,c.id LIMIT 25")
            .fetch_all(self.pool()).await?.into_iter().map(|row| Ok(WorkflowCancellationTarget {
                launch_id: row.try_get("launch_id")?, proposal_id: row.try_get("proposal_id")?, run_id: row.try_get("run_id")?,
                workspace_id: row.try_get("workspace_id")?, terminal_handle: row.try_get("terminal_handle")?,
            })).collect()
    }

    pub async fn settle_workflow_cancellation(
        &self,
        target: &WorkflowCancellationTarget,
        error: Option<&str>,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE workflowRuns SET revision=revision WHERE run_id=?")
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
        sqlx::query("UPDATE workflowCancellationTargets SET state=?,error=? WHERE launch_id IS ? AND proposal_id IS ? AND state='pending'")
            .bind(if error.is_some() { "attention" } else { "settled" })
            .bind(error.map(|value| value.chars().take(1000).collect::<String>()))
            .bind(&target.launch_id).bind(&target.proposal_id).execute(&mut *tx).await?;
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
    let row =
        sqlx::query("SELECT workspace_id,state FROM workflowTerminalShutdowns WHERE tab_id=?")
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
    let valid: bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowCancellationTargets c
        LEFT JOIN workflowLaunches l ON l.id=c.launch_id AND l.run_id=c.run_id
        LEFT JOIN workflowCoordinators p ON p.proposal_id=c.proposal_id
        JOIN workflowRuns w ON w.run_id=c.run_id
        WHERE c.launch_id IS ? AND c.proposal_id IS ? AND c.run_id=? AND COALESCE(l.workspace_id,p.workspace_id)=?
        AND COALESCE(l.terminal_handle,p.tab_id)=? AND w.status='cancelled' AND (?=0 OR c.state='pending')
        AND (c.proposal_id IS NULL OR EXISTS(SELECT 1 FROM workflowPlanRevisions r WHERE r.run_id=c.run_id AND r.request_id=c.proposal_id)
            OR EXISTS(SELECT 1 FROM workflowProposalDrafts d WHERE d.id=c.proposal_id AND json_extract(d.document,'$.request.runId')=c.run_id)))")
        .bind(&target.launch_id).bind(&target.proposal_id).bind(&target.run_id).bind(&target.workspace_id).bind(&target.terminal_handle).bind(pending_only)
        .fetch_one(&mut **tx).await?;
    if !valid {
        bail!("workflow cancellation identity changed");
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

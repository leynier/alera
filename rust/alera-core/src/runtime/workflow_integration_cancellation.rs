use anyhow::{bail, Result};

use super::{RuntimeStore, WorkflowIntegrationRecord, WorkflowIntegrationState as State};
use crate::git::WorkflowIntegrationReceipt;

impl RuntimeStore {
    pub async fn workflow_integration_run_cancelled(&self, id: &str) -> Result<bool> {
        Ok(sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowIntegrations i JOIN workflowRuns r ON r.run_id=i.run_id WHERE i.id=? AND r.status='cancelled' AND r.revision=i.revision)")
            .bind(id).fetch_one(self.pool()).await?)
    }

    /// Linearizes a Git step against cancellation before native work begins.
    /// It grants no permission to a subsequent step, which must check again.
    pub async fn require_workflow_integration_current(&self, id: &str) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query("SELECT * FROM workflowIntegrations WHERE id=?")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
        let record = super::workflow_integration_store::decode(&row)?;
        if !matches!(
            record.state,
            State::Pending | State::Prepared | State::Attention
        ) {
            bail!("integration is already settled");
        }
        super::workflow_integration_validation::require_current(&mut tx, &record.request).await?;
        tx.commit().await?;
        Ok(())
    }

    /// Trusted native boundary: caller holds the integration lock and has
    /// inspected the Git receipt/checkouts without preparing or applying work.
    pub async fn settle_cancelled_workflow_integration(
        &self,
        id: &str,
        receipt: Option<&WorkflowIntegrationReceipt>,
    ) -> Result<WorkflowIntegrationRecord> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query("SELECT * FROM workflowIntegrations WHERE id=?")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
        let record = super::workflow_integration_store::decode(&row)?;
        if record.state == State::Cancelled {
            return Ok(record);
        }
        if !matches!(
            record.state,
            State::Pending | State::Prepared | State::Attention
        ) {
            bail!("integration is already settled");
        }
        let cancelled: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowRuns WHERE run_id=? AND revision=? AND status='cancelled')")
            .bind(&record.request.run_id).bind(record.request.revision).fetch_one(&mut *tx).await?;
        if !cancelled {
            bail!("integration run is not cancelled at this revision");
        }
        if receipt.is_some_and(|r| r.version != 1 || r.request != record.request)
            || record
                .receipt
                .as_ref()
                .is_some_and(|stored| Some(stored) != receipt)
        {
            bail!("cancelled integration receipt changed or disappeared");
        }
        for expected in [&record.request.integration, &record.request.source] {
            let row = sqlx::query("SELECT * FROM workflowWorkspaces WHERE id=?")
                .bind(&expected.id)
                .fetch_one(&mut *tx)
                .await?;
            let resource = super::workflow_workspace_store::decode(&row)?;
            super::workflow_integration_validation::require_resource(&mut tx, &resource).await?;
            if resource.identity.run_id != record.request.run_id
                || resource.identity.repo_path != record.request.repo_path
                || resource.identity.workspace.path != expected.path
                || resource.identity.base_sha != expected.base_sha
            {
                bail!("cancelled integration resource identity changed");
            }
        }
        sqlx::query("UPDATE workflowIntegrations SET cancelled=1,receipt=?,updated_at=datetime('now') WHERE id=? AND cancelled=0")
            .bind(receipt.map(serde_json::to_string).transpose()?).bind(id).execute(&mut *tx).await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision+1 WHERE id=1")
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        self.workflow_integration(id).await
    }
}

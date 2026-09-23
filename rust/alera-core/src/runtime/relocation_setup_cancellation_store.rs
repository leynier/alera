use anyhow::{anyhow, bail, Result};

use super::{RelocationSetupReceipt, RuntimeStore};

impl RuntimeStore {
    pub(super) async fn migrate_relocation_setup_cancellations(&self) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS relocationSetupCancellations (relocationId TEXT NOT NULL, attemptId TEXT NOT NULL, PRIMARY KEY(relocationId, attemptId))")
            .execute(self.pool()).await?;
        Ok(())
    }

    pub async fn request_relocation_setup_cancellation(
        &self,
        workspace_id: &str,
        relocation_id: &str,
        attempt_id: &str,
    ) -> Result<()> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let owner: Option<String> =
            sqlx::query_scalar("SELECT workspaceId FROM workspaceRelocations WHERE id = ?")
                .bind(relocation_id)
                .fetch_optional(&mut *tx)
                .await?;
        if owner.as_deref() != Some(workspace_id) {
            bail!("Setup receipt belongs to a different task or no longer exists");
        }
        let active: i64 = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM relocationSetupReceipts WHERE relocationId = ? AND attemptId = ? AND reportJson IS NULL)")
            .bind(relocation_id).bind(attempt_id).fetch_one(&mut *tx).await?;
        if active == 0 {
            bail!("Setup attempt changed or already finished; inspect recovery before cancelling");
        }
        sqlx::query("INSERT INTO relocationSetupCancellations(relocationId, attemptId) VALUES (?, ?) ON CONFLICT DO NOTHING")
            .bind(relocation_id).bind(attempt_id).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn setup_cancellation_requested(
        &self,
        receipt: &RelocationSetupReceipt,
    ) -> Result<bool> {
        let attempt = receipt
            .attempt_id
            .as_deref()
            .ok_or_else(|| anyhow!("Setup has no claimed attempt"))?;
        Ok(sqlx::query_scalar::<_, i64>("SELECT EXISTS(SELECT 1 FROM relocationSetupCancellations WHERE relocationId = ? AND attemptId = ?)")
            .bind(&receipt.relocation_id).bind(attempt).fetch_one(self.pool()).await? != 0)
    }
}

use anyhow::{anyhow, bail, Result};

use super::{RemoteWorkspaceRelocationIntent, RuntimeStore, WorkspaceRelocation};

impl RuntimeStore {
    /// Retain the owner's resolved path before dispatch, without moving Home's task.
    pub async fn record_remote_workspace_relocation_preparation(
        &self,
        id: &str,
        preparation: &WorkspaceRelocation,
    ) -> Result<RemoteWorkspaceRelocationIntent> {
        let mut tx = self.pool().begin().await?;
        let data: Option<String> = sqlx::query_scalar("SELECT dataJson FROM remoteWorkspaceRelocationIntents WHERE id = ? AND completed = 0 AND ownerJournalJson IS NULL")
            .bind(id).fetch_optional(&mut *tx).await?;
        let data =
            data.ok_or_else(|| anyhow!("SSH relocation is no longer awaiting owner preparation"))?;
        let mut intent: RemoteWorkspaceRelocationIntent = serde_json::from_str(&data)?;
        if let Some(previous) = &intent.owner_preparation {
            if serde_json::to_value(previous)? != serde_json::to_value(preparation)? {
                bail!("Owner preparation changed; retain the original recovery evidence");
            }
            return Ok(intent);
        }
        if preparation.destination.path.trim().is_empty()
            || preparation.destination.path == intent.source.path
            || (intent.intent.to_project_checkout
                && preparation.destination.path != intent.project_checkout_path)
        {
            bail!("Owner preparation returned an invalid destination");
        }
        intent.destination_path = Some(preparation.destination.path.clone());
        super::validate_owner_scope(&intent, preparation)?;
        let path = &preparation.destination.path;
        if !intent.intent.to_project_checkout {
            let occupied: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM repositoryCheckouts c JOIN workspaceCheckoutBindings b ON b.checkoutId = c.id WHERE c.hostId = ? AND c.path = ? AND b.workspaceId != ?)")
                .bind(&intent.source.host_id).bind(path).bind(&intent.source.id).fetch_one(&mut *tx).await?;
            let reserved: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM remoteRelocationLinkedPaths WHERE hostId = ? AND path = ? AND id != ?) OR EXISTS (SELECT 1 FROM workspaceRelocations WHERE hostId = ? AND completed = 0 AND id != ? AND ((json_extract(dataJson, '$.source.kind') = 'linked' AND json_extract(dataJson, '$.source.path') = ?) OR (json_extract(dataJson, '$.destination.kind') = 'linked' AND json_extract(dataJson, '$.destination.path') = ?)))")
                .bind(&intent.source.host_id).bind(path).bind(id)
                .bind(&intent.source.host_id).bind(id).bind(path).bind(path).fetch_one(&mut *tx).await?;
            if occupied || reserved {
                bail!("The resolved SSH worktree is owned or reserved by another task");
            }
        }
        intent.owner_preparation = Some(preparation.clone());
        let result = sqlx::query("UPDATE remoteWorkspaceRelocationIntents SET dataJson = ? WHERE id = ? AND completed = 0 AND dataJson = ? AND ownerJournalJson IS NULL")
            .bind(serde_json::to_string(&intent)?).bind(id).bind(data).execute(&mut *tx).await?;
        if result.rows_affected() != 1 {
            bail!("SSH relocation changed during owner preparation");
        }
        tx.commit().await?;
        Ok(intent)
    }
}

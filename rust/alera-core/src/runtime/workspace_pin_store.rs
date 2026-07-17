use anyhow::Result;

use super::{RuntimeStore, RuntimeStoreError, Workspace};

impl RuntimeStore {
    pub async fn set_workspace_pinned(
        &self,
        workspace_id: &str,
        is_pinned: bool,
    ) -> Result<Workspace> {
        let result = sqlx::query("UPDATE workspaces SET isPinned = ? WHERE id = ?")
            .bind(if is_pinned { 1_i64 } else { 0_i64 })
            .bind(workspace_id)
            .execute(self.pool())
            .await?;
        if result.rows_affected() == 0 {
            anyhow::bail!(RuntimeStoreError::Message(format!(
                "workspace not found: {workspace_id}"
            )));
        }
        self.find_workspace(workspace_id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "workspace not found after pin update: {workspace_id}"
            )))
        })
    }
}

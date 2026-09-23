use anyhow::Result;

use super::store::tab_from_row;
use super::{RuntimeStore, WorkspaceTabRecord};

impl RuntimeStore {
    pub async fn list_all_workspace_tabs(&self) -> Result<Vec<WorkspaceTabRecord>> {
        let rows = sqlx::query(
            "SELECT id, workspaceId, kind, title, createdAt, updatedAt, payloadJson \
             FROM workspaceTabs ORDER BY createdAt ASC",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(tab_from_row).collect()
    }
}

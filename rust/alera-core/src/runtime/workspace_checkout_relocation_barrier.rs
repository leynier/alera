use anyhow::{bail, Result};
use sqlx::SqliteConnection;

use super::RuntimeStore;

const PENDING: &str = "SELECT r.id FROM workspaces w JOIN (
    SELECT id, projectId, hostId, json_extract(dataJson, '$.source.path') AS sourcePath,
           json_extract(dataJson, '$.destination.path') AS destinationPath,
           json_extract(dataJson, '$.repositoryPath') AS projectPath
    FROM workspaceRelocations WHERE completed = 0
    UNION ALL
    SELECT id, projectId, hostId, json_extract(dataJson, '$.source.path'),
           json_extract(dataJson, '$.destinationPath'), json_extract(dataJson, '$.projectCheckoutPath')
    FROM remoteWorkspaceRelocationIntents WHERE completed = 0
) r ON r.hostId = w.hostId AND (r.projectId = w.projectId OR w.path IN (r.sourcePath, r.destinationPath, r.projectPath))
WHERE w.id = ? LIMIT 1";

impl RuntimeStore {
    pub async fn pending_workspace_checkout_relocation(
        &self,
        workspace_id: &str,
    ) -> Result<Option<String>> {
        Ok(sqlx::query_scalar(PENDING)
            .bind(workspace_id)
            .fetch_optional(self.pool())
            .await?)
    }
}

pub(super) async fn require_checkout_process_launch_available(
    connection: &mut SqliteConnection,
    workspace_id: &str,
) -> Result<()> {
    let terminal: Option<String> = sqlx::query_scalar(
        "SELECT id FROM terminalLifecycleOperations WHERE workspaceId = ? AND closed = 0 LIMIT 1",
    )
    .bind(workspace_id)
    .fetch_optional(&mut *connection)
    .await?;
    if let Some(id) = terminal {
        bail!("Recover terminal operation {id} before starting another workspace process");
    }
    let pending: Option<String> = sqlx::query_scalar(PENDING)
        .bind(workspace_id)
        .fetch_optional(connection)
        .await?;
    if let Some(id) = pending {
        bail!("Recover checkout relocation {id} before starting another workspace process");
    }
    Ok(())
}

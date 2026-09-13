use anyhow::{anyhow, bail, Result};

use super::{
    RemoteWorkspaceRelocationIntent, RuntimeStore, Workspace, WorkspaceRelocation,
    WorkspaceRelocationPhase,
};

impl RuntimeStore {
    /// The runtime must keep its verified Home buffer/process guard through this commit.
    pub async fn commit_remote_workspace_relocation(&self, id: &str) -> Result<Workspace> {
        let mut tx = self.pool().begin().await?;
        let row: Option<(String, Option<String>, bool)> = sqlx::query_as("SELECT dataJson, ownerJournalJson, completed FROM remoteWorkspaceRelocationIntents WHERE id = ?")
            .bind(id).fetch_optional(&mut *tx).await?;
        let (data, receipt, completed) = row.ok_or_else(|| anyhow!("SSH relocation not found"))?;
        let intent: RemoteWorkspaceRelocationIntent = serde_json::from_str(&data)?;
        let mut journal: WorkspaceRelocation =
            serde_json::from_str(&receipt.ok_or_else(|| {
                anyhow!("A verified owner receipt is required before changing Home location")
            })?)?;
        super::remote_workspace_relocation_receipts::validate_receipt(&intent, &journal)?;
        if completed {
            let latest: Option<String> = sqlx::query_scalar("SELECT id FROM workspaceRelocations WHERE workspaceId = ? ORDER BY rowid DESC LIMIT 1")
                .bind(&intent.source.id).fetch_optional(&mut *tx).await?;
            if latest.as_deref() != Some(id) {
                bail!("This relocation was superseded; its receipt cannot change the current task");
            }
        } else {
            journal.source = intent.source.clone();
            journal.destination.host_id = intent.source.host_id.clone();
            journal.phase = WorkspaceRelocationPhase::Committed;
            sqlx::query("UPDATE remoteWorkspaceRelocationIntents SET completed = 1 WHERE id = ? AND completed = 0")
                .bind(id).execute(&mut *tx).await?;
            sqlx::query("INSERT INTO workspaceRelocations(id, workspaceId, projectId, hostId, dataJson) VALUES (?, ?, ?, ?, ?)")
                .bind(id).bind(&intent.source.id).bind(&intent.source.project_id).bind(&intent.source.host_id)
                .bind(serde_json::to_string(&journal)?).execute(&mut *tx).await?;
            super::workspace_relocation_location_write::write_relocated_workspace(
                &mut tx,
                &journal.source,
                &journal.destination,
                &journal.repository_path,
            )
            .await?;
            journal.phase = WorkspaceRelocationPhase::Completed;
            sqlx::query("UPDATE workspaceRelocations SET completed = 1, dataJson = ? WHERE id = ?")
                .bind(serde_json::to_string(&journal)?)
                .bind(id)
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await?;
        let workspace = self
            .find_workspace(&intent.source.id)
            .await?
            .ok_or_else(|| anyhow!("Workspace disappeared after SSH relocation"))?;
        if workspace.instance_id != intent.source.instance_id
            || workspace.host_id != intent.source.host_id
            || workspace.project_id != intent.source.project_id
            || Some(workspace.path.as_str()) != intent.destination_path.as_deref()
            || workspace.kind != journal.destination.kind
        {
            bail!("The workspace has a different identity or location than this relocation result");
        }
        Ok(workspace)
    }
}

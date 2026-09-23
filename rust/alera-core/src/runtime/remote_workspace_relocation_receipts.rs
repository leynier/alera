use anyhow::{anyhow, bail, Result};

use super::{
    RemoteWorkspaceRelocationIntent, RuntimeStore, WorkspaceKind, WorkspaceRelocation,
    WorkspaceRelocationPhase, LOCAL_HOST_ID,
};

impl RuntimeStore {
    /// Retain owner recovery evidence before committing any Home location fields.
    pub async fn record_remote_workspace_relocation_receipt(
        &self,
        id: &str,
        receipt: &WorkspaceRelocation,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        let row: Option<(String, Option<String>)> = sqlx::query_as("SELECT dataJson, ownerJournalJson FROM remoteWorkspaceRelocationIntents WHERE id = ? AND completed = 0")
            .bind(id).fetch_optional(&mut *tx).await?;
        let (data, previous) = row.ok_or_else(|| anyhow!("Pending SSH relocation not found"))?;
        let intent: RemoteWorkspaceRelocationIntent = serde_json::from_str(&data)?;
        validate_receipt(&intent, receipt)?;
        let encoded = serde_json::to_string(receipt)?;
        if let Some(previous) = previous {
            if previous != encoded {
                bail!("The owner returned different evidence for the same relocation; preserve both locations and inspect recovery");
            }
            return Ok(());
        }
        let result = sqlx::query("UPDATE remoteWorkspaceRelocationIntents SET ownerJournalJson = ? WHERE id = ? AND completed = 0 AND dataJson = ? AND ownerJournalJson IS NULL")
            .bind(encoded).bind(id).bind(data).execute(&mut *tx).await?;
        if result.rows_affected() != 1 {
            bail!("SSH relocation changed while retaining its owner receipt");
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn find_remote_workspace_relocation_receipt(
        &self,
        id: &str,
    ) -> Result<Option<WorkspaceRelocation>> {
        let encoded: Option<String> = sqlx::query_scalar("SELECT ownerJournalJson FROM remoteWorkspaceRelocationIntents WHERE id = ? AND ownerJournalJson IS NOT NULL")
            .bind(id).fetch_optional(self.pool()).await?;
        encoded
            .map(|value| serde_json::from_str(&value).map_err(Into::into))
            .transpose()
    }
}

pub(super) fn validate_receipt(
    intent: &RemoteWorkspaceRelocationIntent,
    receipt: &WorkspaceRelocation,
) -> Result<()> {
    if receipt.phase != WorkspaceRelocationPhase::Completed {
        bail!("The owner relocation is not completed");
    }
    if let Some(prepared) = &intent.owner_preparation {
        if prepared.source_commit != receipt.source_commit
            || prepared.original_branch != receipt.original_branch
            || prepared.replacement_commit != receipt.replacement_commit
            || prepared.destination_original_branch != receipt.destination_original_branch
            || prepared.destination_original_commit != receipt.destination_original_commit
        {
            bail!("Owner completion differs from the retained preparation baseline");
        }
    }
    validate_owner_scope(intent, receipt)
}

pub(super) fn validate_owner_scope(
    intent: &RemoteWorkspaceRelocationIntent,
    receipt: &WorkspaceRelocation,
) -> Result<()> {
    let source = &receipt.source;
    let destination = &receipt.destination;
    let expected = &intent.source;
    let destination_kind = if intent.intent.to_project_checkout {
        WorkspaceKind::Main
    } else {
        WorkspaceKind::Linked
    };
    let expected_branch = if intent.intent.to_project_checkout {
        Some(receipt.original_branch.as_str())
    } else {
        intent.intent.branch.as_deref()
    };
    if receipt.id != intent.id
        || source.id != expected.id
        || source.instance_id != expected.instance_id
        || source.project_id != expected.project_id
        || source.host_id != LOCAL_HOST_ID
        || source.path != expected.path
        || source.kind != expected.kind
        || destination.id != expected.id
        || destination.instance_id != expected.instance_id
        || destination.project_id != expected.project_id
        || destination.host_id != LOCAL_HOST_ID
        || Some(destination.path.as_str()) != intent.destination_path.as_deref()
        || destination.kind != destination_kind
        || destination.branch.as_deref() != expected_branch
        || receipt.move_changes != intent.intent.move_changes
        || receipt.replacement_branch != intent.intent.replacement_branch
        || receipt.repository_path != intent.project_checkout_path
    {
        bail!(
            "The owner receipt does not verify the exact SSH relocation choices and task identity"
        );
    }
    Ok(())
}

#[path = "remote_workspace_relocation_preparation.rs"]
mod preparation;

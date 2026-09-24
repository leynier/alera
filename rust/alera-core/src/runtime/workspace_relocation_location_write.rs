use super::Workspace;
use anyhow::{bail, Result};
use serde_json::{json, Value};
use sqlx::{Row, Sqlite, Transaction};

pub(super) async fn write_relocated_workspace(
    tx: &mut Transaction<'_, Sqlite>,
    source: &Workspace,
    destination: &Workspace,
    repository_path: &str,
) -> Result<()> {
    let updated = sqlx::query("UPDATE workspaces SET path = ?, kind = ?, branch = ?, sourceBranch = ?, reusesExistingBranch = ?, updatedAt = ? WHERE id = ? AND instanceId = ? AND projectId = ? AND hostId = ? AND path = ? AND kind = ?")
            .bind(&destination.path).bind(destination.kind.as_str()).bind(&destination.branch)
            .bind(&destination.source_branch).bind(destination.reuses_existing_branch)
            .bind(super::store::format_timestamp(chrono::Utc::now())).bind(&source.id).bind(&source.instance_id)
            .bind(&source.project_id).bind(&source.host_id).bind(&source.path).bind(source.kind.as_str()).execute(&mut **tx).await?;
    if updated.rows_affected() != 1 {
        bail!("Workspace changed during relocation; files and recovery data were retained");
    }
    super::checkout_store::bind_workspace_checkout(tx, destination, &destination.path).await?;
    if destination.kind == super::WorkspaceKind::Linked {
        let bound = sqlx::query("UPDATE repositoryCheckouts SET repositoryPath = ? WHERE id = (SELECT checkoutId FROM workspaceCheckoutBindings WHERE workspaceId = ?) AND kind = 'linked' AND (repositoryPath IS NULL OR repositoryPath = ?)")
                .bind(repository_path).bind(&destination.id).bind(repository_path).execute(&mut **tx).await?;
        if bound.rows_affected() != 1 {
            bail!("The relocated worktree belongs to a different repository");
        }
    }
    let tabs = sqlx::query("SELECT id, payloadJson FROM workspaceTabs WHERE workspaceId = ?")
        .bind(&source.id)
        .fetch_all(&mut **tx)
        .await?;
    for tab in tabs {
        let id: String = tab.try_get("id")?;
        let mut payload: Value = serde_json::from_str(tab.try_get("payloadJson")?)?;
        if !payload.is_object() {
            bail!("Tab {id} has an invalid payload; relocation records were not committed");
        }
        for key in ["filePath", "gitDiffRoot", "workingDirectory"] {
            if let Some(path) = payload.get(key).and_then(Value::as_str) {
                if let Some(relocated) = super::workspace_location_path::relocated_path(
                    path,
                    &source.path,
                    &destination.path,
                ) {
                    payload[key] = json!(relocated);
                }
            }
        }
        sqlx::query("UPDATE workspaceTabs SET payloadJson = ? WHERE id = ?")
            .bind(serde_json::to_string(&payload)?)
            .bind(id)
            .execute(&mut **tx)
            .await?;
    }
    Ok(())
}

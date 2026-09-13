use anyhow::{bail, Result};
use serde_json::{json, Value};
use sqlx::Row;

use super::{RuntimeStore, Workspace};

impl RuntimeStore {
    /// Move records before deleting the source, retaining stable tab identities.
    pub async fn transfer_workspace_contents(
        &self,
        source: &Workspace,
        destination: &Workspace,
    ) -> Result<()> {
        if source.id == destination.id || source.project_id != destination.project_id {
            bail!("Workspace transfer requires different workspaces in the same project");
        }
        let mut tx = self.pool().begin().await?;
        let rows = sqlx::query("SELECT id, payloadJson FROM workspaceTabs WHERE workspaceId = ? ORDER BY createdAt, id")
            .bind(&source.id).fetch_all(&mut *tx).await?;
        let destination_rows = sqlx::query(
            "SELECT id FROM workspaceTabs WHERE workspaceId = ? ORDER BY createdAt, id",
        )
        .bind(&destination.id)
        .fetch_all(&mut *tx)
        .await?;
        let destination_tabs: Vec<String> =
            destination_rows.iter().map(|row| row.get("id")).collect();
        let mut source_tabs = Vec::new();
        for row in rows {
            let id: String = row.try_get("id")?;
            source_tabs.push(id.clone());
            let mut payload: Value = serde_json::from_str(row.try_get("payloadJson")?)?;
            if !payload.is_object() {
                bail!("Tab {id} has an invalid payload; no tab or layout records were moved");
            }
            let mut previous = payload["handoffSourceWorkspaceIds"]
                .as_array()
                .cloned()
                .unwrap_or_default();
            if !previous.contains(&json!(source.id)) {
                previous.push(json!(source.id));
            }
            payload["handoffSourceWorkspaceIds"] = json!(previous);
            for key in ["filePath", "gitDiffRoot", "workingDirectory"] {
                if let Some(path) = payload.get(key).and_then(Value::as_str) {
                    if let Ok(relative) = std::path::Path::new(path).strip_prefix(&source.path) {
                        payload[key] = json!(std::path::Path::new(&destination.path)
                            .join(relative)
                            .to_string_lossy());
                    }
                }
            }
            sqlx::query("UPDATE workspaceTabs SET workspaceId = ?, payloadJson = ? WHERE id = ?")
                .bind(&destination.id)
                .bind(serde_json::to_string(&payload)?)
                .bind(id)
                .execute(&mut *tx)
                .await?;
        }
        let layouts = sqlx::query(
            "SELECT workspaceId, dataJson FROM workbenchLayouts WHERE workspaceId IN (?, ?)",
        )
        .bind(&source.id)
        .bind(&destination.id)
        .fetch_all(&mut *tx)
        .await?;
        let mut from = None;
        let mut to = None;
        for row in layouts {
            let value: Value = serde_json::from_str(row.try_get("dataJson")?)?;
            if row.try_get::<String, _>("workspaceId")? == source.id {
                from = Some(value);
            } else {
                to = Some(value);
            }
        }
        if !source_tabs.is_empty() {
            let layout = super::workspace_transfer_layout::merge_transfer_layout(
                &source.id,
                &destination.id,
                from,
                to,
                &source_tabs,
                &destination_tabs,
            );
            sqlx::query("INSERT INTO workbenchLayouts (workspaceId, dataJson) VALUES (?, ?) ON CONFLICT(workspaceId) DO UPDATE SET dataJson = excluded.dataJson")
                .bind(&destination.id).bind(serde_json::to_string(&layout)?).execute(&mut *tx).await?;
            sqlx::query("DELETE FROM workbenchLayouts WHERE workspaceId = ?")
                .bind(&source.id)
                .execute(&mut *tx)
                .await?;
        }
        sqlx::query("INSERT OR IGNORE INTO linkedReviews (workspaceId, dismissed, provider, number, url, linkedAt) SELECT ?, dismissed, provider, number, url, linkedAt FROM linkedReviews WHERE workspaceId = ?")
            .bind(&destination.id).bind(&source.id).execute(&mut *tx).await?;
        sqlx::query("DELETE FROM linkedReviews WHERE workspaceId = ?")
            .bind(&source.id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("INSERT OR IGNORE INTO linkedIssues (workspaceId, url, provider, repository, number, title, state, stateLabel, fetchedAt, fetchError, linkedAt) SELECT ?, url, provider, repository, number, title, state, stateLabel, fetchedAt, fetchError, linkedAt FROM linkedIssues WHERE workspaceId = ?")
            .bind(&destination.id).bind(&source.id).execute(&mut *tx).await?;
        sqlx::query("DELETE FROM linkedIssues WHERE workspaceId = ?")
            .bind(&source.id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("INSERT INTO runtimeMetadata (key, value) SELECT ?, value FROM runtimeMetadata WHERE key = ? ON CONFLICT(key) DO UPDATE SET value = MAX(value, excluded.value)")
            .bind(format!("workspace.activity.{}", destination.id)).bind(format!("workspace.activity.{}", source.id)).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(())
    }
}

#[cfg(test)]
#[path = "workspace_content_transfer_tests.rs"]
mod tests;

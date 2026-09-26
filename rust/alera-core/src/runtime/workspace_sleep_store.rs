use std::collections::BTreeMap;

use anyhow::Result;
use sqlx::Row;

use super::RuntimeStore;

const SLEPT_TABS_KEY_PREFIX: &str = "workspace.sleptTabs.";

impl RuntimeStore {
    /// Records the terminal tabs a workspace sleep stops. Their records stay
    /// for resume, so clients need this list to show them as closed.
    pub async fn record_workspace_sleep(&self, workspace_id: &str) -> Result<Vec<String>> {
        let tab_ids = self
            .list_workspace_tabs(workspace_id)
            .await?
            .into_iter()
            .filter(|tab| tab.kind == "terminal")
            .map(|tab| tab.id)
            .collect::<Vec<_>>();
        if tab_ids.is_empty() {
            self.clear_workspace_sleep(workspace_id).await?;
        } else {
            self.set_metadata(
                &format!("{SLEPT_TABS_KEY_PREFIX}{workspace_id}"),
                &serde_json::to_string(&tab_ids)?,
            )
            .await?;
        }
        Ok(tab_ids)
    }

    /// Wakes the workspace when [tab_id] is one of its slept terminals. A tab
    /// created after the sleep leaves the others asleep. Returns whether the
    /// workspace woke.
    pub async fn wake_workspace_for_tab(&self, workspace_id: &str, tab_id: &str) -> Result<bool> {
        let slept = self.slept_workspace_tabs(workspace_id).await?;
        if !slept.iter().any(|id| id == tab_id) {
            return Ok(false);
        }
        self.clear_workspace_sleep(workspace_id).await?;
        Ok(true)
    }

    pub async fn list_slept_workspace_tabs(&self) -> Result<BTreeMap<String, Vec<String>>> {
        let rows = sqlx::query("SELECT key, value FROM runtimeMetadata WHERE key LIKE ?")
            .bind(format!("{SLEPT_TABS_KEY_PREFIX}%"))
            .fetch_all(self.pool())
            .await?;
        let mut result = BTreeMap::new();
        for row in rows {
            let key: String = row.try_get("key")?;
            let value: String = row.try_get("value")?;
            let Some(workspace_id) = key.strip_prefix(SLEPT_TABS_KEY_PREFIX) else {
                continue;
            };
            if let Ok(tab_ids) = serde_json::from_str::<Vec<String>>(&value) {
                result.insert(workspace_id.to_string(), tab_ids);
            }
        }
        Ok(result)
    }

    async fn slept_workspace_tabs(&self, workspace_id: &str) -> Result<Vec<String>> {
        let Some(value) = self
            .get_metadata(&format!("{SLEPT_TABS_KEY_PREFIX}{workspace_id}"))
            .await?
        else {
            return Ok(Vec::new());
        };
        Ok(serde_json::from_str(&value).unwrap_or_default())
    }

    async fn clear_workspace_sleep(&self, workspace_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM runtimeMetadata WHERE key = ?")
            .bind(format!("{SLEPT_TABS_KEY_PREFIX}{workspace_id}"))
            .execute(self.pool())
            .await?;
        Ok(())
    }
}

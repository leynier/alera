use std::collections::BTreeMap;

use anyhow::Result;
use chrono::{DateTime, SecondsFormat, Utc};
use sqlx::Row;

use super::{
    RuntimeStore, RuntimeStoreError, SharedWorkbenchPrefsWriter, SharedWorkbenchViewPrefs,
    SharedWorkbenchViewPrefsRecord,
};

const VIEW_PREFS_KEY: &str = "workbench.sharedViewPrefs.v1";
const ACTIVITY_KEY_PREFIX: &str = "workspace.activity.";

impl RuntimeStore {
    pub async fn shared_workbench_view_prefs(&self) -> Result<SharedWorkbenchViewPrefsRecord> {
        let Some(encoded) = self.get_metadata(VIEW_PREFS_KEY).await? else {
            return Ok(SharedWorkbenchViewPrefsRecord::default());
        };
        Ok(serde_json::from_str(&encoded).unwrap_or_default())
    }

    pub async fn update_shared_workbench_view_prefs(
        &self,
        prefs: SharedWorkbenchViewPrefs,
        expected_revision: Option<i64>,
        writer: SharedWorkbenchPrefsWriter,
    ) -> Result<SharedWorkbenchViewPrefsRecord> {
        let current = self.shared_workbench_view_prefs().await?;
        if writer == SharedWorkbenchPrefsWriter::Mobile
            && expected_revision != Some(current.revision)
        {
            anyhow::bail!(RuntimeStoreError::Message(
                "Workbench view preferences changed on desktop. Refresh and retry.".to_string(),
            ));
        }
        let next = SharedWorkbenchViewPrefsRecord {
            revision: current.revision.saturating_add(1),
            desktop_initialized: current.desktop_initialized
                || writer == SharedWorkbenchPrefsWriter::Desktop,
            last_writer: writer,
            prefs,
        };
        self.set_metadata(VIEW_PREFS_KEY, &serde_json::to_string(&next)?)
            .await?;
        Ok(next)
    }

    pub async fn record_workspace_activity(
        &self,
        workspace_id: &str,
        at: DateTime<Utc>,
    ) -> Result<()> {
        let key = format!("{ACTIVITY_KEY_PREFIX}{workspace_id}");
        if let Some(current) = self.get_metadata(&key).await? {
            if DateTime::parse_from_rfc3339(&current)
                .is_ok_and(|value| value.with_timezone(&Utc) >= at)
            {
                return Ok(());
            }
        }
        self.set_metadata(&key, &at.to_rfc3339_opts(SecondsFormat::Millis, true))
            .await
    }

    pub async fn record_workspace_activity_batch(
        &self,
        entries: BTreeMap<String, DateTime<Utc>>,
    ) -> Result<BTreeMap<String, DateTime<Utc>>> {
        for (workspace_id, at) in entries {
            self.record_workspace_activity(&workspace_id, at).await?;
        }
        self.list_workspace_activity().await
    }

    pub async fn list_workspace_activity(&self) -> Result<BTreeMap<String, DateTime<Utc>>> {
        let rows = sqlx::query("SELECT key, value FROM runtimeMetadata WHERE key LIKE ?")
            .bind(format!("{ACTIVITY_KEY_PREFIX}%"))
            .fetch_all(self.pool())
            .await?;
        let mut result = BTreeMap::new();
        for row in rows {
            let key: String = row.try_get("key")?;
            let value: String = row.try_get("value")?;
            let Some(workspace_id) = key.strip_prefix(ACTIVITY_KEY_PREFIX) else {
                continue;
            };
            if let Ok(at) = DateTime::parse_from_rfc3339(&value) {
                result.insert(workspace_id.to_string(), at.with_timezone(&Utc));
            }
        }
        Ok(result)
    }

    pub async fn remove_workspace_activity(&self, workspace_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM runtimeMetadata WHERE key = ?")
            .bind(format!("{ACTIVITY_KEY_PREFIX}{workspace_id}"))
            .execute(self.pool())
            .await?;
        Ok(())
    }
}

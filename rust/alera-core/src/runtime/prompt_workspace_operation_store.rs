//! New Workspace from Prompt operations started through the runtime.
//!
//! The runtime host owns the record's shape; the store keeps it as JSON next
//! to the columns it filters and deduplicates on. `requestId` makes a retried
//! start return the first operation instead of creating a second workspace.

use anyhow::Result;
use chrono::Utc;
use serde_json::Value;
use sqlx::Row;

use super::RuntimeStore;

pub(super) const PROMPT_WORKSPACE_OPERATION_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS promptWorkspaceOperations (
        id TEXT PRIMARY KEY,
        requestId TEXT UNIQUE,
        status TEXT NOT NULL,
        dataJson TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE INDEX IF NOT EXISTS promptWorkspaceOperationsUpdatedAtIdx ON promptWorkspaceOperations(updatedAt DESC);",
];

/// Operations kept after they finish, newest first.
const RETAINED_FINISHED_OPERATIONS: i64 = 200;

#[derive(Debug, Clone, PartialEq)]
pub struct PromptWorkspaceOperationRecord {
    pub id: String,
    pub request_id: Option<String>,
    pub status: String,
    pub data: Value,
    pub created_at: String,
    pub updated_at: String,
}

impl RuntimeStore {
    /// Inserts the operation, or returns the one already started with the
    /// same `request_id`.
    pub async fn insert_prompt_workspace_operation(
        &self,
        id: &str,
        request_id: Option<&str>,
        status: &str,
        data: &Value,
    ) -> Result<PromptWorkspaceOperationRecord> {
        if let Some(request_id) = request_id {
            if let Some(existing) = self
                .find_prompt_workspace_operation_by_request(request_id)
                .await?
            {
                return Ok(existing);
            }
        }
        let now = Utc::now().to_rfc3339();
        sqlx::query(
            "INSERT INTO promptWorkspaceOperations (id, requestId, status, dataJson, createdAt, \
             updatedAt) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(requestId) DO NOTHING",
        )
        .bind(id)
        .bind(request_id)
        .bind(status)
        .bind(serde_json::to_string(data)?)
        .bind(&now)
        .bind(&now)
        .execute(self.pool())
        .await?;
        match request_id {
            Some(request_id) => self
                .find_prompt_workspace_operation_by_request(request_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("prompt workspace operation disappeared")),
            None => self
                .find_prompt_workspace_operation(id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("prompt workspace operation disappeared")),
        }
    }

    pub async fn update_prompt_workspace_operation(
        &self,
        id: &str,
        status: &str,
        data: &Value,
    ) -> Result<Option<PromptWorkspaceOperationRecord>> {
        sqlx::query(
            "UPDATE promptWorkspaceOperations SET status = ?, dataJson = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(status)
        .bind(serde_json::to_string(data)?)
        .bind(Utc::now().to_rfc3339())
        .bind(id)
        .execute(self.pool())
        .await?;
        self.find_prompt_workspace_operation(id).await
    }

    pub async fn find_prompt_workspace_operation(
        &self,
        id: &str,
    ) -> Result<Option<PromptWorkspaceOperationRecord>> {
        let row = sqlx::query(
            "SELECT id, requestId, status, dataJson, createdAt, updatedAt \
             FROM promptWorkspaceOperations WHERE id = ?",
        )
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(operation_from_row).transpose()
    }

    pub async fn find_prompt_workspace_operation_by_request(
        &self,
        request_id: &str,
    ) -> Result<Option<PromptWorkspaceOperationRecord>> {
        let row = sqlx::query(
            "SELECT id, requestId, status, dataJson, createdAt, updatedAt \
             FROM promptWorkspaceOperations WHERE requestId = ?",
        )
        .bind(request_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(operation_from_row).transpose()
    }

    pub async fn list_prompt_workspace_operations(
        &self,
        limit: i64,
    ) -> Result<Vec<PromptWorkspaceOperationRecord>> {
        let rows = sqlx::query(
            "SELECT id, requestId, status, dataJson, createdAt, updatedAt \
             FROM promptWorkspaceOperations ORDER BY updatedAt DESC LIMIT ?",
        )
        .bind(limit.clamp(1, RETAINED_FINISHED_OPERATIONS))
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(operation_from_row).collect()
    }

    /// Operations a runtime restart interrupted.
    pub async fn list_running_prompt_workspace_operations(
        &self,
    ) -> Result<Vec<PromptWorkspaceOperationRecord>> {
        let rows = sqlx::query(
            "SELECT id, requestId, status, dataJson, createdAt, updatedAt \
             FROM promptWorkspaceOperations WHERE status = 'running'",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(operation_from_row).collect()
    }

    /// Drops the oldest finished operations beyond the retained count.
    pub async fn prune_prompt_workspace_operations(&self) -> Result<u64> {
        let result = sqlx::query(
            "DELETE FROM promptWorkspaceOperations WHERE status != 'running' AND id NOT IN \
             (SELECT id FROM promptWorkspaceOperations ORDER BY updatedAt DESC LIMIT ?)",
        )
        .bind(RETAINED_FINISHED_OPERATIONS)
        .execute(self.pool())
        .await?;
        Ok(result.rows_affected())
    }
}

fn operation_from_row(row: sqlx::sqlite::SqliteRow) -> Result<PromptWorkspaceOperationRecord> {
    let data: String = row.try_get("dataJson")?;
    Ok(PromptWorkspaceOperationRecord {
        id: row.try_get("id")?,
        request_id: row.try_get("requestId")?,
        status: row.try_get("status")?,
        data: serde_json::from_str(&data)?,
        created_at: row.try_get("createdAt")?,
        updated_at: row.try_get("updatedAt")?,
    })
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use crate::runtime::RuntimeStore;

    async fn store() -> (tempfile::TempDir, RuntimeStore) {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        (directory, store)
    }

    #[tokio::test]
    async fn a_repeated_request_id_returns_the_first_operation() {
        let (_directory, store) = store().await;
        let first = store
            .insert_prompt_workspace_operation("op-1", Some("req-1"), "running", &json!({ "a": 1 }))
            .await
            .unwrap();
        let again = store
            .insert_prompt_workspace_operation("op-2", Some("req-1"), "running", &json!({ "a": 2 }))
            .await
            .unwrap();
        assert_eq!(again.id, first.id);
        assert_eq!(again.data, json!({ "a": 1 }));
        assert!(store
            .find_prompt_workspace_operation("op-2")
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn updates_list_and_running_filters() {
        let (_directory, store) = store().await;
        store
            .insert_prompt_workspace_operation("op-1", None, "running", &json!({}))
            .await
            .unwrap();
        store
            .insert_prompt_workspace_operation("op-2", None, "running", &json!({}))
            .await
            .unwrap();
        let updated = store
            .update_prompt_workspace_operation("op-1", "completed", &json!({ "done": true }))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(updated.status, "completed");
        assert_eq!(updated.data["done"], true);
        let running = store
            .list_running_prompt_workspace_operations()
            .await
            .unwrap();
        assert_eq!(running.len(), 1);
        assert_eq!(running[0].id, "op-2");
        assert_eq!(
            store
                .list_prompt_workspace_operations(10)
                .await
                .unwrap()
                .len(),
            2
        );
        assert_eq!(store.prune_prompt_workspace_operations().await.unwrap(), 0);
    }
}

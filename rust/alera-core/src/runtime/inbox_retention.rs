use anyhow::Result;
use chrono::{Duration, Utc};
use sqlx::Row;

use super::inbox_models::*;
use super::inbox_store::{placeholders, sqlite_timestamp};
use super::RuntimeStore;

const EXTERNAL_ROW: &str = "substr(from_handle, 1, 4) = 'ext:' OR substr(to_handle, 1, 4) = 'ext:'";
const DELETE_BATCH: usize = 400;

impl RuntimeStore {
    /// Deletes every message sent from or to `inbox`, with the threads it started.
    pub async fn purge_inbox(&self, inbox: &str) -> Result<u64> {
        validate_inbox_address(inbox)?;
        let roots: Vec<String> = sqlx::query(
            "SELECT id FROM orchestrationMessages WHERE from_handle = ? AND thread_id IS NULL",
        )
        .bind(inbox)
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(|row| row.try_get("id"))
        .collect::<std::result::Result<_, _>>()?;
        let mut tx = self.pool().begin().await?;
        let mut deleted =
            sqlx::query("DELETE FROM orchestrationMessages WHERE from_handle = ? OR to_handle = ?")
                .bind(inbox)
                .bind(inbox)
                .execute(&mut *tx)
                .await?
                .rows_affected();
        for chunk in roots.chunks(DELETE_BATCH) {
            let sql = format!(
                "DELETE FROM orchestrationMessages WHERE thread_id IN ({})",
                placeholders(chunk.len())
            );
            let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
            for id in chunk {
                query = query.bind(id);
            }
            deleted += query.execute(&mut *tx).await?.rows_affected();
        }
        tx.commit().await?;
        Ok(deleted)
    }

    /// Removes inbox conversations idle for longer than the history window.
    /// A conversation with a question still waiting for delivery is kept whole.
    pub async fn prune_inbox_history(&self) -> Result<u64> {
        self.expire_orchestration_messages().await?;
        let cutoff = sqlite_timestamp(Utc::now() - Duration::seconds(INBOX_HISTORY_SECONDS));
        let roots: Vec<String> = sqlx::query(
            "SELECT r.id FROM orchestrationMessages r \
             WHERE substr(r.from_handle, 1, 4) = 'ext:' AND r.thread_id IS NULL \
             AND NOT EXISTS (SELECT 1 FROM orchestrationMessages m \
               WHERE (m.id = r.id OR m.thread_id = r.id) \
               AND (m.created_at >= ?1 OR (substr(m.from_handle, 1, 4) = 'ext:' \
                 AND m.state = 'queued' AND m.delivered_at IS NULL AND m.read = 0)))",
        )
        .bind(&cutoff)
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(|row| row.try_get("id"))
        .collect::<std::result::Result<_, _>>()?;
        let mut tx = self.pool().begin().await?;
        let mut deleted = 0;
        for chunk in roots.chunks(DELETE_BATCH) {
            let marks = placeholders(chunk.len());
            let sql = format!(
                "DELETE FROM orchestrationMessages WHERE id IN ({marks}) OR thread_id IN ({marks})"
            );
            let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
            for _ in 0..2 {
                for id in chunk {
                    query = query.bind(id);
                }
            }
            deleted += query.execute(&mut *tx).await?.rows_affected();
        }
        // Loose messages to an inbox that belong to no question it started.
        deleted += sqlx::query(sqlx::AssertSqlSafe(format!(
            "DELETE FROM orchestrationMessages WHERE ({EXTERNAL_ROW}) AND created_at < ? \
             AND NOT (substr(from_handle, 1, 4) = 'ext:' AND thread_id IS NULL) \
             AND (thread_id IS NULL OR NOT EXISTS (SELECT 1 FROM orchestrationMessages root \
               WHERE root.id = orchestrationMessages.thread_id))"
        )))
        .bind(&cutoff)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        tx.commit().await?;
        Ok(deleted)
    }
}

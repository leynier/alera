use anyhow::Result;
use sqlx::Row;

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn ensure_column(
        &self,
        table: &str,
        column: &str,
        definition: &str,
    ) -> Result<()> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!("PRAGMA table_info({table})")))
            .fetch_all(self.pool())
            .await?;
        let exists = rows.iter().any(|row| {
            row.try_get::<String, _>("name")
                .is_ok_and(|name| name == column)
        });
        if !exists {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "ALTER TABLE {table} ADD COLUMN {column} {definition}"
            )))
            .execute(self.pool())
            .await?;
        }
        Ok(())
    }
}

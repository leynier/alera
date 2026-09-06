use anyhow::Result;
use sqlx::Row;

use super::RuntimeStore;

impl RuntimeStore {
    /// Only the host holding exclusive runtime ownership may retire feature data.
    /// Ordinary store opens can share a profile with an older, still-running host.
    pub async fn retire_removed_features(&self) -> Result<()> {
        let mut transaction = self.pool().begin().await?;
        for statement in [
            // The trigger belongs to workspaceTabs and survives dropping its target table.
            "DROP TRIGGER IF EXISTS codexChatStateDeleteTab",
            "DROP TABLE IF EXISTS agentCanvasEvents",
            "DROP TABLE IF EXISTS agentCanvasDecisions",
            "DROP TABLE IF EXISTS agentCanvasRevisions",
            "DROP TABLE IF EXISTS agentCanvases",
            "DROP TABLE IF EXISTS browserTrustedCertificates",
            "DROP TABLE IF EXISTS browserPermissions",
            "DROP TABLE IF EXISTS browserClosedTabs",
            "DROP TABLE IF EXISTS browserHistory",
            "DROP TABLE IF EXISTS browserProfiles",
            "DROP TABLE IF EXISTS codexChatState",
            "DELETE FROM workspaceTabs WHERE kind IN ('mobileEmulator', 'browser', 'codex')",
        ] {
            sqlx::query(statement).execute(&mut *transaction).await?;
        }
        transaction.commit().await?;
        Ok(())
    }

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

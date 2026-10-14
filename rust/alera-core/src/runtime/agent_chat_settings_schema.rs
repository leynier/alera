//! Additive settings tables. Reopening a current store performs no writes.

use anyhow::Result;

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn migrate_agent_chat_settings(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        for statement in [
            "CREATE TABLE IF NOT EXISTS agentChatSettingsRevisions (
                domain TEXT PRIMARY KEY,
                revision INTEGER NOT NULL CHECK (revision >= 0)
            )",
            "CREATE TABLE IF NOT EXISTS agentChatPreferences (
                section TEXT NOT NULL,
                entryKey TEXT NOT NULL,
                valueJson TEXT NOT NULL,
                revision INTEGER NOT NULL,
                PRIMARY KEY (section, entryKey)
            )",
            "CREATE TABLE IF NOT EXISTS agentChatProviderInstances (
                providerInstanceId TEXT PRIMARY KEY,
                envelopeJson TEXT NOT NULL,
                secretRefsJson TEXT NOT NULL,
                revision INTEGER NOT NULL
            )",
            "CREATE TABLE IF NOT EXISTS agentChatReadCursors (
                chatId TEXT PRIMARY KEY,
                cursor INTEGER NOT NULL CHECK (cursor >= 0),
                FOREIGN KEY (chatId) REFERENCES agentChatSessions(chatId) ON DELETE CASCADE
            )",
        ] {
            sqlx::query(statement).execute(&mut *tx).await?;
        }
        tx.commit().await?;
        Ok(())
    }
}

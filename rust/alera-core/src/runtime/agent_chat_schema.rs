//! DDL for agent chats. Pending requests live in the snapshot
//! header; turns and items get their own rows so history pages without loading the
//! whole transcript.
//!
//! The triggers keep chats correct whichever path touches their tab or
//! workspace: removing an `agentChat` tab archives the chat instead of
//! deleting its transcript, moving the tab (hand on) moves the chat with it,
//! and deleting the workspace deletes its chats. They do not rely on
//! `PRAGMA foreign_keys`, which the orchestration reset toggles.

use anyhow::Result;

use super::RuntimeStore;

const SQL_NOW: &str = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";

const TABLES: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS agentChatSessions (
        chatId TEXT PRIMARY KEY,
        workspaceId TEXT NOT NULL,
        tabId TEXT NOT NULL,
        providerInstanceId TEXT NOT NULL,
        provider TEXT NOT NULL,
        nativeThreadId TEXT,
        generation INTEGER NOT NULL DEFAULT 1,
        archived INTEGER NOT NULL DEFAULT 0,
        archivedAt TEXT,
        cursor INTEGER NOT NULL DEFAULT 0,
        snapshotJson TEXT NOT NULL,
        metadataJson TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE INDEX IF NOT EXISTS agentChatSessionsWorkspaceIdx \
     ON agentChatSessions(workspaceId, archived, updatedAt);",
    "CREATE UNIQUE INDEX IF NOT EXISTS agentChatSessionsOpenTabIdx \
     ON agentChatSessions(tabId) WHERE archived = 0;",
    "CREATE TABLE IF NOT EXISTS agentChatItems (
        chatId TEXT NOT NULL,
        itemId TEXT NOT NULL,
        seq INTEGER NOT NULL,
        turnId TEXT,
        itemJson TEXT NOT NULL,
        byteSize INTEGER NOT NULL,
        updatedCursor INTEGER NOT NULL,
        PRIMARY KEY (chatId, itemId)
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS agentChatItemsSeqIdx ON agentChatItems(chatId, seq);",
    "CREATE INDEX IF NOT EXISTS agentChatItemsClientMessageIdx \
     ON agentChatItems(chatId, json_extract(itemJson, '$.clientMessageId'));",
    "CREATE TABLE IF NOT EXISTS agentChatTurns (
        chatId TEXT NOT NULL,
        turnId TEXT NOT NULL,
        seq INTEGER NOT NULL,
        status TEXT NOT NULL,
        turnJson TEXT NOT NULL,
        byteSize INTEGER NOT NULL,
        updatedCursor INTEGER NOT NULL,
        PRIMARY KEY (chatId, turnId)
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS agentChatTurnsSeqIdx ON agentChatTurns(chatId, seq);",
    "CREATE INDEX IF NOT EXISTS agentChatTurnsStatusIdx ON agentChatTurns(chatId, status);",
    "CREATE TABLE IF NOT EXISTS agentChatEvents (
        chatId TEXT NOT NULL,
        cursor INTEGER NOT NULL,
        deltaJson TEXT NOT NULL,
        occurredAt TEXT NOT NULL,
        PRIMARY KEY (chatId, cursor)
    );",
    "CREATE TABLE IF NOT EXISTS agentChatNativeIds (
        chatId TEXT NOT NULL,
        generation INTEGER NOT NULL,
        kind TEXT NOT NULL,
        nativeIdJson TEXT NOT NULL,
        appId TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        PRIMARY KEY (chatId, generation, kind, nativeIdJson)
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS agentChatNativeIdsAppIdx \
     ON agentChatNativeIds(chatId, kind, appId);",
    "CREATE TABLE IF NOT EXISTS agentChatReceipts (
        callerScope TEXT NOT NULL,
        requestId TEXT NOT NULL,
        chatId TEXT,
        digest TEXT NOT NULL,
        receiptJson TEXT NOT NULL,
        cursor INTEGER,
        createdAt TEXT NOT NULL,
        PRIMARY KEY (callerScope, requestId)
    );",
    "CREATE INDEX IF NOT EXISTS agentChatReceiptsChatIdx ON agentChatReceipts(chatId);",
    "CREATE INDEX IF NOT EXISTS agentChatReceiptsCreatedIdx ON agentChatReceipts(createdAt);",
    "CREATE TABLE IF NOT EXISTS agentChatCancelledMessages (
        chatId TEXT NOT NULL,
        clientMessageId TEXT NOT NULL,
        cancelledAt TEXT NOT NULL,
        PRIMARY KEY (chatId, clientMessageId),
        FOREIGN KEY (chatId) REFERENCES agentChatSessions(chatId) ON DELETE CASCADE
    );",
];

fn triggers() -> Vec<String> {
    vec![
        format!(
            "CREATE TRIGGER IF NOT EXISTS agentChatArchiveOnTabDelete AFTER DELETE ON workspaceTabs \
             WHEN OLD.kind = 'agentChat' BEGIN \
             UPDATE agentChatSessions SET archived = 1, archivedAt = {SQL_NOW}, updatedAt = {SQL_NOW} \
             WHERE tabId = OLD.id AND archived = 0; END;"
        ),
        format!(
            "CREATE TRIGGER IF NOT EXISTS agentChatFollowTabWorkspace \
             AFTER UPDATE OF workspaceId ON workspaceTabs \
             WHEN OLD.kind = 'agentChat' AND OLD.workspaceId IS NOT NEW.workspaceId BEGIN \
             UPDATE agentChatSessions SET workspaceId = NEW.workspaceId, \
             snapshotJson = json_set(snapshotJson, '$.workspaceId', NEW.workspaceId), \
             updatedAt = {SQL_NOW} WHERE tabId = OLD.id AND archived = 0; END;"
        ),
        "CREATE TRIGGER IF NOT EXISTS agentChatDeleteWithWorkspace AFTER DELETE ON workspaces BEGIN \
         DELETE FROM agentChatSessions WHERE workspaceId = OLD.id; END;"
            .to_string(),
        "CREATE TRIGGER IF NOT EXISTS agentChatDeleteChildren AFTER DELETE ON agentChatSessions BEGIN \
         DELETE FROM agentChatItems WHERE chatId = OLD.chatId; \
         DELETE FROM agentChatTurns WHERE chatId = OLD.chatId; \
         DELETE FROM agentChatEvents WHERE chatId = OLD.chatId; \
         DELETE FROM agentChatNativeIds WHERE chatId = OLD.chatId; \
         DELETE FROM agentChatCancelledMessages WHERE chatId = OLD.chatId; \
         DELETE FROM agentChatReceipts WHERE chatId = OLD.chatId; END;"
            .to_string(),
    ]
}

impl RuntimeStore {
    pub(super) async fn migrate_agent_chats(&self) -> Result<()> {
        for statement in TABLES {
            sqlx::query(*statement).execute(self.pool()).await?;
        }
        self.ensure_column("agentChatSessions", "metadataJson", "TEXT")
            .await?;
        let mut tx = self.pool().begin().await?;
        super::agent_chat_turns::migrate_turn_headers_in(&mut tx).await?;
        for statement in triggers() {
            super::schema_object_replacement::replace_schema_object(&mut tx, &statement).await?;
        }
        tx.commit().await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::super::agent_chat_test_support::{create_chat, store_with_workspace};
    use super::*;

    async fn data_version(connection: &mut sqlx::SqliteConnection) -> i64 {
        sqlx::query_scalar("PRAGMA data_version")
            .fetch_one(connection)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn a_current_chat_store_reopen_preserves_the_live_read_to_write_snapshot() {
        let (dir, store) = store_with_workspace("ws").await;
        let chat_id = create_chat(&store, "ws", "tab").await;
        let mut transaction = store.pool().begin().await.unwrap();
        let stored_chat: String =
            sqlx::query_scalar("SELECT chatId FROM agentChatSessions WHERE chatId = ?")
                .bind(&chat_id)
                .fetch_one(&mut *transaction)
                .await
                .unwrap();
        assert_eq!(stored_chat, chat_id);

        let cli = RuntimeStore::open(dir.path()).await.unwrap();
        cli.pool().close().await;

        sqlx::query("UPDATE workspaces SET name = 'Live Runtime Write' WHERE id = 'ws'")
            .execute(&mut *transaction)
            .await
            .unwrap();
        transaction.commit().await.unwrap();
        assert_eq!(
            store.find_workspace("ws").await.unwrap().unwrap().name,
            "Live Runtime Write"
        );
    }

    #[tokio::test]
    async fn an_outdated_chat_cleanup_trigger_upgrades_once_and_then_reopens_without_writes() {
        let (dir, store) = store_with_workspace("ws").await;
        let chat_id = create_chat(&store, "ws", "tab").await;
        let before = store.agent_chat(&chat_id).await.unwrap().unwrap();
        store
            .cancel_agent_chat_message(&chat_id, "cancelled-message")
            .await
            .unwrap();
        let mut connection = store.pool().acquire().await.unwrap();
        for statement in [
            "DROP TRIGGER agentChatDeleteChildren",
            "CREATE TRIGGER agentChatDeleteChildren AFTER DELETE ON agentChatSessions BEGIN \
             DELETE FROM agentChatItems WHERE chatId = OLD.chatId; END;",
        ] {
            sqlx::query(statement)
                .execute(&mut *connection)
                .await
                .unwrap();
        }
        let version_before = data_version(&mut connection).await;
        let migrated = RuntimeStore::open(dir.path()).await.unwrap();
        migrated.pool().close().await;
        let version_after = data_version(&mut connection).await;
        assert_eq!(version_after, version_before + 1);
        assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap(), before);
        let retained_markers: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM agentChatCancelledMessages WHERE chatId = ?")
                .bind(&chat_id)
                .fetch_one(&mut *connection)
                .await
                .unwrap();
        assert_eq!(retained_markers, 1);

        let reopened = RuntimeStore::open(dir.path()).await.unwrap();
        reopened.pool().close().await;
        assert_eq!(data_version(&mut connection).await, version_after);

        sqlx::query("PRAGMA foreign_keys = OFF")
            .execute(&mut *connection)
            .await
            .unwrap();
        sqlx::query("DELETE FROM agentChatSessions WHERE chatId = ?")
            .bind(&chat_id)
            .execute(&mut *connection)
            .await
            .unwrap();
        let markers: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM agentChatCancelledMessages WHERE chatId = ?")
                .bind(&chat_id)
                .fetch_one(&mut *connection)
                .await
                .unwrap();
        assert_eq!(markers, 0);
        sqlx::query("PRAGMA foreign_keys = ON")
            .execute(&mut *connection)
            .await
            .unwrap();
    }
}

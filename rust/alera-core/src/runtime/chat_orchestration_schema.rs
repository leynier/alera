//! DDL for chat orchestration. The tables carry no foreign key or trigger
//! tying them to chats or workspaces: deleting either leaves the task, its
//! lineage and its result readable, and restart recovery settles the rest.

use anyhow::{bail, Result};

use super::chat_orchestration_models::{
    CHAT_ORCHESTRATION_SCHEMA_VERSION, CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY,
};
use super::RuntimeStore;

const TABLES: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS chatOrchestrationTasks (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        taskId TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        callerScope TEXT NOT NULL,
        parentTaskId TEXT,
        rootTaskId TEXT NOT NULL,
        depth INTEGER NOT NULL DEFAULT 0,
        parentChatId TEXT,
        rootChatId TEXT,
        childChatId TEXT,
        childTurnId TEXT,
        projectId TEXT,
        workspaceId TEXT,
        hostId TEXT,
        targetJson TEXT NOT NULL,
        title TEXT,
        role TEXT,
        brief TEXT NOT NULL,
        notify TEXT NOT NULL,
        launchOptionsJson TEXT,
        resultText TEXT,
        resultTruncated INTEGER NOT NULL DEFAULT 0,
        resultDelivery TEXT NOT NULL DEFAULT 'pending',
        errorCode TEXT,
        error TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        cancelRequestedAt TEXT,
        settledAt TEXT
    );",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationTasksParentChatIdx \
     ON chatOrchestrationTasks(parentChatId, sequence);",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationTasksChildChatIdx \
     ON chatOrchestrationTasks(childChatId, sequence);",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationTasksParentTaskIdx \
     ON chatOrchestrationTasks(parentTaskId);",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationTasksRootIdx \
     ON chatOrchestrationTasks(rootTaskId, sequence);",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationTasksWorkspaceIdx \
     ON chatOrchestrationTasks(workspaceId, sequence);",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationTasksRootChatIdx \
     ON chatOrchestrationTasks(rootChatId, sequence);",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationTasksProjectIdx \
     ON chatOrchestrationTasks(projectId, sequence);",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationTasksStatusIdx \
     ON chatOrchestrationTasks(status);",
    "CREATE TABLE IF NOT EXISTS chatOrchestrationWakeCounters (
        parentChatId TEXT PRIMARY KEY,
        generation INTEGER NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS chatOrchestrationWakes (
        parentChatId TEXT NOT NULL,
        generation INTEGER NOT NULL,
        clientMessageId TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        sealedAt TEXT,
        deliveredAt TEXT,
        PRIMARY KEY (parentChatId, generation)
    );",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationWakesStatusIdx \
     ON chatOrchestrationWakes(status, parentChatId, generation);",
    "CREATE TABLE IF NOT EXISTS chatOrchestrationWakeEntries (
        parentChatId TEXT NOT NULL,
        generation INTEGER NOT NULL,
        taskId TEXT NOT NULL,
        taskStatus TEXT NOT NULL,
        taskRevision INTEGER NOT NULL,
        PRIMARY KEY (taskId, taskRevision)
    );",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationWakeEntriesWakeIdx \
     ON chatOrchestrationWakeEntries(parentChatId, generation);",
    "CREATE TABLE IF NOT EXISTS chatOrchestrationReceipts (
        scope TEXT NOT NULL,
        verb TEXT NOT NULL,
        requestId TEXT NOT NULL,
        digest TEXT NOT NULL,
        responseJson TEXT NOT NULL,
        taskId TEXT,
        createdAt TEXT NOT NULL,
        PRIMARY KEY (scope, verb, requestId)
    );",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationReceiptsCreatedIdx \
     ON chatOrchestrationReceipts(createdAt);",
    "CREATE TABLE IF NOT EXISTS chatOrchestrationCredentials (
        credentialHash TEXT PRIMARY KEY,
        chatId TEXT NOT NULL,
        generation INTEGER NOT NULL,
        issuedAt TEXT NOT NULL,
        revokedAt TEXT,
        revokeReason TEXT
    );",
    "CREATE INDEX IF NOT EXISTS chatOrchestrationCredentialsChatIdx \
     ON chatOrchestrationCredentials(chatId, generation);",
];

impl RuntimeStore {
    /// Idempotent. A store stamped by a newer runtime fails closed before any
    /// table is touched, so an older binary never writes rows it cannot read.
    pub(super) async fn migrate_chat_orchestration(&self) -> Result<()> {
        let stamp_needed = if let Some(stored) = self
            .get_metadata(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
            .await?
        {
            match stored.parse::<i64>() {
                Ok(version) if version <= CHAT_ORCHESTRATION_SCHEMA_VERSION => {
                    version != CHAT_ORCHESTRATION_SCHEMA_VERSION
                }
                _ => bail!(
                    "unsupported chat orchestration schema version {stored}; this runtime \
                     understands {CHAT_ORCHESTRATION_SCHEMA_VERSION} and refuses to modify a \
                     newer store"
                ),
            }
        } else {
            true
        };
        let mut tx = self.pool().begin().await?;
        for statement in TABLES {
            sqlx::query(*statement).execute(&mut *tx).await?;
        }
        if stamp_needed {
            sqlx::query(
                "INSERT INTO runtimeMetadata (key, value, updatedAt) VALUES (?, ?, ?) \
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
            )
            .bind(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
            .bind(CHAT_ORCHESTRATION_SCHEMA_VERSION.to_string())
            .bind(super::format_timestamp(chrono::Utc::now()))
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const OLD_TIMESTAMP: &str = "2001-01-01T00:00:00.000Z";

    #[tokio::test]
    async fn a_current_schema_stamp_keeps_its_timestamp_and_commits_nothing() {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        sqlx::query("UPDATE runtimeMetadata SET updatedAt = ? WHERE key = ?")
            .bind(OLD_TIMESTAMP)
            .bind(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
            .execute(store.pool())
            .await
            .unwrap();
        let mut observer = store.pool().acquire().await.unwrap();
        let before: i64 = sqlx::query_scalar("PRAGMA data_version")
            .fetch_one(&mut *observer)
            .await
            .unwrap();
        store.migrate_chat_orchestration().await.unwrap();
        let after: i64 = sqlx::query_scalar("PRAGMA data_version")
            .fetch_one(&mut *observer)
            .await
            .unwrap();
        assert_eq!(after, before);
        let timestamp: String =
            sqlx::query_scalar("SELECT updatedAt FROM runtimeMetadata WHERE key = ?")
                .bind(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
                .fetch_one(&mut *observer)
                .await
                .unwrap();
        assert_eq!(timestamp, OLD_TIMESTAMP);
    }

    #[tokio::test]
    async fn missing_and_older_schema_stamps_are_written_with_the_current_version() {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        for version in [None, Some("0")] {
            match version {
                Some(version) => {
                    sqlx::query(
                        "UPDATE runtimeMetadata SET value = ?, updatedAt = ? WHERE key = ?",
                    )
                    .bind(version)
                    .bind(OLD_TIMESTAMP)
                    .bind(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
                    .execute(store.pool())
                    .await
                    .unwrap();
                }
                None => {
                    store
                        .delete_metadata(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
                        .await
                        .unwrap();
                }
            }
            store.migrate_chat_orchestration().await.unwrap();
            assert_eq!(
                store
                    .get_metadata(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
                    .await
                    .unwrap(),
                Some(CHAT_ORCHESTRATION_SCHEMA_VERSION.to_string())
            );
            let timestamp: String =
                sqlx::query_scalar("SELECT updatedAt FROM runtimeMetadata WHERE key = ?")
                    .bind(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
                    .fetch_one(store.pool())
                    .await
                    .unwrap();
            assert_ne!(timestamp, OLD_TIMESTAMP);
        }
    }

    #[tokio::test]
    async fn a_future_schema_stamp_is_refused_before_missing_tables_are_recreated() {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        let future = (CHAT_ORCHESTRATION_SCHEMA_VERSION + 1).to_string();
        store
            .set_metadata(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY, &future)
            .await
            .unwrap();
        sqlx::query("DROP TABLE chatOrchestrationWakeCounters")
            .execute(store.pool())
            .await
            .unwrap();
        assert!(store.migrate_chat_orchestration().await.is_err());
        let exists: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'chatOrchestrationWakeCounters'",
        )
        .fetch_one(store.pool())
        .await
        .unwrap();
        assert_eq!(exists, 0);
        assert_eq!(
            store
                .get_metadata(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
                .await
                .unwrap(),
            Some(future)
        );
    }
}

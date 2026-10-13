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
        if let Some(stored) = self
            .get_metadata(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
            .await?
        {
            match stored.parse::<i64>() {
                Ok(version) if version <= CHAT_ORCHESTRATION_SCHEMA_VERSION => {}
                _ => bail!(
                    "unsupported chat orchestration schema version {stored}; this runtime \
                     understands {CHAT_ORCHESTRATION_SCHEMA_VERSION} and refuses to modify a \
                     newer store"
                ),
            }
        }
        let mut tx = self.pool().begin().await?;
        for statement in TABLES {
            sqlx::query(*statement).execute(&mut *tx).await?;
        }
        sqlx::query(
            "INSERT INTO runtimeMetadata (key, value, updatedAt) VALUES (?, ?, ?) \
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
        )
        .bind(CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY)
        .bind(CHAT_ORCHESTRATION_SCHEMA_VERSION.to_string())
        .bind(super::format_timestamp(chrono::Utc::now()))
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }
}

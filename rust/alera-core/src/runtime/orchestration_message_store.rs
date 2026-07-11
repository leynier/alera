use anyhow::Result;
use sqlx::sqlite::SqliteRow;
use sqlx::Row;
use uuid::Uuid;

use super::{
    OrchestrationMessage, OrchestrationMessagePriority, OrchestrationMessageType, RuntimeStore,
};

pub const ORCHESTRATION_HANDLE_MAX_BYTES: usize = 512;
pub const ORCHESTRATION_SUBJECT_MAX_BYTES: usize = 256;
pub const ORCHESTRATION_LIFECYCLE_BODY_MAX_BYTES: usize = 8 * 1024;
pub const ORCHESTRATION_BODY_MAX_BYTES: usize = 64 * 1024;
pub const ORCHESTRATION_THREAD_ID_MAX_BYTES: usize = 512;
pub const ORCHESTRATION_PAYLOAD_MAX_BYTES: usize = 64 * 1024;

// Timestamps in orchestration tables use SQLite's datetime('now') TEXT shape
// (UTC, second precision) so threshold comparisons can rely on lexicographic
// ordering, mirroring the Orca reference implementation.
pub(super) const ORCHESTRATION_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS orchestrationMessages (
        id TEXT NOT NULL,
        from_handle TEXT NOT NULL,
        to_handle TEXT NOT NULL,
        subject TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'status'
            CHECK(type IN ('status','dispatch','worker_done','merge_ready',
                           'escalation','handoff','decision_gate','heartbeat')),
        priority TEXT NOT NULL DEFAULT 'normal'
            CHECK(priority IN ('normal','high','urgent')),
        thread_id TEXT,
        payload TEXT,
        read INTEGER NOT NULL DEFAULT 0,
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        delivered_at TEXT
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS orchestrationMessagesIdIdx ON orchestrationMessages(id);",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesInboxIdx ON orchestrationMessages(to_handle, read);",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesUndeliveredIdx ON orchestrationMessages(to_handle, read, delivered_at, sequence);",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesThreadIdx ON orchestrationMessages(thread_id);",
    "CREATE TABLE IF NOT EXISTS orchestrationTasks (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        created_by_terminal_handle TEXT,
        task_title TEXT,
        display_name TEXT,
        spec TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','ready','dispatched','completed','failed','blocked')),
        deps TEXT NOT NULL DEFAULT '[]',
        result TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        completed_at TEXT
    );",
    "CREATE INDEX IF NOT EXISTS orchestrationTasksStatusIdx ON orchestrationTasks(status);",
    "CREATE INDEX IF NOT EXISTS orchestrationTasksParentIdx ON orchestrationTasks(parent_id);",
    "CREATE TABLE IF NOT EXISTS orchestrationDispatchContexts (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        assignee_handle TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','dispatched','completed','failed','circuit_broken')),
        failure_count INTEGER NOT NULL DEFAULT 0,
        last_failure TEXT,
        dispatched_at TEXT,
        completed_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        last_heartbeat_at TEXT
    );",
    "CREATE INDEX IF NOT EXISTS orchestrationDispatchTaskIdx ON orchestrationDispatchContexts(task_id);",
    "CREATE INDEX IF NOT EXISTS orchestrationDispatchStatusIdx ON orchestrationDispatchContexts(status);",
    "CREATE TABLE IF NOT EXISTS orchestrationDecisionGates (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        question TEXT NOT NULL,
        options TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','resolved','timeout')),
        resolution TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        resolved_at TEXT
    );",
    "CREATE INDEX IF NOT EXISTS orchestrationGatesTaskIdx ON orchestrationDecisionGates(task_id);",
    "CREATE TABLE IF NOT EXISTS orchestrationCoordinatorRuns (
        id TEXT PRIMARY KEY,
        spec TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'idle'
            CHECK(status IN ('idle','running','completed','failed')),
        coordinator_handle TEXT,
        poll_interval_ms INTEGER NOT NULL DEFAULT 2000,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        completed_at TEXT
    );",
];

// Future enum widening: SQLite cannot ALTER a CHECK constraint, so adding a
// message type or status value requires an Orca-style table rebuild migration.

pub struct NewOrchestrationMessage {
    pub from_handle: String,
    pub to_handle: String,
    pub subject: String,
    pub body: String,
    pub message_type: OrchestrationMessageType,
    pub priority: OrchestrationMessagePriority,
    pub thread_id: Option<String>,
    pub payload: Option<String>,
}

fn validate_message_field(value: &str, field: &str, max_bytes: usize) -> Result<()> {
    if value.len() > max_bytes {
        anyhow::bail!("message_too_large: {field} exceeds {max_bytes} UTF-8 bytes");
    }
    Ok(())
}

fn validate_new_orchestration_message(message: &NewOrchestrationMessage) -> Result<()> {
    validate_message_field(
        &message.from_handle,
        "from handle",
        ORCHESTRATION_HANDLE_MAX_BYTES,
    )?;
    validate_message_field(
        &message.to_handle,
        "to handle",
        ORCHESTRATION_HANDLE_MAX_BYTES,
    )?;
    validate_message_field(&message.subject, "subject", ORCHESTRATION_SUBJECT_MAX_BYTES)?;
    let body_limit = if message.message_type.is_lifecycle() {
        ORCHESTRATION_LIFECYCLE_BODY_MAX_BYTES
    } else {
        ORCHESTRATION_BODY_MAX_BYTES
    };
    validate_message_field(&message.body, "body", body_limit)?;
    if let Some(thread_id) = message.thread_id.as_deref() {
        validate_message_field(thread_id, "thread id", ORCHESTRATION_THREAD_ID_MAX_BYTES)?;
    }
    if let Some(payload) = message.payload.as_deref() {
        validate_message_field(payload, "payload", ORCHESTRATION_PAYLOAD_MAX_BYTES)?;
    }
    Ok(())
}

pub(super) fn orchestration_id(prefix: &str) -> String {
    let hex = Uuid::new_v4().simple().to_string();
    format!("{prefix}_{}", &hex[..16])
}

const MESSAGE_COLUMNS: &str = "id, from_handle, to_handle, subject, body, type, priority, \
     thread_id, payload, read, sequence, created_at, delivered_at";

fn message_from_row(row: SqliteRow) -> Result<OrchestrationMessage> {
    let type_raw: String = row.try_get("type")?;
    let priority_raw: String = row.try_get("priority")?;
    Ok(OrchestrationMessage {
        id: row.try_get("id")?,
        from_handle: row.try_get("from_handle")?,
        to_handle: row.try_get("to_handle")?,
        subject: row.try_get("subject")?,
        body: row.try_get("body")?,
        message_type: OrchestrationMessageType::parse(&type_raw)
            .unwrap_or(OrchestrationMessageType::Status),
        priority: OrchestrationMessagePriority::parse(&priority_raw).unwrap_or_default(),
        thread_id: row.try_get("thread_id")?,
        payload: row.try_get("payload")?,
        read: row.try_get::<i64, _>("read")? != 0,
        sequence: row.try_get("sequence")?,
        created_at: row.try_get("created_at")?,
        delivered_at: row.try_get("delivered_at")?,
    })
}

fn id_placeholders(count: usize) -> String {
    let mut placeholders = "?,".repeat(count);
    placeholders.pop();
    placeholders
}

impl RuntimeStore {
    pub async fn insert_orchestration_message(
        &self,
        message: NewOrchestrationMessage,
    ) -> Result<OrchestrationMessage> {
        validate_new_orchestration_message(&message)?;
        let id = orchestration_id("msg");
        sqlx::query(
            "INSERT INTO orchestrationMessages \
             (id, from_handle, to_handle, subject, body, type, priority, thread_id, payload) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(&message.from_handle)
        .bind(&message.to_handle)
        .bind(&message.subject)
        .bind(&message.body)
        .bind(message.message_type.as_str())
        .bind(message.priority.as_str())
        .bind(&message.thread_id)
        .bind(&message.payload)
        .execute(self.pool())
        .await?;
        self.orchestration_message_by_id(&id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("inserted orchestration message not found"))
    }

    pub async fn orchestration_message_by_id(
        &self,
        id: &str,
    ) -> Result<Option<OrchestrationMessage>> {
        let row = sqlx::query(&format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages WHERE id = ?"
        ))
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(message_from_row).transpose()
    }

    pub async fn unread_orchestration_messages(
        &self,
        to_handle: &str,
        types: Option<&[OrchestrationMessageType]>,
    ) -> Result<Vec<OrchestrationMessage>> {
        let mut sql = format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ? AND read = 0"
        );
        if let Some(types) = types {
            if !types.is_empty() {
                sql.push_str(&format!(" AND type IN ({})", id_placeholders(types.len())));
            }
        }
        sql.push_str(" ORDER BY sequence ASC");
        let mut query = sqlx::query(&sql).bind(to_handle);
        if let Some(types) = types {
            for message_type in types {
                query = query.bind(message_type.as_str());
            }
        }
        let rows = query.fetch_all(self.pool()).await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn unread_orchestration_coordinator_messages(
        &self,
        to_handle: &str,
    ) -> Result<Vec<OrchestrationMessage>> {
        let rows = sqlx::query(&format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ? AND read = 0 AND ( \
               type IN ('worker_done', 'heartbeat', 'escalation') \
               OR ( \
                 type = 'decision_gate' \
                 AND CASE \
                   WHEN payload IS NOT NULL AND json_valid(payload) \
                   THEN COALESCE(json_extract(payload, '$.taskId'), '') != '' \
                   ELSE 0 \
                 END \
               ) \
             ) \
             ORDER BY sequence ASC"
        ))
        .bind(to_handle)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn undelivered_unread_orchestration_messages(
        &self,
        to_handle: &str,
    ) -> Result<Vec<OrchestrationMessage>> {
        let rows = sqlx::query(&format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ? AND read = 0 AND delivered_at IS NULL \
             ORDER BY sequence ASC"
        ))
        .bind(to_handle)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn all_orchestration_messages_for_handle(
        &self,
        to_handle: &str,
        types: Option<&[OrchestrationMessageType]>,
        limit: i64,
    ) -> Result<Vec<OrchestrationMessage>> {
        let mut sql = format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ?"
        );
        if let Some(types) = types {
            if !types.is_empty() {
                sql.push_str(&format!(" AND type IN ({})", id_placeholders(types.len())));
            }
        }
        sql.push_str(" ORDER BY sequence DESC LIMIT ?");
        let mut query = sqlx::query(&sql).bind(to_handle);
        if let Some(types) = types {
            for message_type in types {
                query = query.bind(message_type.as_str());
            }
        }
        let rows = query.bind(limit).fetch_all(self.pool()).await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn orchestration_inbox(&self, limit: i64) -> Result<Vec<OrchestrationMessage>> {
        let rows = sqlx::query(&format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             ORDER BY sequence DESC LIMIT ?"
        ))
        .bind(limit)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn mark_orchestration_messages_read(&self, ids: &[String]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }
        let sql = format!(
            "UPDATE orchestrationMessages SET read = 1 WHERE id IN ({})",
            id_placeholders(ids.len())
        );
        let mut query = sqlx::query(&sql);
        for id in ids {
            query = query.bind(id);
        }
        query.execute(self.pool()).await?;
        Ok(())
    }

    pub async fn mark_orchestration_messages_delivered(&self, ids: &[String]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }
        let sql = format!(
            "UPDATE orchestrationMessages SET delivered_at = datetime('now') WHERE id IN ({})",
            id_placeholders(ids.len())
        );
        let mut query = sqlx::query(&sql);
        for id in ids {
            query = query.bind(id);
        }
        query.execute(self.pool()).await?;
        Ok(())
    }

    /// Replies addressed to `to_handle` in a thread, strictly after `after_sequence`.
    /// Powers the blocking `ask` loop.
    pub async fn orchestration_thread_messages_for(
        &self,
        thread_id: &str,
        to_handle: &str,
        after_sequence: i64,
    ) -> Result<Vec<OrchestrationMessage>> {
        let rows = sqlx::query(&format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE thread_id = ? AND to_handle = ? AND sequence > ? \
             ORDER BY sequence ASC"
        ))
        .bind(thread_id)
        .bind(to_handle)
        .bind(after_sequence)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn reset_orchestration_messages(&self) -> Result<()> {
        sqlx::query("DELETE FROM orchestrationMessages")
            .execute(self.pool())
            .await?;
        Ok(())
    }
}

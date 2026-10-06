use std::sync::atomic::Ordering;

use anyhow::Result;
use chrono::{Duration, Utc};
use sqlx::Row;

use super::inbox_models::*;
use super::{
    NewOrchestrationMessage, OrchestrationMessage, OrchestrationMessageType, RuntimeStore,
};

const INBOX_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS inboxRevision (
        id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL
    )",
    "INSERT OR IGNORE INTO inboxRevision VALUES (1, 0)",
];

// Indexes come after `ensure_column`: an existing database gets the columns
// first, so no index can reference a column that does not exist yet.
const INBOX_INDEXES: &[&str] = &[
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesFromIdx ON orchestrationMessages(from_handle, sequence)",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesReplyToIdx ON orchestrationMessages(reply_to_id)",
];

/// SQLite `datetime('now')` shape, so comparisons with stored timestamps stay
/// lexicographic.
pub(super) fn sqlite_timestamp(at: chrono::DateTime<Utc>) -> String {
    at.format("%Y-%m-%d %H:%M:%S").to_string()
}

impl RuntimeStore {
    pub(super) async fn migrate_inbox(&self) -> Result<()> {
        for statement in INBOX_SCHEMA {
            sqlx::query(*statement).execute(self.pool()).await?;
        }
        self.ensure_column("orchestrationMessages", "reply_to_id", "TEXT")
            .await?;
        self.ensure_column("orchestrationMessages", "external_meta", "TEXT")
            .await?;
        for statement in INBOX_INDEXES {
            sqlx::query(*statement).execute(self.pool()).await?;
        }
        // The revision moves in the same transaction as the row that changed,
        // whichever writer touched it.
        for (operation, row) in [("INSERT", "NEW"), ("UPDATE", "NEW"), ("DELETE", "OLD")] {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "CREATE TRIGGER IF NOT EXISTS inbox_messages_{operation}
                 AFTER {operation} ON orchestrationMessages
                 WHEN substr({row}.from_handle, 1, 4) = 'ext:' OR substr({row}.to_handle, 1, 4) = 'ext:'
                 BEGIN UPDATE inboxRevision SET revision = revision + 1 WHERE id = 1; END"
            )))
            .execute(self.pool())
            .await?;
        }
        Ok(())
    }

    pub async fn inbox_revision(&self) -> Result<i64> {
        let row = sqlx::query("SELECT revision FROM inboxRevision WHERE id = 1")
            .fetch_one(self.pool())
            .await?;
        Ok(row.try_get("revision")?)
    }

    /// Called after actor-owned work settles. Returns the revision only when it
    /// moved since the last call, so repeated reads emit nothing.
    pub async fn take_inbox_change(&self) -> Result<Option<i64>> {
        let revision = self.inbox_revision().await?;
        let previous = self
            .inbox_notification_revision
            .fetch_max(revision, Ordering::Relaxed);
        Ok((revision > previous).then_some(revision))
    }

    /// Expires inbox questions whose deadline passed before delivery and
    /// returns the inboxes that changed, so the host can announce them.
    pub async fn expire_inbox_questions(&self) -> Result<Vec<String>> {
        let inboxes: Vec<String> = sqlx::query(
            "SELECT DISTINCT from_handle FROM orchestrationMessages \
             WHERE substr(from_handle, 1, 4) = 'ext:' AND state = 'queued' \
             AND expires_at IS NOT NULL AND expires_at <= datetime('now')",
        )
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(|row| row.try_get("from_handle"))
        .collect::<std::result::Result<_, _>>()?;
        if !inboxes.is_empty() {
            self.expire_orchestration_messages().await?;
        }
        Ok(inboxes)
    }

    pub async fn pending_inbox_questions_for(&self, recipient: &str) -> Result<i64> {
        self.expire_orchestration_messages().await?;
        let row = sqlx::query(
            "SELECT COUNT(*) AS pending FROM orchestrationMessages \
             WHERE to_handle = ? AND substr(from_handle, 1, 4) = 'ext:' \
             AND state = 'queued' AND delivered_at IS NULL AND read = 0",
        )
        .bind(recipient)
        .fetch_one(self.pool())
        .await?;
        Ok(row.try_get("pending")?)
    }

    pub async fn insert_inbox_question(
        &self,
        question: NewInboxQuestion,
    ) -> Result<OrchestrationMessage> {
        validate_inbox_address(&question.inbox)?;
        if is_external_inbox(&question.recipient) || question.recipient.starts_with('@') {
            anyhow::bail!("inbox_invalid_recipient: ask a terminal, not a group or another inbox");
        }
        let expires_in = question
            .expires_in_seconds
            .unwrap_or(INBOX_DEFAULT_EXPIRY_SECONDS);
        if !(INBOX_MIN_EXPIRY_SECONDS..=INBOX_MAX_EXPIRY_SECONDS).contains(&expires_in) {
            anyhow::bail!(
                "inbox_invalid_expiry: expiry must be between {INBOX_MIN_EXPIRY_SECONDS} and {INBOX_MAX_EXPIRY_SECONDS} seconds"
            );
        }
        let external_meta = question.external_meta.to_string();
        if external_meta.len() > INBOX_EXTERNAL_META_MAX_BYTES {
            anyhow::bail!("message_too_large: inbox metadata exceeds {INBOX_EXTERNAL_META_MAX_BYTES} UTF-8 bytes");
        }
        if let Some(thread_id) = question.thread_id.as_deref() {
            let root = self.orchestration_message_by_id(thread_id).await?;
            let same_thread = root.as_ref().is_some_and(|root| {
                root.thread_id.is_none()
                    && root.from_handle == question.inbox
                    && root.to_handle == question.recipient
            });
            if !same_thread {
                anyhow::bail!(
                    "inbox_thread_mismatch: a follow-up must continue a question this inbox sent to the same recipient"
                );
            }
        }
        if self
            .pending_inbox_questions_for(&question.recipient)
            .await?
            >= INBOX_PENDING_LIMIT
        {
            anyhow::bail!(
                "inbox_pending_limit: the recipient already has {INBOX_PENDING_LIMIT} undelivered questions"
            );
        }
        let expires_at = sqlite_timestamp(Utc::now() + Duration::seconds(expires_in));
        self.insert_orchestration_message(NewOrchestrationMessage {
            from_handle: question.inbox,
            to_handle: question.recipient,
            subject: question.subject,
            body: question.body,
            message_type: OrchestrationMessageType::DecisionGate,
            priority: question.priority,
            thread_id: question.thread_id,
            payload: question.payload,
            run_id: None,
            workspace_id: question.workspace_id,
            task_id: None,
            dispatch_id: None,
            expires_at: Some(expires_at),
            reply_to_id: None,
            external_meta: Some(external_meta),
        })
        .await
    }

    /// Cancels a question that was never pasted, read, or answered.
    pub async fn cancel_inbox_question(
        &self,
        id: &str,
        cancellation: serde_json::Value,
    ) -> Result<OrchestrationMessage> {
        self.expire_orchestration_messages().await?;
        let result = sqlx::query(
            "UPDATE orchestrationMessages SET state = 'obsolete', obsolete_at = datetime('now'), \
             external_meta = json_set(COALESCE(external_meta, '{}'), '$.cancellation', json(?)) \
             WHERE id = ? AND substr(from_handle, 1, 4) = 'ext:' AND state = 'queued' \
             AND delivered_at IS NULL AND read = 0",
        )
        .bind(cancellation.to_string())
        .bind(id)
        .execute(self.pool())
        .await?;
        let message = self.orchestration_message_by_id(id).await?;
        match message {
            Some(message) if result.rows_affected() == 1 => Ok(message),
            Some(message) if is_external_inbox(&message.from_handle) => anyhow::bail!(
                "inbox_not_cancellable: only a question that has not reached the agent can be cancelled"
            ),
            _ => anyhow::bail!("inbox_question_not_found: {id}"),
        }
    }

    /// Marks messages addressed to an inbox as read. Agent rows are never
    /// touched here, because their `read` flag means the agent consumed them.
    pub async fn mark_inbox_messages_read(&self, ids: &[String]) -> Result<u64> {
        if ids.is_empty() {
            return Ok(0);
        }
        let sql = format!(
            "UPDATE orchestrationMessages SET read = 1, \
             state = CASE WHEN state = 'obsolete' THEN state ELSE 'read' END \
             WHERE read = 0 AND substr(to_handle, 1, 4) = 'ext:' AND id IN ({})",
            placeholders(ids.len())
        );
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        for id in ids {
            query = query.bind(id);
        }
        Ok(query.execute(self.pool()).await?.rows_affected())
    }
}

pub(super) fn placeholders(count: usize) -> String {
    let mut marks = "?,".repeat(count);
    marks.pop();
    marks
}

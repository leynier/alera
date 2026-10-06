use std::sync::atomic::Ordering;

use anyhow::Result;
use chrono::{Duration, Utc};
use serde::Serialize;
use sqlx::Row;

use super::inbox_models::INBOX_HISTORY_SECONDS;
use super::inbox_store::{placeholders, sqlite_timestamp};
use super::orchestration_message_store::{message_from_row, MESSAGE_COLUMNS};
use super::{OrchestrationMessage, RuntimeStore};

/// Messages agents exchange as conversation. Lifecycle reports, dispatches and
/// escalations are task control and stay out of this view and its retention.
const CONVERSATION_ROW: &str = "substr(from_handle, 1, 4) != 'ext:' \
     AND substr(to_handle, 1, 4) != 'ext:' \
     AND type IN ('status', 'handoff', 'merge_ready', 'decision_gate')";
const DELETE_BATCH: usize = 400;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConversationThread {
    pub thread_id: String,
    pub subject: String,
    pub started_by: String,
    pub participants: Vec<String>,
    pub workspace_id: Option<String>,
    pub created_at: String,
    pub last_activity_at: String,
    pub last_sequence: i64,
    pub message_count: i64,
    /// A group send has no stored root; its thread id is generated.
    pub group: bool,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConversationPage {
    pub items: Vec<ConversationThread>,
    pub next_before: Option<i64>,
}

#[derive(Debug, Clone, Default)]
pub struct ConversationFilter {
    pub workspace_id: Option<String>,
    pub participant: Option<String>,
    pub before_sequence: Option<i64>,
    pub limit: i64,
}

impl RuntimeStore {
    pub(super) async fn migrate_conversations(&self) -> Result<()> {
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS conversationRevision (
                id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL
            )",
        )
        .execute(self.pool())
        .await?;
        sqlx::query("INSERT OR IGNORE INTO conversationRevision VALUES (1, 0)")
            .execute(self.pool())
            .await?;
        for (operation, row) in [("INSERT", "NEW"), ("UPDATE", "NEW"), ("DELETE", "OLD")] {
            let condition = CONVERSATION_ROW
                .replace("from_handle", &format!("{row}.from_handle"))
                .replace("to_handle", &format!("{row}.to_handle"))
                .replace("type IN", &format!("{row}.type IN"));
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "CREATE TRIGGER IF NOT EXISTS conversation_messages_{operation}
                 AFTER {operation} ON orchestrationMessages WHEN {condition}
                 BEGIN UPDATE conversationRevision SET revision = revision + 1 WHERE id = 1; END"
            )))
            .execute(self.pool())
            .await?;
        }
        Ok(())
    }

    pub async fn conversation_revision(&self) -> Result<i64> {
        let row = sqlx::query("SELECT revision FROM conversationRevision WHERE id = 1")
            .fetch_one(self.pool())
            .await?;
        Ok(row.try_get("revision")?)
    }

    pub async fn take_conversation_change(&self) -> Result<Option<i64>> {
        let revision = self.conversation_revision().await?;
        let previous = self
            .conversation_notification_revision
            .fetch_max(revision, Ordering::Relaxed);
        Ok((revision > previous).then_some(revision))
    }

    /// Threads between terminals, most recent activity first. A message
    /// without a thread is its own thread.
    pub async fn conversation_threads(
        &self,
        filter: ConversationFilter,
    ) -> Result<ConversationPage> {
        let limit = filter.limit.clamp(1, 200);
        // Filters choose threads; order and cursor always use every message
        // of the thread, so a page matches what the summary shows.
        let mut sql = format!(
            "SELECT COALESCE(thread_id, id) AS tid, MAX(sequence) AS last_sequence \
             FROM orchestrationMessages WHERE {CONVERSATION_ROW} GROUP BY tid HAVING 1"
        );
        if filter.workspace_id.is_some() {
            sql.push_str(" AND SUM(workspace_id = ?) > 0");
        }
        if filter.participant.is_some() {
            sql.push_str(" AND SUM(from_handle = ? OR to_handle = ?) > 0");
        }
        if filter.before_sequence.is_some() {
            sql.push_str(" AND MAX(sequence) < ?");
        }
        sql.push_str(" ORDER BY last_sequence DESC LIMIT ?");
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        if let Some(workspace_id) = &filter.workspace_id {
            query = query.bind(workspace_id);
        }
        if let Some(participant) = &filter.participant {
            query = query.bind(participant).bind(participant);
        }
        if let Some(before) = filter.before_sequence {
            query = query.bind(before);
        }
        let rows = query.bind(limit).fetch_all(self.pool()).await?;
        let next_before = if rows.len() as i64 == limit {
            rows.last()
                .map(|row| row.try_get::<i64, _>("last_sequence"))
                .transpose()?
        } else {
            None
        };
        let mut items = Vec::with_capacity(rows.len());
        for row in rows {
            let thread_id: String = row.try_get("tid")?;
            let messages = self.conversation_thread(&thread_id).await?;
            if let Some(thread) = summarize(&thread_id, &messages) {
                items.push(thread);
            }
        }
        Ok(ConversationPage { items, next_before })
    }

    pub async fn conversation_thread(&self, thread_id: &str) -> Result<Vec<OrchestrationMessage>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE (id = ?1 OR thread_id = ?1) AND {CONVERSATION_ROW} ORDER BY sequence ASC"
        )))
        .bind(thread_id)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    /// Deletes agent conversations idle past the history window. A thread is
    /// kept whole while any of its messages is still queued for delivery or
    /// belongs to a task or dispatch that is not finished.
    pub async fn prune_conversation_history(&self) -> Result<u64> {
        let cutoff = sqlite_timestamp(Utc::now() - Duration::seconds(INBOX_HISTORY_SECONDS));
        let threads: Vec<String> = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT COALESCE(thread_id, id) AS tid FROM orchestrationMessages \
             WHERE {CONVERSATION_ROW} GROUP BY tid HAVING MAX(created_at) < ?1 \
             AND SUM(state = 'queued') = 0 \
             AND SUM(CASE WHEN dispatch_id IS NOT NULL AND EXISTS (SELECT 1 FROM orchestrationDispatchContexts d \
                   WHERE d.id = orchestrationMessages.dispatch_id \
                   AND d.status IN ('pending','dispatched','awaiting_acceptance','stalled')) THEN 1 ELSE 0 END) = 0 \
             AND SUM(CASE WHEN task_id IS NOT NULL AND EXISTS (SELECT 1 FROM orchestrationTasks t \
                   WHERE t.id = orchestrationMessages.task_id \
                   AND t.status IN ('pending','ready','dispatched','blocked','stalled')) THEN 1 ELSE 0 END) = 0"
        )))
        .bind(&cutoff)
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(|row| row.try_get("tid"))
        .collect::<std::result::Result<_, _>>()?;
        let mut tx = self.pool().begin().await?;
        let mut deleted = 0;
        for chunk in threads.chunks(DELETE_BATCH) {
            let marks = placeholders(chunk.len());
            let sql = format!(
                "DELETE FROM orchestrationMessages WHERE {CONVERSATION_ROW} \
                 AND (id IN ({marks}) OR thread_id IN ({marks}))"
            );
            let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
            for _ in 0..2 {
                for id in chunk {
                    query = query.bind(id);
                }
            }
            deleted += query.execute(&mut *tx).await?.rows_affected();
        }
        tx.commit().await?;
        Ok(deleted)
    }
}

fn summarize(thread_id: &str, messages: &[OrchestrationMessage]) -> Option<ConversationThread> {
    let first = messages.first()?;
    let last = messages.last()?;
    let mut participants: Vec<String> = Vec::new();
    for message in messages {
        for handle in [&message.from_handle, &message.to_handle] {
            if !participants.contains(handle) {
                participants.push(handle.clone());
            }
        }
    }
    Some(ConversationThread {
        thread_id: thread_id.to_string(),
        subject: first.subject.clone(),
        started_by: first.from_handle.clone(),
        participants,
        workspace_id: first.workspace_id.clone(),
        created_at: first.created_at.clone(),
        last_activity_at: messages
            .iter()
            .map(|message| message.created_at.as_str())
            .max()
            .unwrap_or(first.created_at.as_str())
            .to_string(),
        last_sequence: last.sequence,
        message_count: messages.len() as i64,
        group: !messages.iter().any(|message| message.id == thread_id),
    })
}

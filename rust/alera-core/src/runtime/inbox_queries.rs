use std::collections::HashSet;

use anyhow::Result;
use sqlx::Row;

use super::inbox_models::*;
use super::orchestration_message_store::{message_from_row, MESSAGE_COLUMNS};
use super::{OrchestrationMessage, RuntimeStore};

const INBOX_THREAD_SCAN_BATCH: i64 = 200;

impl RuntimeStore {
    pub async fn inbox_thread(&self, thread_id: &str) -> Result<Option<InboxThreadDetail>> {
        self.expire_orchestration_messages().await?;
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE id = ?1 OR thread_id = ?1 ORDER BY sequence ASC"
        )))
        .bind(thread_id)
        .fetch_all(self.pool())
        .await?;
        let messages = rows
            .into_iter()
            .map(message_from_row)
            .collect::<Result<Vec<_>>>()?;
        Ok(build_thread(thread_id, messages))
    }

    /// Threads by their latest activity, newest first. The status filter is
    /// applied before the limit, so a page is full whenever enough threads
    /// match; `next_before` continues after the last returned thread.
    pub async fn inbox_threads(&self, filter: InboxThreadFilter) -> Result<InboxThreadPage> {
        self.expire_orchestration_messages().await?;
        let limit = filter.limit.clamp(1, 200);
        let mut sql = String::from(
            "SELECT id, last_sequence FROM (SELECT r.id AS id, \
               (SELECT MAX(m.sequence) FROM orchestrationMessages m \
                 WHERE m.id = r.id OR m.thread_id = r.id) AS last_sequence \
             FROM orchestrationMessages r \
             WHERE substr(r.from_handle, 1, 4) = 'ext:' AND r.thread_id IS NULL",
        );
        if filter.inbox.is_some() {
            sql.push_str(" AND r.from_handle = ?");
        }
        if filter.workspace_id.is_some() {
            sql.push_str(" AND r.workspace_id = ?");
        }
        if filter.origin_client_id.is_some() {
            sql.push_str(" AND json_extract(r.external_meta, '$.origin.clientId') = ?");
        }
        sql.push_str(") WHERE last_sequence < ? ORDER BY last_sequence DESC LIMIT ?");
        let mut items = Vec::new();
        let mut before = filter.before_sequence.unwrap_or(i64::MAX);
        loop {
            let mut query = sqlx::query(sqlx::AssertSqlSafe(sql.clone()));
            if let Some(inbox) = &filter.inbox {
                query = query.bind(inbox);
            }
            if let Some(workspace_id) = &filter.workspace_id {
                query = query.bind(workspace_id);
            }
            if let Some(client_id) = &filter.origin_client_id {
                query = query.bind(client_id);
            }
            let rows = query
                .bind(before)
                .bind(INBOX_THREAD_SCAN_BATCH)
                .fetch_all(self.pool())
                .await?;
            let exhausted = (rows.len() as i64) < INBOX_THREAD_SCAN_BATCH;
            for row in rows {
                before = row.try_get("last_sequence")?;
                let id: String = row.try_get("id")?;
                let Some(detail) = self.inbox_thread(&id).await? else {
                    continue;
                };
                if filter
                    .status
                    .is_none_or(|status| status == detail.thread.status)
                {
                    items.push(detail.thread);
                    if items.len() as i64 == limit {
                        return Ok(InboxThreadPage {
                            items,
                            next_before: Some(before),
                        });
                    }
                }
            }
            if exhausted {
                return Ok(InboxThreadPage {
                    items,
                    next_before: None,
                });
            }
        }
    }

    /// The question an inbox already asked with this retry key on behalf of
    /// the same origin client, so a retried ask returns it instead of asking
    /// twice. Keys live in `external_meta.requestKey`.
    pub async fn inbox_question_by_request_key(
        &self,
        inbox: &str,
        request_key: &str,
        origin_client_id: Option<&str>,
    ) -> Result<Option<OrchestrationMessage>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE from_handle = ? AND json_extract(external_meta, '$.requestKey') = ? \
             AND json_extract(external_meta, '$.origin.clientId') IS ? \
             ORDER BY sequence DESC LIMIT 1"
        )))
        .bind(inbox)
        .bind(request_key)
        .bind(origin_client_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(message_from_row).transpose()
    }

    /// Messages addressed to `inbox` after `after_sequence`, oldest first.
    pub async fn inbox_messages_after(
        &self,
        inbox: &str,
        after_sequence: i64,
        limit: i64,
    ) -> Result<Vec<OrchestrationMessage>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ? AND sequence > ? ORDER BY sequence ASC LIMIT ?"
        )))
        .bind(inbox)
        .bind(after_sequence)
        .bind(limit.clamp(1, 200))
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn inbox_summary(&self) -> Result<Vec<InboxSummaryEntry>> {
        self.expire_orchestration_messages().await?;
        let rows = sqlx::query(
            "WITH inboxes AS ( \
               SELECT from_handle AS inbox FROM orchestrationMessages WHERE substr(from_handle, 1, 4) = 'ext:' \
               UNION SELECT to_handle FROM orchestrationMessages WHERE substr(to_handle, 1, 4) = 'ext:' \
             ) \
             SELECT i.inbox AS inbox, \
               (SELECT COUNT(*) FROM orchestrationMessages m \
                 WHERE m.from_handle = i.inbox AND m.thread_id IS NULL) AS thread_count, \
               (SELECT COUNT(*) FROM orchestrationMessages m \
                 WHERE m.from_handle = i.inbox AND m.state = 'queued' \
                 AND m.delivered_at IS NULL AND m.read = 0 \
                 AND NOT EXISTS (SELECT 1 FROM orchestrationMessages r \
                   WHERE r.reply_to_id = m.id AND r.from_handle = m.to_handle)) AS pending_count, \
               (SELECT COUNT(*) FROM orchestrationMessages q \
                 WHERE q.from_handle = i.inbox AND q.state NOT IN ('expired', 'obsolete') \
                 AND (q.delivered_at IS NOT NULL OR q.read = 1) \
                 AND NOT EXISTS (SELECT 1 FROM orchestrationMessages r \
                   WHERE r.reply_to_id = q.id AND r.from_handle = q.to_handle)) AS awaiting_reply_count, \
               (SELECT COUNT(*) FROM orchestrationMessages m \
                 WHERE m.to_handle = i.inbox AND m.read = 0) AS unread_reply_count, \
               (SELECT MAX(created_at) FROM orchestrationMessages m \
                 WHERE m.from_handle = i.inbox OR m.to_handle = i.inbox) AS last_activity_at \
             FROM inboxes i ORDER BY last_activity_at DESC, inbox ASC",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter()
            .map(|row| {
                Ok(InboxSummaryEntry {
                    inbox: row.try_get("inbox")?,
                    thread_count: row.try_get("thread_count")?,
                    pending_count: row.try_get("pending_count")?,
                    awaiting_reply_count: row.try_get("awaiting_reply_count")?,
                    unread_reply_count: row.try_get("unread_reply_count")?,
                    last_activity_at: row.try_get("last_activity_at")?,
                })
            })
            .collect()
    }
}

fn build_thread(thread_id: &str, messages: Vec<OrchestrationMessage>) -> Option<InboxThreadDetail> {
    let root = messages
        .iter()
        .find(|message| message.id == thread_id && message.thread_id.is_none())?
        .clone();
    if !is_external_inbox(&root.from_handle) {
        return None;
    }
    let inbox = root.from_handle.clone();
    let recipient = root.to_handle.clone();
    let answered: HashSet<&str> = messages
        .iter()
        .filter(|message| message.to_handle == inbox && message.from_handle == recipient)
        .filter_map(|message| message.reply_to_id.as_deref())
        .collect();
    let question_ids: HashSet<&str> = messages
        .iter()
        .filter(|message| message.from_handle == inbox)
        .map(|message| message.id.as_str())
        .collect();
    let entries: Vec<InboxMessage> = messages
        .iter()
        .map(|message| {
            if message.from_handle == inbox {
                InboxMessage {
                    kind: InboxMessageKind::Question,
                    status: Some(question_status(
                        message,
                        answered.contains(message.id.as_str()),
                    )),
                    message: message.clone(),
                }
            } else {
                let correlated = message
                    .reply_to_id
                    .as_deref()
                    .is_some_and(|id| question_ids.contains(id))
                    && message.from_handle == recipient;
                InboxMessage {
                    kind: if correlated {
                        InboxMessageKind::Reply
                    } else {
                        InboxMessageKind::Message
                    },
                    status: None,
                    message: message.clone(),
                }
            }
        })
        .collect();
    let status = entries
        .iter()
        .rev()
        .find_map(|entry| entry.status)
        .unwrap_or(InboxQuestionStatus::Pending);
    let incoming = entries
        .iter()
        .filter(|entry| entry.message.to_handle == inbox);
    let reply_count = incoming.clone().count() as i64;
    let unread_reply_count = incoming.filter(|entry| !entry.message.read).count() as i64;
    let last = messages.last()?;
    let meta = root.external_meta.clone();
    Some(InboxThreadDetail {
        thread: InboxThread {
            thread_id: root.id.clone(),
            inbox,
            recipient,
            workspace_id: root.workspace_id.clone(),
            subject: root.subject.clone(),
            created_at: root.created_at.clone(),
            last_activity_at: messages
                .iter()
                .map(|message| message.created_at.as_str())
                .max()
                .unwrap_or(root.created_at.as_str())
                .to_string(),
            last_sequence: last.sequence,
            status,
            question_count: question_ids.len() as i64,
            reply_count,
            unread_reply_count,
            origin: meta.as_ref().and_then(|meta| meta.get("origin").cloned()),
            target: meta.as_ref().and_then(|meta| meta.get("target").cloned()),
        },
        messages: entries,
    })
}

/// Precedence: cancelled, answered, expired, delivered, received, pending.
pub fn question_status(question: &OrchestrationMessage, answered: bool) -> InboxQuestionStatus {
    let cancelled = question.state == "obsolete";
    if cancelled {
        InboxQuestionStatus::Cancelled
    } else if answered {
        InboxQuestionStatus::Answered
    } else if question.state == "expired" && question.delivered_at.is_none() {
        InboxQuestionStatus::Expired
    } else if question.delivered_at.is_some() {
        InboxQuestionStatus::Delivered
    } else if question.read {
        InboxQuestionStatus::Received
    } else {
        InboxQuestionStatus::Pending
    }
}

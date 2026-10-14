//! Shared host read cursors and bounded, indexed child task summaries.

#[cfg(test)]
#[path = "agent_chat_attention_tests.rs"]
mod tests;

use anyhow::Result;
use serde_json::json;
use sqlx::{Row, SqliteConnection};

use super::agent_chat_receipts::{check_receipt_in, insert_receipt_in, require_receipt};
use super::agent_chat_store::require_session_row_in;
use super::*;

async fn mark_read_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    cursor: i64,
) -> Result<i64> {
    let row = require_session_row_in(connection, chat_id).await?;
    if cursor < 0 || cursor > row.cursor {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "read cursor is outside committed history".into()
        ));
    }
    sqlx::query("INSERT INTO agentChatReadCursors (chatId, cursor) VALUES (?, ?) \
        ON CONFLICT(chatId) DO UPDATE SET cursor = excluded.cursor WHERE excluded.cursor > agentChatReadCursors.cursor")
        .bind(chat_id).bind(cursor).execute(&mut *connection).await?;
    Ok(
        sqlx::query_scalar("SELECT cursor FROM agentChatReadCursors WHERE chatId = ?")
            .bind(chat_id)
            .fetch_one(&mut *connection)
            .await?,
    )
}

impl RuntimeStore {
    /// Monotonic and clamped to the committed cursor. An ahead-of-host cursor
    /// is refused so a stale client cannot hide future completion events.
    pub async fn mark_agent_chat_read(&self, chat_id: &str, cursor: i64) -> Result<i64> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let stored = mark_read_in(&mut tx, chat_id, cursor).await?;
        tx.commit().await?;
        Ok(stored)
    }

    /// Cursor and exact request response are persisted together, without
    /// advancing the chat journal or snapshot cursor.
    pub async fn mark_agent_chat_read_with_receipt(
        &self,
        chat_id: &str,
        cursor: i64,
        receipt: &AgentChatReceipt,
    ) -> Result<AgentChatReadOutcome> {
        require_receipt(receipt)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        match check_receipt_in(
            &mut tx,
            &receipt.caller_scope,
            &receipt.request_id,
            &receipt.digest,
        )
        .await?
        {
            AgentChatReceiptCheck::Replay(value) => {
                tx.commit().await?;
                return Ok(AgentChatReadOutcome::Replay(value));
            }
            AgentChatReceiptCheck::Conflict => {
                tx.commit().await?;
                return Ok(AgentChatReadOutcome::ReceiptConflict);
            }
            AgentChatReceiptCheck::New => {}
        }
        let stored = mark_read_in(&mut tx, chat_id, cursor).await?;
        let response = json!({"cursor": stored, "readCursor": stored});
        let saved = AgentChatReceipt {
            receipt: response.clone(),
            ..receipt.clone()
        };
        insert_receipt_in(&mut tx, Some(chat_id), None, &saved).await?;
        tx.commit().await?;
        Ok(AgentChatReadOutcome::Applied(response))
    }

    /// Reads no transcript bodies. Unread describes a new settled response,
    /// rather than drafts, renames, provider picks, or a person's own message.
    pub async fn agent_chat_attention(&self, chat_id: &str) -> Result<AgentChatAttention> {
        let mut tx = self.pool().begin().await?;
        let row = require_session_row_in(&mut tx, chat_id).await?;
        let read_cursor: i64 =
            sqlx::query_scalar("SELECT cursor FROM agentChatReadCursors WHERE chatId = ?")
                .bind(chat_id)
                .fetch_optional(&mut *tx)
                .await?
                .unwrap_or(0);
        let unread: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM agentChatTurns WHERE chatId = ?1 \
             AND updatedCursor > ?2 AND status IN ('completed', 'failed', 'interrupted', 'cancelled'))",
        ).bind(chat_id).bind(read_cursor).fetch_one(&mut *tx).await?;
        let children = sqlx::query(
            "SELECT COALESCE(SUM(status IN ('preparing', 'running', 'needs_input', 'cancel_requested')), 0) AS openCount, \
             COALESCE(MAX(status = 'needs_input'), 0) AS needsInput, \
             COALESCE(MAX(status IN ('failed', 'interrupted')), 0) AS failed \
             FROM chatOrchestrationTasks WHERE parentChatId = ?",
        ).bind(chat_id).fetch_one(&mut *tx).await?;
        let parent_chat_id: Option<String> = sqlx::query_scalar(
            "SELECT parentChatId FROM chatOrchestrationTasks \
             WHERE childChatId = ? AND kind = 'delegate' AND parentChatId IS NOT NULL \
             AND parentChatId <> childChatId ORDER BY sequence LIMIT 1",
        )
        .bind(chat_id)
        .fetch_optional(&mut *tx)
        .await?;
        let result = AgentChatAttention {
            chat_id: chat_id.into(),
            cursor: row.cursor,
            read_cursor,
            unread,
            open_child_task_count: children.try_get("openCount")?,
            child_needs_input: children.try_get::<i64, _>("needsInput")? != 0,
            child_failed: children.try_get::<i64, _>("failed")? != 0,
            parent_chat_id,
        };
        tx.commit().await?;
        Ok(result)
    }
}

//! Safe deletion and close receipts that outlive a discarded chat.

#[cfg(test)]
#[path = "agent_chat_deletion_tests.rs"]
mod tests;

use anyhow::Result;
use chrono::Utc;
use serde_json::{json, Value};
use sqlx::SqliteConnection;

use super::agent_chat_receipts::{check_receipt_in, insert_receipt_in, require_receipt};
use super::agent_chat_store::{require_session_row_in, SessionRow};
use super::agent_chat_validation::parse_header;
use super::*;

async fn receipt_in(
    connection: &mut SqliteConnection,
    receipt: Option<&AgentChatReceipt>,
) -> Result<AgentChatReceiptCheck> {
    let Some(receipt) = receipt else {
        return Ok(AgentChatReceiptCheck::New);
    };
    require_receipt(receipt)?;
    check_receipt_in(
        connection,
        &receipt.caller_scope,
        &receipt.request_id,
        &receipt.digest,
    )
    .await
}

async fn active_task_in(connection: &mut SqliteConnection, chat_id: &str) -> Result<bool> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM chatOrchestrationTasks \
         WHERE (parentChatId = ?1 OR childChatId = ?1 OR rootChatId = ?1) \
         AND status IN ('preparing', 'running', 'needs_input', 'cancel_requested'))",
    )
    .bind(chat_id)
    .fetch_one(&mut *connection)
    .await?)
}

async fn never_sent_in(connection: &mut SqliteConnection, row: &SessionRow) -> Result<bool> {
    let header = parse_header(&row.snapshot_json)?;
    if row.archived
        || row.native_thread_id.is_some()
        || header.session.active_turn_id.is_some()
        || !header.pending_requests.is_empty()
        || matches!(
            header.session.status,
            AgentChatSessionStatus::Starting
                | AgentChatSessionStatus::Running
                | AgentChatSessionStatus::Waiting
        )
        || ["queue", "queuedMessages"].iter().any(|key| {
            header
                .extra
                .get(*key)
                .and_then(Value::as_array)
                .is_some_and(|queue| !queue.is_empty())
        })
    {
        return Ok(false);
    }
    let history: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM agentChatItems WHERE chatId = ?1) \
         OR EXISTS(SELECT 1 FROM agentChatTurns WHERE chatId = ?1) \
         OR EXISTS(SELECT 1 FROM agentChatNativeIds WHERE chatId = ?1)",
    )
    .bind(&row.chat_id)
    .fetch_one(&mut *connection)
    .await?;
    Ok(!history && !active_task_in(connection, &row.chat_id).await?)
}

async fn remove_tab_in(connection: &mut SqliteConnection, row: &SessionRow) -> Result<()> {
    super::agent_chat_native_operations::require_no_native_operation_in(connection, &row.chat_id)
        .await?;
    let removed = sqlx::query("DELETE FROM workspaceTabs WHERE id = ? AND kind = 'agentChat'")
        .bind(&row.tab_id)
        .execute(&mut *connection)
        .await?;
    if removed.rows_affected() != 0 {
        sqlx::query("DELETE FROM agentProfileLaunchReceipts WHERE tabId = ?")
            .bind(&row.tab_id)
            .execute(&mut *connection)
            .await?;
        super::automation_binding_store::release_bound_tabs_for_tab_in(
            connection,
            &row.tab_id,
            "tabClosed",
        )
        .await?;
    }
    Ok(())
}

async fn save_detached_receipt_in(
    connection: &mut SqliteConnection,
    receipt: Option<&AgentChatReceipt>,
    response: Value,
) -> Result<()> {
    if let Some(receipt) = receipt {
        let saved = AgentChatReceipt {
            receipt: response,
            ..receipt.clone()
        };
        insert_receipt_in(connection, None, None, &saved).await?;
    }
    Ok(())
}

async fn delete_session_in(connection: &mut SqliteConnection, chat_id: &str) -> Result<()> {
    super::agent_chat_native_operations::require_no_native_operation_in(connection, chat_id)
        .await?;
    // Original create/send retries must not resurrect a deleted chat.
    sqlx::query("UPDATE agentChatReceipts SET chatId = NULL WHERE chatId = ?")
        .bind(chat_id)
        .execute(&mut *connection)
        .await?;
    sqlx::query("UPDATE chatOrchestrationCredentials SET revokedAt = ?, revokeReason = 'chatDeleted' WHERE chatId = ? AND revokedAt IS NULL")
        .bind(format_timestamp(Utc::now())).bind(chat_id).execute(&mut *connection).await?;
    sqlx::query("DELETE FROM agentChatSessions WHERE chatId = ?")
        .bind(chat_id)
        .execute(&mut *connection)
        .await?;
    Ok(())
}

impl RuntimeStore {
    /// A stale cursor or any admitted activity refuses discard. The actor can
    /// then archive; a concurrent send cannot lose a successfully stored item.
    pub async fn discard_agent_chat_if_never_sent(
        &self,
        chat_id: &str,
        expected_cursor: i64,
        receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatDeleteOutcome> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        match receipt_in(&mut tx, receipt).await? {
            AgentChatReceiptCheck::Replay(value) => {
                tx.commit().await?;
                return Ok(AgentChatDeleteOutcome::Replay(value));
            }
            AgentChatReceiptCheck::Conflict => {
                tx.commit().await?;
                return Ok(AgentChatDeleteOutcome::ReceiptConflict);
            }
            AgentChatReceiptCheck::New => {}
        }
        let row = require_session_row_in(&mut tx, chat_id).await?;
        if row.cursor != expected_cursor || !never_sent_in(&mut tx, &row).await? {
            tx.commit().await?;
            return Ok(AgentChatDeleteOutcome::NotNeverSent);
        }
        remove_tab_in(&mut tx, &row).await?;
        delete_session_in(&mut tx, chat_id).await?;
        save_detached_receipt_in(
            &mut tx,
            receipt,
            json!({
                "chatId": chat_id, "tabId": row.tab_id, "archived": false, "discarded": true,
            }),
        )
        .await?;
        tx.commit().await?;
        Ok(AgentChatDeleteOutcome::Deleted)
    }

    /// A complete close decision is receipt-backed in a single actor/store step.
    pub async fn close_agent_chat_with_receipt(
        &self,
        chat_id: &str,
        receipt: &AgentChatReceipt,
    ) -> Result<AgentChatCloseOutcome> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        match receipt_in(&mut tx, Some(receipt)).await? {
            AgentChatReceiptCheck::Replay(value) => {
                tx.commit().await?;
                return Ok(AgentChatCloseOutcome::Replay(value));
            }
            AgentChatReceiptCheck::Conflict => {
                tx.commit().await?;
                return Ok(AgentChatCloseOutcome::ReceiptConflict);
            }
            AgentChatReceiptCheck::New => {}
        }
        let row = require_session_row_in(&mut tx, chat_id).await?;
        let discarded = never_sent_in(&mut tx, &row).await?;
        remove_tab_in(&mut tx, &row).await?;
        if discarded {
            delete_session_in(&mut tx, chat_id).await?;
        } else {
            let now = format_timestamp(Utc::now());
            sqlx::query("UPDATE agentChatSessions SET archived = 1, archivedAt = COALESCE(archivedAt, ?), updatedAt = ? WHERE chatId = ?")
                .bind(&now).bind(&now).bind(chat_id).execute(&mut *tx).await?;
        }
        save_detached_receipt_in(&mut tx, Some(receipt), json!({
            "chatId": chat_id, "tabId": row.tab_id, "archived": !discarded, "discarded": discarded,
        })).await?;
        tx.commit().await?;
        Ok(AgentChatCloseOutcome::Closed {
            chat_id: chat_id.into(),
            tab_id: row.tab_id,
            archived: !discarded,
            discarded,
        })
    }

    /// Settled task lineage survives deletion; active task linkage blocks it.
    pub async fn delete_archived_agent_chat(
        &self,
        chat_id: &str,
        expected_cursor: i64,
        receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatArchivedDeleteOutcome> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        match receipt_in(&mut tx, receipt).await? {
            AgentChatReceiptCheck::Replay(value) => {
                tx.commit().await?;
                return Ok(AgentChatArchivedDeleteOutcome::Replay(value));
            }
            AgentChatReceiptCheck::Conflict => {
                tx.commit().await?;
                return Ok(AgentChatArchivedDeleteOutcome::ReceiptConflict);
            }
            AgentChatReceiptCheck::New => {}
        }
        let row = require_session_row_in(&mut tx, chat_id).await?;
        let refused = if row.cursor != expected_cursor {
            Some(AgentChatArchivedDeleteOutcome::CursorConflict {
                current: row.cursor,
            })
        } else if !row.archived {
            Some(AgentChatArchivedDeleteOutcome::NotArchived)
        } else if active_task_in(&mut tx, chat_id).await? {
            Some(AgentChatArchivedDeleteOutcome::ReferencedByTasks)
        } else {
            None
        };
        if let Some(outcome) = refused {
            tx.commit().await?;
            return Ok(outcome);
        }
        delete_session_in(&mut tx, chat_id).await?;
        save_detached_receipt_in(
            &mut tx,
            receipt,
            json!({"chatId": chat_id, "deleted": true}),
        )
        .await?;
        tx.commit().await?;
        Ok(AgentChatArchivedDeleteOutcome::Deleted)
    }
}

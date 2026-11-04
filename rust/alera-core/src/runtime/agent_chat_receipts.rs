//! Command receipts: an exact retry replays the stored response, the same
//! request id with a different payload is a conflict, and a receipt written
//! with a mutation commits in the same transaction as that mutation.

use anyhow::Result;
use chrono::{Duration, Utc};
use sqlx::{Row, SqliteConnection};

use super::agent_chat_models::*;
use super::agent_chat_validation::require_id;
use super::{format_timestamp, RuntimeStore};

pub(super) fn require_receipt(receipt: &AgentChatReceipt) -> Result<()> {
    require_id("callerScope", &receipt.caller_scope)?;
    require_id("requestId", &receipt.request_id)?;
    require_id("digest", &receipt.digest)
}

pub(super) async fn check_receipt_in(
    connection: &mut SqliteConnection,
    caller_scope: &str,
    request_id: &str,
    digest: &str,
) -> Result<AgentChatReceiptCheck> {
    let cutoff = format_timestamp(Utc::now() - Duration::days(AGENT_CHAT_RECEIPT_RETENTION_DAYS));
    sqlx::query("DELETE FROM agentChatReceipts WHERE createdAt < ?")
        .bind(cutoff)
        .execute(&mut *connection)
        .await?;
    let row = sqlx::query(
        "SELECT digest, receiptJson FROM agentChatReceipts WHERE callerScope = ? AND requestId = ?",
    )
    .bind(caller_scope)
    .bind(request_id)
    .fetch_optional(&mut *connection)
    .await?;
    let Some(row) = row else {
        return Ok(AgentChatReceiptCheck::New);
    };
    if row.try_get::<String, _>("digest")? != digest {
        return Ok(AgentChatReceiptCheck::Conflict);
    }
    let json: String = row.try_get("receiptJson")?;
    Ok(AgentChatReceiptCheck::Replay(serde_json::from_str(&json)?))
}

pub(super) async fn insert_receipt_in(
    connection: &mut SqliteConnection,
    chat_id: Option<&str>,
    cursor: Option<i64>,
    receipt: &AgentChatReceipt,
) -> Result<()> {
    sqlx::query(
        "INSERT INTO agentChatReceipts \
         (callerScope, requestId, chatId, digest, receiptJson, cursor, createdAt) \
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&receipt.caller_scope)
    .bind(&receipt.request_id)
    .bind(chat_id)
    .bind(&receipt.digest)
    .bind(serde_json::to_string(&receipt.receipt)?)
    .bind(cursor)
    .bind(format_timestamp(Utc::now()))
    .execute(&mut *connection)
    .await?;
    Ok(())
}

impl RuntimeStore {
    /// Looks a command up before running it.
    pub async fn check_agent_chat_receipt(
        &self,
        caller_scope: &str,
        request_id: &str,
        digest: &str,
    ) -> Result<AgentChatReceiptCheck> {
        require_id("callerScope", caller_scope)?;
        require_id("requestId", request_id)?;
        let mut connection = self.pool().acquire().await?;
        check_receipt_in(&mut connection, caller_scope, request_id, digest).await
    }

    /// Records the response of a command that did not commit a chat change
    /// (one that only reached the provider, or was refused). Returns `New`
    /// when stored, otherwise what an earlier identical or conflicting
    /// command left. Commands that change the chat pass their receipt to
    /// `commit_agent_chat` instead, so both land together.
    pub async fn record_agent_chat_receipt(
        &self,
        chat_id: Option<&str>,
        receipt: &AgentChatReceipt,
    ) -> Result<AgentChatReceiptCheck> {
        require_receipt(receipt)?;
        let mut tx = self.pool().begin().await?;
        let existing = check_receipt_in(
            &mut tx,
            &receipt.caller_scope,
            &receipt.request_id,
            &receipt.digest,
        )
        .await?;
        if existing != AgentChatReceiptCheck::New {
            tx.commit().await?;
            return Ok(existing);
        }
        let cursor = match chat_id {
            Some(chat_id) => Some(
                sqlx::query_scalar::<_, i64>(
                    "SELECT cursor FROM agentChatSessions WHERE chatId = ?",
                )
                .bind(chat_id)
                .fetch_optional(&mut *tx)
                .await?
                .ok_or_else(|| AgentChatStoreError::NotFound(chat_id.to_string()))?,
            ),
            None => None,
        };
        insert_receipt_in(&mut tx, chat_id, cursor, receipt).await?;
        tx.commit().await?;
        Ok(AgentChatReceiptCheck::New)
    }
}

//! Durable cancellation before a message reaches the chat actor's send path.
//! Markers belong to the chat's lifetime, so receipt retention and provider
//! generation changes cannot admit a delayed cancelled message.

use anyhow::Result;
use chrono::Utc;

use super::agent_chat_models::AgentChatStoreError;
use super::agent_chat_validation::{require_chat_id, require_id};
use super::{format_timestamp, RuntimeStore};

impl RuntimeStore {
    /// Prevents this exact client message from being admitted in any provider
    /// generation. Returns true for a new marker, false for an existing marker.
    /// The actor must persist this before acknowledging message cancellation.
    pub async fn cancel_agent_chat_message(
        &self,
        chat_id: &str,
        client_message_id: &str,
    ) -> Result<bool> {
        require_chat_id(chat_id)?;
        require_id("clientMessageId", client_message_id)?;
        let mut tx = self.pool().begin().await?;
        // Write first to serialize concurrent markers before any read snapshot.
        let result = sqlx::query(
            "INSERT INTO agentChatCancelledMessages (chatId, clientMessageId, cancelledAt) \
             SELECT chatId, ?, ? FROM agentChatSessions WHERE chatId = ? \
             ON CONFLICT(chatId, clientMessageId) DO NOTHING",
        )
        .bind(client_message_id)
        .bind(format_timestamp(Utc::now()))
        .bind(chat_id)
        .execute(&mut *tx)
        .await?;
        let inserted = result.rows_affected() != 0;
        if !inserted {
            let exists: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM agentChatSessions WHERE chatId = ?)",
            )
            .bind(chat_id)
            .fetch_one(&mut *tx)
            .await?;
            if !exists {
                anyhow::bail!(AgentChatStoreError::NotFound(chat_id.to_string()));
            }
        }
        tx.commit().await?;
        Ok(inserted)
    }

    /// Checks admission for an exact client message without reading history.
    /// An unknown chat is an error; archive and generation do not clear markers.
    pub async fn is_agent_chat_message_cancelled(
        &self,
        chat_id: &str,
        client_message_id: &str,
    ) -> Result<bool> {
        require_chat_id(chat_id)?;
        require_id("clientMessageId", client_message_id)?;
        sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM agentChatCancelledMessages c \
             WHERE c.chatId = s.chatId AND c.clientMessageId = ?) \
             FROM agentChatSessions s WHERE s.chatId = ?",
        )
        .bind(client_message_id)
        .bind(chat_id)
        .fetch_optional(self.pool())
        .await?
        .ok_or_else(|| AgentChatStoreError::NotFound(chat_id.to_string()).into())
    }
}

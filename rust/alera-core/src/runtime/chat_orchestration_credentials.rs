//! Per-chat-generation MCP credentials. Only a SHA-256 of the secret is
//! stored; the secret lives in the chat's private credential file. Issuing a
//! credential revokes the chat's earlier ones, and a generation older than
//! one already issued is refused so a stale launch cannot rebind.

use anyhow::Result;
use chrono::{Duration, Utc};
use sha2::{Digest, Sha256};
use sqlx::sqlite::SqliteRow;
use sqlx::Row;

use super::chat_orchestration_delivery::*;
use super::chat_orchestration_models::*;
use super::chat_orchestration_rows::{conflict, require_id};
use super::{format_timestamp, parse_timestamp, RuntimeStore};

/// 244 random bits from two UUIDv4s, hex encoded.
pub fn new_chat_orchestration_credential_secret() -> String {
    format!(
        "{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    )
}

pub fn hash_chat_orchestration_credential(secret: &str) -> String {
    hex::encode(Sha256::digest(secret.as_bytes()))
}

fn credential_from_row(row: &SqliteRow) -> Result<ChatOrchestrationCredential> {
    Ok(ChatOrchestrationCredential {
        chat_id: row.try_get("chatId")?,
        generation: row.try_get("generation")?,
        issued_at: parse_timestamp(row.try_get("issuedAt")?),
        revoked_at: row
            .try_get::<Option<String>, _>("revokedAt")?
            .map(|value| parse_timestamp(&value)),
        revoke_reason: row.try_get("revokeReason")?,
    })
}

fn require_hash(credential_hash: &str) -> Result<()> {
    require_id("credentialHash", credential_hash)?;
    if credential_hash.len() != 64 || !credential_hash.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(ChatOrchestrationStoreError::Invalid(
            "credentialHash must be a SHA-256 hex digest".into(),
        )
        .into());
    }
    Ok(())
}

impl RuntimeStore {
    pub async fn issue_chat_orchestration_credential(
        &self,
        chat_id: &str,
        generation: i64,
        credential_hash: &str,
    ) -> Result<ChatOrchestrationCredential> {
        require_id("chatId", chat_id)?;
        require_hash(credential_hash)?;
        if generation < 1 {
            return Err(ChatOrchestrationStoreError::Invalid(
                "generation must be at least 1".into(),
            )
            .into());
        }
        let mut tx = self.pool().begin().await?;
        let now = Utc::now();
        let cutoff = format_timestamp(
            now - Duration::days(CHAT_ORCHESTRATION_REVOKED_CREDENTIAL_RETENTION_DAYS),
        );
        sqlx::query(
            "DELETE FROM chatOrchestrationCredentials WHERE revokedAt IS NOT NULL AND revokedAt < ?",
        )
        .bind(cutoff)
        .execute(&mut *tx)
        .await?;
        let newest: Option<i64> = sqlx::query_scalar(
            "SELECT MAX(generation) FROM chatOrchestrationCredentials WHERE chatId = ?",
        )
        .bind(chat_id)
        .fetch_one(&mut *tx)
        .await?;
        if newest.is_some_and(|newest| generation < newest) {
            return Err(conflict(format!(
                "chat {chat_id} already has a credential for a newer generation"
            )));
        }
        let now = format_timestamp(now);
        sqlx::query(
            "UPDATE chatOrchestrationCredentials SET revokedAt = ?, revokeReason = 'superseded' \
             WHERE chatId = ? AND revokedAt IS NULL",
        )
        .bind(&now)
        .bind(chat_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO chatOrchestrationCredentials (credentialHash, chatId, generation, issuedAt) \
             VALUES (?, ?, ?, ?)",
        )
        .bind(credential_hash)
        .bind(chat_id)
        .bind(generation)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(ChatOrchestrationCredential {
            chat_id: chat_id.to_string(),
            generation,
            issued_at: parse_timestamp(&now),
            revoked_at: None,
            revoke_reason: None,
        })
    }

    /// The live credential behind `credential_hash`; `None` once revoked or
    /// unknown. The caller still checks the generation against the chat's.
    pub async fn find_chat_orchestration_credential(
        &self,
        credential_hash: &str,
    ) -> Result<Option<ChatOrchestrationCredential>> {
        if require_hash(credential_hash).is_err() {
            return Ok(None);
        }
        let row = sqlx::query(
            "SELECT chatId, generation, issuedAt, revokedAt, revokeReason \
             FROM chatOrchestrationCredentials WHERE credentialHash = ? AND revokedAt IS NULL",
        )
        .bind(credential_hash)
        .fetch_optional(self.pool())
        .await?;
        row.as_ref().map(credential_from_row).transpose()
    }

    /// Revokes every live credential of the chat (close, archive).
    pub async fn revoke_chat_orchestration_credentials(
        &self,
        chat_id: &str,
        reason: &str,
    ) -> Result<u64> {
        self.revoke_chat_orchestration_credentials_before(chat_id, i64::MAX, reason)
            .await
    }

    /// Revokes the chat's live credentials below `generation` (provider switch).
    pub async fn revoke_chat_orchestration_credentials_before(
        &self,
        chat_id: &str,
        generation: i64,
        reason: &str,
    ) -> Result<u64> {
        require_id("chatId", chat_id)?;
        require_id("reason", reason)?;
        Ok(sqlx::query(
            "UPDATE chatOrchestrationCredentials SET revokedAt = ?, revokeReason = ? \
             WHERE chatId = ? AND generation < ? AND revokedAt IS NULL",
        )
        .bind(format_timestamp(Utc::now()))
        .bind(reason)
        .bind(chat_id)
        .bind(generation)
        .execute(self.pool())
        .await?
        .rows_affected())
    }

    pub async fn revoke_all_chat_orchestration_credentials(&self, reason: &str) -> Result<u64> {
        require_id("reason", reason)?;
        Ok(sqlx::query(
            "UPDATE chatOrchestrationCredentials SET revokedAt = ?, revokeReason = ? \
             WHERE revokedAt IS NULL",
        )
        .bind(format_timestamp(Utc::now()))
        .bind(reason)
        .execute(self.pool())
        .await?
        .rows_affected())
    }
}

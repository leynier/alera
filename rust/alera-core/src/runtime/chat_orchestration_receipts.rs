//! Mutation receipts keyed by `(scope, verb, requestId)`. The same payload
//! replays the stored response; a different payload under the same key is a
//! conflict. Digests come from a canonical JSON form so key order and the
//! request id itself never change them.

use anyhow::Result;
use chrono::{Duration, Utc};
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::{Row, SqliteConnection};

use super::chat_orchestration_delivery::*;
use super::chat_orchestration_models::*;
use super::chat_orchestration_rows::{require_bounded, require_id};
use super::{format_timestamp, RuntimeStore};

fn canonical(value: &Value, out: &mut String) {
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            out.push('{');
            for (index, key) in keys.into_iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                out.push_str(&Value::String(key.clone()).to_string());
                out.push(':');
                canonical(&map[key], out);
            }
            out.push('}');
        }
        Value::Array(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                canonical(item, out);
            }
            out.push(']');
        }
        other => out.push_str(&other.to_string()),
    }
}

/// SHA-256 hex of the verb and the canonical payload, ignoring top-level
/// `requestId` / `clientRequestId`.
pub fn chat_orchestration_request_digest(verb: &str, payload: &Value) -> String {
    let mut payload = payload.clone();
    if let Some(map) = payload.as_object_mut() {
        map.remove("requestId");
        map.remove("clientRequestId");
    }
    let mut text = String::new();
    canonical(&payload, &mut text);
    let mut hasher = Sha256::new();
    hasher.update(verb.as_bytes());
    hasher.update([0]);
    hasher.update(text.as_bytes());
    hex::encode(hasher.finalize())
}

pub(super) fn require_receipt(receipt: &ChatOrchestrationReceipt) -> Result<()> {
    require_id("scope", &receipt.scope)?;
    require_id("verb", &receipt.verb)?;
    require_id("requestId", &receipt.request_id)?;
    require_id("digest", &receipt.digest)?;
    require_bounded(
        "receipt response",
        &receipt.response.to_string(),
        CHAT_ORCHESTRATION_RECEIPT_MAX_BYTES,
    )
}

/// Also the first write of a receipt-guarded transaction, which takes the
/// write lock before the receipt is read.
pub(super) async fn prune_receipts_in(connection: &mut SqliteConnection) -> Result<()> {
    let cutoff =
        format_timestamp(Utc::now() - Duration::days(CHAT_ORCHESTRATION_RECEIPT_RETENTION_DAYS));
    sqlx::query("DELETE FROM chatOrchestrationReceipts WHERE createdAt < ?")
        .bind(cutoff)
        .execute(&mut *connection)
        .await?;
    Ok(())
}

pub(super) async fn check_receipt_in(
    connection: &mut SqliteConnection,
    scope: &str,
    verb: &str,
    request_id: &str,
    digest: &str,
) -> Result<ChatOrchestrationReceiptCheck> {
    let row = sqlx::query(
        "SELECT digest, responseJson FROM chatOrchestrationReceipts \
         WHERE scope = ? AND verb = ? AND requestId = ?",
    )
    .bind(scope)
    .bind(verb)
    .bind(request_id)
    .fetch_optional(&mut *connection)
    .await?;
    let Some(row) = row else {
        return Ok(ChatOrchestrationReceiptCheck::New);
    };
    if row.try_get::<String, _>("digest")? != digest {
        return Ok(ChatOrchestrationReceiptCheck::Conflict);
    }
    let json: String = row.try_get("responseJson")?;
    Ok(ChatOrchestrationReceiptCheck::Replay(
        serde_json::from_str::<Value>(&json)?,
    ))
}

pub(super) async fn insert_receipt_in(
    connection: &mut SqliteConnection,
    task_id: Option<&str>,
    receipt: &ChatOrchestrationReceipt,
) -> Result<()> {
    sqlx::query(
        "INSERT INTO chatOrchestrationReceipts \
         (scope, verb, requestId, digest, responseJson, taskId, createdAt) \
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&receipt.scope)
    .bind(&receipt.verb)
    .bind(&receipt.request_id)
    .bind(&receipt.digest)
    .bind(receipt.response.to_string())
    .bind(task_id)
    .bind(format_timestamp(Utc::now()))
    .execute(&mut *connection)
    .await?;
    Ok(())
}

/// Inserts a receipt when its key is unused, then reads the winner when a
/// concurrent caller already committed the same key. The caller holds a
/// write transaction, so this avoids leaking a SQLite UNIQUE error to an
/// idempotent API.
pub(super) async fn insert_or_check_receipt_in(
    connection: &mut SqliteConnection,
    task_id: Option<&str>,
    receipt: &ChatOrchestrationReceipt,
) -> Result<ChatOrchestrationReceiptCheck> {
    let inserted = sqlx::query(
        "INSERT INTO chatOrchestrationReceipts \
         (scope, verb, requestId, digest, responseJson, taskId, createdAt) \
         VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(scope, verb, requestId) DO NOTHING",
    )
    .bind(&receipt.scope)
    .bind(&receipt.verb)
    .bind(&receipt.request_id)
    .bind(&receipt.digest)
    .bind(receipt.response.to_string())
    .bind(task_id)
    .bind(format_timestamp(Utc::now()))
    .execute(&mut *connection)
    .await?
    .rows_affected();
    if inserted > 0 {
        return Ok(ChatOrchestrationReceiptCheck::New);
    }
    check_receipt_in(
        connection,
        &receipt.scope,
        &receipt.verb,
        &receipt.request_id,
        &receipt.digest,
    )
    .await
}

impl RuntimeStore {
    /// Replaces a task's initial admission response once its external work is
    /// prepared. Digest and response guards preserve any competing result.
    pub async fn finalize_chat_orchestration_receipt(
        &self,
        receipt: &ChatOrchestrationReceipt,
        expected_response: &serde_json::Value,
    ) -> Result<ChatOrchestrationReceiptCheck> {
        require_receipt(receipt)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE chatOrchestrationReceipts SET responseJson = ? \
             WHERE scope = ? AND verb = ? AND requestId = ? AND digest = ? \
             AND taskId IS NOT NULL AND responseJson = ?",
        )
        .bind(receipt.response.to_string())
        .bind(&receipt.scope)
        .bind(&receipt.verb)
        .bind(&receipt.request_id)
        .bind(&receipt.digest)
        .bind(expected_response.to_string())
        .execute(&mut *tx)
        .await?;
        let outcome = check_receipt_in(
            &mut tx,
            &receipt.scope,
            &receipt.verb,
            &receipt.request_id,
            &receipt.digest,
        )
        .await?;
        tx.commit().await?;
        Ok(outcome)
    }

    /// Looks a mutation up before running it.
    pub async fn check_chat_orchestration_receipt(
        &self,
        scope: &str,
        verb: &str,
        request_id: &str,
        digest: &str,
    ) -> Result<ChatOrchestrationReceiptCheck> {
        require_id("scope", scope)?;
        require_id("verb", verb)?;
        require_id("requestId", request_id)?;
        let mut tx = self.pool().begin().await?;
        prune_receipts_in(&mut tx).await?;
        let check = check_receipt_in(&mut tx, scope, verb, request_id, digest).await?;
        tx.commit().await?;
        Ok(check)
    }

    /// Stores the response of an idempotent mutation (`cancel`, `send`
    /// without a task, `respond`, ...). Returns `New` when stored, otherwise
    /// what an earlier identical or conflicting request left; the caller then
    /// answers with that instead of its own response. `create_chat_orchestration_task`
    /// takes its receipt directly so the task and receipt land together.
    pub async fn record_chat_orchestration_receipt(
        &self,
        task_id: Option<&str>,
        receipt: &ChatOrchestrationReceipt,
    ) -> Result<ChatOrchestrationReceiptCheck> {
        require_receipt(receipt)?;
        let mut tx = self.pool().begin().await?;
        prune_receipts_in(&mut tx).await?;
        let existing = insert_or_check_receipt_in(&mut tx, task_id, receipt).await?;
        tx.commit().await?;
        Ok(existing)
    }
}

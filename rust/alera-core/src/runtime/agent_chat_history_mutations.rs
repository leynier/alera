//! Durable history prefixes, independent of the bounded snapshot window.

#[cfg(test)]
#[path = "agent_chat_history_mutation_tests.rs"]
mod tests;

use anyhow::Result;
use chrono::Utc;
use serde_json::{json, Value};
use sqlx::SqliteConnection;

use super::agent_chat_native_operations::{
    require_no_native_operation_in, require_rewind_header, rewind_in, target_in,
};
use super::agent_chat_receipts::{check_receipt_in, insert_receipt_in, require_receipt};
use super::agent_chat_store::{
    full_snapshot_in, insert_tab_in, require_new_record, require_session_row_in,
    require_workspace_in, SESSION_COLUMNS,
};
use super::agent_chat_validation::{header_json, metadata_json, parse_snapshot, require_tab};
use super::*;

fn invalid(message: &str) -> anyhow::Error {
    AgentChatStoreError::Invalid(message.into()).into()
}

async fn check_in(
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

impl RuntimeStore {
    /// Copies the durable prefix through a settled response. Provider-native
    /// identities, cancellation markers, and source receipts are never copied.
    pub async fn fork_agent_chat_through_turn(
        &self,
        source_chat_id: &str,
        expected_cursor: i64,
        turn_id: &str,
        new_record: &AgentChatRecord,
        new_tab: &WorkspaceTabRecord,
        receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatCreateOutcome> {
        let snapshot = parse_snapshot(&new_record.snapshot)?;
        require_new_record(new_record, &snapshot)?;
        require_tab(new_record, new_tab)?;
        if new_record.native_thread_id.is_some()
            || !snapshot.items.is_empty()
            || !snapshot.turns.is_empty()
            || !snapshot.pending_requests.is_empty()
            || snapshot.session.status != AgentChatSessionStatus::Stopped
            || snapshot.session.active_turn_id.is_some()
            || snapshot.provider == AGENT_CHAT_UNSELECTED_PROVIDER
        {
            return Err(invalid(
                "a fork starts selected, stopped, and without native state or initial history",
            ));
        }
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        match check_in(&mut tx, receipt).await? {
            AgentChatReceiptCheck::Replay(value) => {
                tx.commit().await?;
                return Ok(AgentChatCreateOutcome::Replay(value));
            }
            AgentChatReceiptCheck::Conflict => {
                tx.commit().await?;
                return Ok(AgentChatCreateOutcome::ReceiptConflict);
            }
            AgentChatReceiptCheck::New => {}
        }
        let source = require_session_row_in(&mut tx, source_chat_id).await?;
        require_no_native_operation_in(&mut tx, source_chat_id).await?;
        if source.cursor != expected_cursor {
            return Err(invalid("source chat cursor changed"));
        }
        let (turn_seq, _, item_seq) = target_in(&mut tx, source_chat_id, turn_id).await?;
        require_workspace_in(&mut tx, &new_record.workspace_id).await?;
        insert_tab_in(&mut tx, new_tab).await?;
        let now = format_timestamp(Utc::now());
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "INSERT INTO agentChatSessions ({SESSION_COLUMNS}) VALUES (?, ?, ?, ?, ?, NULL, 1, 0, NULL, 0, ?, ?, ?, ?)"
        ))).bind(&new_record.chat_id).bind(&new_record.workspace_id).bind(&new_record.tab_id)
            .bind(&new_record.provider_instance_id).bind(&new_record.provider).bind(header_json(&snapshot)?)
            .bind(metadata_json(new_record.metadata.as_ref())?).bind(&now).bind(&now).execute(&mut *tx).await?;
        sqlx::query("INSERT INTO agentChatTurns (chatId, turnId, seq, status, turnJson, byteSize, updatedCursor) \
            SELECT ?, turnId, seq, status, turnJson, byteSize, 0 FROM agentChatTurns WHERE chatId = ? AND seq <= ?")
            .bind(&new_record.chat_id).bind(source_chat_id).bind(turn_seq).execute(&mut *tx).await?;
        sqlx::query("INSERT INTO agentChatItems (chatId, itemId, seq, turnId, itemJson, byteSize, updatedCursor) \
            SELECT ?1, itemId, seq, turnId, itemJson, byteSize, 0 FROM agentChatItems \
            WHERE chatId = ?2 AND seq <= ?3 AND (turnId IS NULL OR turnId IN \
                (SELECT turnId FROM agentChatTurns WHERE chatId = ?1))")
            .bind(&new_record.chat_id).bind(source_chat_id).bind(item_seq).execute(&mut *tx).await?;
        let row = require_session_row_in(&mut tx, &new_record.chat_id).await?;
        let snapshot = full_snapshot_in(&mut tx, &row).await?;
        if let Some(receipt) = receipt {
            let operation_kind = if new_record
                .metadata
                .as_ref()
                .and_then(|metadata| metadata.get("nativeFork"))
                .is_some()
            {
                "nativeForkDeferred"
            } else {
                "transcriptFork"
            };
            let saved = AgentChatReceipt {
                receipt: json!({"chatId": row.chat_id, "tabId": row.tab_id, "snapshot": snapshot,
                    "operationKind": operation_kind, "filesystemChangesReverted": false}),
                ..receipt.clone()
            };
            insert_receipt_in(&mut tx, Some(&row.chat_id), Some(0), &saved).await?;
        }
        tx.commit().await?;
        Ok(AgentChatCreateOutcome::Created(Box::new(
            row.into_record(snapshot),
        )))
    }

    /// Removes the selected turn and every later transcript row. The returned
    /// prompt is the complete initial user item; ambiguous steering is refused.
    /// Filesystem changes are outside this operation.
    pub async fn rewind_agent_chat_before_turn(
        &self,
        chat_id: &str,
        expected_cursor: i64,
        turn_id: &str,
        snapshot: &Value,
        receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatRewindOutcome> {
        let snapshot = parse_snapshot(snapshot)?;
        require_rewind_header(&snapshot)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        match check_in(&mut tx, receipt).await? {
            AgentChatReceiptCheck::Replay(value) => {
                tx.commit().await?;
                return Ok(AgentChatRewindOutcome::Replay(value));
            }
            AgentChatReceiptCheck::Conflict => {
                tx.commit().await?;
                return Ok(AgentChatRewindOutcome::ReceiptConflict);
            }
            AgentChatReceiptCheck::New => {}
        }
        let row = require_session_row_in(&mut tx, chat_id).await?;
        if row.cursor != expected_cursor {
            tx.commit().await?;
            return Ok(AgentChatRewindOutcome::CursorConflict {
                current: row.cursor,
            });
        }
        require_no_native_operation_in(&mut tx, chat_id).await?;
        let (record, event, prompt) = rewind_in(&mut tx, &row, turn_id, snapshot, None).await?;
        if let Some(receipt) = receipt {
            let saved = AgentChatReceipt {
                receipt: json!({"chatId": chat_id, "snapshot": record.snapshot, "event": event,
                    "prompt": prompt.get("text").and_then(Value::as_str).unwrap_or(""),
                    "attachments": prompt.get("attachments").cloned().unwrap_or(json!([])), "promptItem": prompt,
                    "operationKind": "transcriptRewind", "filesystemChangesReverted": false, "nativeRollback": false,
                    "nativeRollbackUnavailableReason": "Use native mode to request a verified native conversation rewind."}),
                ..receipt.clone()
            };
            insert_receipt_in(&mut tx, Some(chat_id), Some(event.cursor), &saved).await?;
        }
        tx.commit().await?;
        Ok(AgentChatRewindOutcome::Rewound {
            record: Box::new(record),
            event,
            prompt,
        })
    }
}

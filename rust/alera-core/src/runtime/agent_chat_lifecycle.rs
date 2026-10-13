//! Closing, reopening, and annotating a chat. Closing archives: the tab
//! goes, the transcript stays.

use anyhow::Result;
use chrono::Utc;
use serde_json::Value;

use super::agent_chat_models::*;
use super::agent_chat_receipts::{check_receipt_in, insert_receipt_in, require_receipt};
use super::agent_chat_store::{full_snapshot_in, insert_tab_in, require_session_row_in};
use super::agent_chat_validation::{metadata_json, parse_header, require_tab};
use super::{format_timestamp, RuntimeStore, WorkspaceTabRecord};

impl RuntimeStore {
    /// Replaces (or clears) the host-only metadata. It is not part of the
    /// snapshot, so it does not move the cursor.
    pub async fn set_agent_chat_metadata(
        &self,
        chat_id: &str,
        metadata: Option<&Value>,
    ) -> Result<AgentChatRecord> {
        let json = metadata_json(metadata)?;
        let updated = sqlx::query(
            "UPDATE agentChatSessions SET metadataJson = ?, updatedAt = ? WHERE chatId = ?",
        )
        .bind(json)
        .bind(format_timestamp(Utc::now()))
        .bind(chat_id)
        .execute(self.pool())
        .await?;
        if updated.rows_affected() == 0 {
            anyhow::bail!(AgentChatStoreError::NotFound(chat_id.to_string()));
        }
        self.agent_chat(chat_id)
            .await?
            .ok_or_else(|| AgentChatStoreError::NotFound(chat_id.to_string()).into())
    }

    /// Closes the chat: removes its open tab and archives the chat in one
    /// transaction, keeping the transcript. The host stops the provider
    /// process; a live status left behind is cleared by startup recovery.
    pub async fn archive_agent_chat(&self, chat_id: &str) -> Result<AgentChatRecord> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let row = require_session_row_in(&mut tx, chat_id).await?;
        if !row.archived {
            let removed = sqlx::query("DELETE FROM workspaceTabs WHERE id = ? AND kind = ?")
                .bind(&row.tab_id)
                .bind(AGENT_CHAT_TAB_KIND)
                .execute(&mut *tx)
                .await?;
            if removed.rows_affected() > 0 {
                sqlx::query("DELETE FROM agentProfileLaunchReceipts WHERE tabId = ?")
                    .bind(&row.tab_id)
                    .execute(&mut *tx)
                    .await?;
                super::automation_binding_store::release_bound_tabs_for_tab_in(
                    &mut tx,
                    &row.tab_id,
                    "tabClosed",
                )
                .await?;
            }
            let now = format_timestamp(Utc::now());
            sqlx::query(
                "UPDATE agentChatSessions SET archived = 1, archivedAt = ?, updatedAt = ? \
                 WHERE chatId = ? AND archived = 0",
            )
            .bind(&now)
            .bind(&now)
            .bind(chat_id)
            .execute(&mut *tx)
            .await?;
        }
        let row = require_session_row_in(&mut tx, chat_id).await?;
        let snapshot = full_snapshot_in(&mut tx, &row).await?;
        tx.commit().await?;
        Ok(row.into_record(snapshot))
    }

    /// Reopens an archived chat in a new `agentChat` tab of its workspace.
    /// The tab and archive state are committed in the reopening delta.
    pub async fn restore_agent_chat(
        &self,
        chat_id: &str,
        tab: &WorkspaceTabRecord,
    ) -> Result<AgentChatRecord> {
        match self
            .restore_agent_chat_with_receipt(chat_id, tab, None)
            .await?
        {
            AgentChatRestoreOutcome::Restored(record) => Ok(*record),
            AgentChatRestoreOutcome::Replay(_) => {
                anyhow::bail!(AgentChatStoreError::Invalid(
                    "restore without a receipt unexpectedly replayed".into()
                ));
            }
            AgentChatRestoreOutcome::ReceiptConflict => {
                anyhow::bail!(AgentChatStoreError::Invalid(
                    "restore without a receipt unexpectedly conflicted".into()
                ));
            }
        }
    }

    /// Reopens an archived chat and optionally records the caller receipt in
    /// the same transaction as the new tab and cursor update.
    pub async fn restore_agent_chat_with_receipt(
        &self,
        chat_id: &str,
        tab: &WorkspaceTabRecord,
        receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatRestoreOutcome> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        if let Some(receipt) = receipt {
            require_receipt(receipt)?;
            match check_receipt_in(
                &mut tx,
                &receipt.caller_scope,
                &receipt.request_id,
                &receipt.digest,
            )
            .await?
            {
                AgentChatReceiptCheck::New => {}
                AgentChatReceiptCheck::Replay(value) => {
                    tx.commit().await?;
                    return Ok(AgentChatRestoreOutcome::Replay(value));
                }
                AgentChatReceiptCheck::Conflict => {
                    tx.commit().await?;
                    return Ok(AgentChatRestoreOutcome::ReceiptConflict);
                }
            }
        }
        let mut row = require_session_row_in(&mut tx, chat_id).await?;
        if !row.archived {
            anyhow::bail!(AgentChatStoreError::Invalid(format!(
                "chat {chat_id} is already open in tab {}",
                row.tab_id
            )));
        }
        let mut probe = row.clone().into_record(Value::Null);
        probe.tab_id = tab.id.clone();
        require_tab(&probe, tab)?;
        insert_tab_in(&mut tx, tab).await?;
        sqlx::query(
            "UPDATE agentChatSessions SET tabId = ?, archived = 0, archivedAt = NULL WHERE chatId = ?",
        )
        .bind(&tab.id)
        .bind(chat_id)
        .execute(&mut *tx)
        .await?;
        let mut snapshot = parse_header(&row.snapshot_json)?;
        snapshot.tab_id = tab.id.clone();
        snapshot.cursor = row.cursor + 1;
        snapshot.extra.insert("archived".into(), Value::Bool(false));
        let mut delta = AgentChatDelta::default();
        delta.extra.insert("archived".into(), Value::Bool(false));
        delta
            .extra
            .insert("tabId".into(), Value::String(tab.id.clone()));
        row.tab_id = tab.id.clone();
        row.archived = false;
        super::agent_chat_commit::commit_in(&mut tx, &row, snapshot, delta, None).await?;
        let row = require_session_row_in(&mut tx, chat_id).await?;
        let snapshot = full_snapshot_in(&mut tx, &row).await?;
        if let Some(receipt) = receipt {
            let stored_receipt = AgentChatReceipt {
                caller_scope: receipt.caller_scope.clone(),
                request_id: receipt.request_id.clone(),
                digest: receipt.digest.clone(),
                receipt: serde_json::json!({
                    "chatId": chat_id,
                    "tabId": row.tab_id.clone(),
                    "snapshot": snapshot.clone(),
                }),
            };
            insert_receipt_in(&mut tx, Some(chat_id), Some(row.cursor), &stored_receipt).await?;
        }
        tx.commit().await?;
        Ok(AgentChatRestoreOutcome::Restored(Box::new(
            row.into_record(snapshot),
        )))
    }
}

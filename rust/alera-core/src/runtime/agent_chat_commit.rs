//! One commit moves a chat from `cursor` to `cursor + 1`: the snapshot
//! header, the turn and item rows the delta touches, the journal entry, and the
//! optional command receipt land in a single transaction.
//!
//! The delta must explain every header change, so a client that applies the
//! journal to the previous snapshot retains every changed turn and item.
//! Snapshot turn omissions only narrow the projection and never remove history.
//! Items persist from the delta only; `items` inside the committed snapshot
//! are ignored.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::Result;
use chrono::Utc;
use serde_json::{Map, Value};
use sqlx::{Row, SqliteConnection};

use super::agent_chat_models::*;
use super::agent_chat_projection::require_snapshot_budget_in;
use super::agent_chat_receipts::{check_receipt_in, insert_receipt_in, require_receipt};
use super::agent_chat_store::{insert_item_in, require_session_row_in, SessionRow};
use super::agent_chat_turns::{require_turn_changes_in, write_turns_in};
use super::agent_chat_validation::*;
use super::{format_timestamp, RuntimeStore};

fn invalid(message: impl Into<String>) -> anyhow::Error {
    AgentChatStoreError::Invalid(message.into()).into()
}

fn require_field<T: PartialEq>(
    label: &str,
    stored: &T,
    committed: &T,
    delta: Option<&T>,
) -> Result<()> {
    let expected = delta.unwrap_or(stored);
    if expected != committed {
        return Err(invalid(format!(
            "snapshot {label} differs from what the delta describes"
        )));
    }
    Ok(())
}

fn require_extra(
    stored: &Map<String, Value>,
    committed: &Map<String, Value>,
    delta: &Map<String, Value>,
) -> Result<()> {
    let keys: BTreeSet<&String> = stored.keys().chain(committed.keys()).collect();
    for key in keys {
        let now = committed.get(key).unwrap_or(&Value::Null);
        if stored.get(key).unwrap_or(&Value::Null) != now
            && delta.get(key).unwrap_or(&Value::Null) != now
        {
            return Err(invalid(format!(
                "snapshot field {key} changed without a delta entry"
            )));
        }
    }
    Ok(())
}

async fn require_switch_allowed(
    connection: &mut SqliteConnection,
    chat_id: &str,
    stored: &AgentChatSnapshot,
) -> Result<()> {
    let running: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM agentChatTurns WHERE chatId = ? AND status = 'running')",
    )
    .bind(chat_id)
    .fetch_one(&mut *connection)
    .await?;
    let reason = if stored.session.active_turn_id.is_some() || running {
        Some("a turn is active")
    } else if !stored.pending_requests.is_empty() {
        Some("requests are pending")
    } else if matches!(
        stored.session.status,
        AgentChatSessionStatus::Starting
            | AgentChatSessionStatus::Running
            | AgentChatSessionStatus::Waiting
    ) {
        Some("the session is busy")
    } else {
        None
    };
    match reason {
        Some(reason) => Err(AgentChatStoreError::ProviderSwitchBlocked {
            chat_id: chat_id.to_string(),
            reason: reason.to_string(),
        }
        .into()),
        None => Ok(()),
    }
}

async fn stored_item_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    item_id: &str,
) -> Result<Option<AgentChatItem>> {
    let json: Option<String> =
        sqlx::query_scalar("SELECT itemJson FROM agentChatItems WHERE chatId = ? AND itemId = ?")
            .bind(chat_id)
            .bind(item_id)
            .fetch_optional(&mut *connection)
            .await?;
    json.map(|json| Ok(serde_json::from_str(&json)?))
        .transpose()
}

async fn write_items_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    cursor: i64,
    delta: &AgentChatDelta,
) -> Result<()> {
    let mut order: Vec<String> = Vec::new();
    let mut touched: BTreeMap<String, AgentChatItem> = BTreeMap::new();
    for item in delta.items.iter().flatten() {
        if touched.insert(item.item_id.clone(), item.clone()).is_some() {
            return Err(invalid(format!("delta repeats item {}", item.item_id)));
        }
        order.push(item.item_id.clone());
    }
    for id in delta.removed_item_ids.iter().flatten() {
        if touched.contains_key(id) {
            return Err(invalid(format!("item {id} is both written and removed")));
        }
        sqlx::query("DELETE FROM agentChatItems WHERE chatId = ? AND itemId = ?")
            .bind(chat_id)
            .bind(id)
            .execute(&mut *connection)
            .await?;
    }
    for append in &delta.text_appends {
        if !touched.contains_key(&append.item_id) {
            let item = stored_item_in(connection, chat_id, &append.item_id)
                .await?
                .ok_or_else(|| {
                    invalid(format!(
                        "text append targets unknown item {}",
                        append.item_id
                    ))
                })?;
            touched.insert(append.item_id.clone(), item);
            order.push(append.item_id.clone());
        }
        let item = touched
            .get_mut(&append.item_id)
            .expect("item was just inserted");
        apply_text_append(item, append)?;
    }
    let mut next_seq: i64 =
        sqlx::query_scalar("SELECT COALESCE(MAX(seq), 0) + 1 FROM agentChatItems WHERE chatId = ?")
            .bind(chat_id)
            .fetch_one(&mut *connection)
            .await?;
    for id in order {
        let item = &touched[&id];
        let json = item_json(item)?;
        let updated = sqlx::query(
            "UPDATE agentChatItems SET turnId = ?, itemJson = ?, byteSize = ?, updatedCursor = ? \
             WHERE chatId = ? AND itemId = ?",
        )
        .bind(&item.turn_id)
        .bind(&json)
        .bind(json.len() as i64)
        .bind(cursor)
        .bind(chat_id)
        .bind(&id)
        .execute(&mut *connection)
        .await?;
        if updated.rows_affected() == 0 {
            insert_item_in(connection, chat_id, next_seq, cursor, item).await?;
            next_seq += 1;
        }
    }
    Ok(())
}

/// Keeps the tab payload's provider identity and model in step with the chat.
async fn sync_tab_payload_in(
    connection: &mut SqliteConnection,
    tab_id: &str,
    snapshot: &AgentChatSnapshot,
) -> Result<()> {
    sqlx::query(
        "UPDATE workspaceTabs SET payloadJson = json_set(payloadJson, '$.provider', ?1, \
         '$.providerInstanceId', ?2) WHERE id = ?3 AND kind = 'agentChat' \
         AND (json_extract(payloadJson, '$.provider') IS NOT ?1 \
         OR json_extract(payloadJson, '$.providerInstanceId') IS NOT ?2)",
    )
    .bind(&snapshot.provider)
    .bind(&snapshot.provider_instance_id)
    .bind(tab_id)
    .execute(&mut *connection)
    .await?;
    match &snapshot.session.model {
        Some(model) => {
            sqlx::query(
                "UPDATE workspaceTabs SET payloadJson = json_set(payloadJson, '$.model', ?1) \
                 WHERE id = ?2 AND kind = 'agentChat' AND json_extract(payloadJson, '$.model') IS NOT ?1",
            )
            .bind(model)
            .bind(tab_id)
            .execute(&mut *connection)
            .await?;
        }
        None => {
            sqlx::query(
                "UPDATE workspaceTabs SET payloadJson = json_remove(payloadJson, '$.model') \
                 WHERE id = ? AND kind = 'agentChat' AND json_type(payloadJson, '$.model') IS NOT NULL",
            )
            .bind(tab_id)
            .execute(&mut *connection)
            .await?;
        }
    }
    Ok(())
}

/// Commits `snapshot` and `delta` on top of `row`, which the caller loaded
/// in this transaction and whose cursor it has already checked.
pub(super) async fn commit_in(
    connection: &mut SqliteConnection,
    row: &SessionRow,
    snapshot: AgentChatSnapshot,
    delta: AgentChatDelta,
    receipt: Option<&AgentChatReceipt>,
) -> Result<AgentChatEvent> {
    let cursor = row.cursor + 1;
    if snapshot.cursor != cursor {
        return Err(invalid(format!("snapshot cursor must be {cursor}")));
    }
    if snapshot.chat_id != row.chat_id
        || snapshot.workspace_id != row.workspace_id
        || snapshot.tab_id != row.tab_id
    {
        return Err(invalid("snapshot identity must match the chat"));
    }
    let stored = parse_header(&row.snapshot_json)?;
    let provider = delta
        .provider
        .clone()
        .unwrap_or_else(|| row.provider.clone());
    let instance = delta
        .provider_instance_id
        .clone()
        .unwrap_or_else(|| row.provider_instance_id.clone());
    if snapshot.provider != provider || snapshot.provider_instance_id != instance {
        return Err(invalid("a provider change must travel in the delta"));
    }
    let switching = provider != row.provider || instance != row.provider_instance_id;
    if switching {
        require_switch_allowed(connection, &row.chat_id, &stored).await?;
    }
    require_field(
        "session",
        &stored.session,
        &snapshot.session,
        delta.session.as_ref(),
    )?;
    require_field(
        "pendingRequests",
        &stored.pending_requests,
        &snapshot.pending_requests,
        delta.requests.as_ref(),
    )?;
    require_field(
        "title",
        &stored.title,
        &snapshot.title,
        delta.title.as_ref(),
    )?;
    require_field(
        "usage",
        &stored.usage,
        &snapshot.usage,
        delta.usage.as_ref(),
    )?;
    require_field(
        "recovery",
        &stored.recovery,
        &snapshot.recovery,
        delta.recovery.as_ref(),
    )?;
    require_turn_changes_in(
        connection,
        &row.chat_id,
        &snapshot.turns,
        delta.turns.as_ref(),
    )
    .await?;
    require_extra(&stored.extra, &snapshot.extra, &delta.extra)?;

    write_turns_in(
        connection,
        &row.chat_id,
        cursor,
        delta.turns.as_deref().unwrap_or_default(),
    )
    .await?;
    write_items_in(connection, &row.chat_id, cursor, &delta).await?;
    let header = header_json(&snapshot)?;
    require_snapshot_budget_in(connection, &row.chat_id, &snapshot, header.len()).await?;
    let now = format_timestamp(Utc::now());
    let generation = row.generation + i64::from(switching);
    sqlx::query(
        "UPDATE agentChatSessions SET provider = ?, providerInstanceId = ?, generation = ?, \
         nativeThreadId = CASE WHEN ? THEN NULL ELSE nativeThreadId END, cursor = ?, \
         snapshotJson = ?, updatedAt = ? WHERE chatId = ? AND cursor = ?",
    )
    .bind(&provider)
    .bind(&instance)
    .bind(generation)
    .bind(switching)
    .bind(cursor)
    .bind(&header)
    .bind(&now)
    .bind(&row.chat_id)
    .bind(row.cursor)
    .execute(&mut *connection)
    .await?;
    if !row.archived {
        sync_tab_payload_in(connection, &row.tab_id, &snapshot).await?;
    }
    let delta_json = serde_json::to_value(&delta)?;
    sqlx::query(
        "INSERT INTO agentChatEvents (chatId, cursor, deltaJson, occurredAt) VALUES (?, ?, ?, ?)",
    )
    .bind(&row.chat_id)
    .bind(cursor)
    .bind(serde_json::to_string(&delta_json)?)
    .bind(&now)
    .execute(&mut *connection)
    .await?;
    sqlx::query("DELETE FROM agentChatEvents WHERE chatId = ? AND cursor <= ?")
        .bind(&row.chat_id)
        .bind(cursor - AGENT_CHAT_EVENT_RETENTION)
        .execute(&mut *connection)
        .await?;
    if let Some(receipt) = receipt {
        insert_receipt_in(connection, Some(&row.chat_id), Some(cursor), receipt).await?;
    }
    Ok(AgentChatEvent {
        chat_id: row.chat_id.clone(),
        cursor,
        delta: delta_json,
        occurred_at: now,
    })
}

impl RuntimeStore {
    /// Commits the host's projection at `expected_cursor + 1`. A receipt that
    /// was already recorded replays (or conflicts) before the cursor is
    /// checked, so a retry after a lost response still gets its answer.
    pub async fn commit_agent_chat(
        &self,
        chat_id: &str,
        expected_cursor: i64,
        snapshot: &Value,
        delta: &Value,
        receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatCommitOutcome> {
        let snapshot = parse_snapshot(snapshot)?;
        let delta = parse_delta(delta)?;
        if let Some(receipt) = receipt {
            require_receipt(receipt)?;
        }
        // A WAL snapshot cannot upgrade to a writer after another client commits.
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        if let Some(receipt) = receipt {
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
                    return Ok(AgentChatCommitOutcome::Replay(value));
                }
                AgentChatReceiptCheck::Conflict => {
                    tx.commit().await?;
                    return Ok(AgentChatCommitOutcome::ReceiptConflict);
                }
            }
        }
        let row = require_session_row_in(&mut tx, chat_id).await?;
        if row.cursor != expected_cursor {
            tx.commit().await?;
            return Ok(AgentChatCommitOutcome::CursorConflict {
                current: row.cursor,
            });
        }
        let event = commit_in(&mut tx, &row, snapshot, delta, receipt).await?;
        tx.commit().await?;
        Ok(AgentChatCommitOutcome::Committed(event))
    }

    /// The stored item, for a host that needs to rebuild its in-memory
    /// projection of one entry.
    pub async fn agent_chat_item(&self, chat_id: &str, item_id: &str) -> Result<Option<Value>> {
        let row =
            sqlx::query("SELECT itemJson FROM agentChatItems WHERE chatId = ? AND itemId = ?")
                .bind(chat_id)
                .bind(item_id)
                .fetch_optional(self.pool())
                .await?;
        row.map(|row| Ok(serde_json::from_str(row.try_get::<&str, _>("itemJson")?)?))
            .transpose()
    }
}

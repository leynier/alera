use anyhow::Result;
use chrono::Utc;
use serde_json::Value;
use sqlx::{Row, SqliteConnection};

use super::agent_chat_models::*;
use super::agent_chat_projection::{item_page_in, projected_snapshot_in, ItemPageBudget};
use super::agent_chat_receipts::{check_receipt_in, insert_receipt_in, require_receipt};
use super::agent_chat_turns::write_turns_in;
use super::agent_chat_validation::*;
use super::{format_timestamp, parse_timestamp, RuntimeStore, WorkspaceTabRecord};

pub(super) const SESSION_COLUMNS: &str = "chatId, workspaceId, tabId, providerInstanceId, \
     provider, nativeThreadId, generation, archived, archivedAt, cursor, snapshotJson, \
     metadataJson, createdAt, updatedAt";

/// A session row with its header still unparsed.
#[derive(Debug, Clone)]
pub(super) struct SessionRow {
    pub chat_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub provider_instance_id: String,
    pub provider: String,
    pub native_thread_id: Option<String>,
    pub generation: i64,
    pub archived: bool,
    pub archived_at: Option<String>,
    pub cursor: i64,
    pub snapshot_json: String,
    pub metadata_json: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

impl SessionRow {
    fn from_row(row: sqlx::sqlite::SqliteRow) -> Result<Self> {
        Ok(Self {
            chat_id: row.try_get("chatId")?,
            workspace_id: row.try_get("workspaceId")?,
            tab_id: row.try_get("tabId")?,
            provider_instance_id: row.try_get("providerInstanceId")?,
            provider: row.try_get("provider")?,
            native_thread_id: row.try_get("nativeThreadId")?,
            generation: row.try_get("generation")?,
            archived: row.try_get::<i64, _>("archived")? != 0,
            archived_at: row.try_get("archivedAt")?,
            cursor: row.try_get("cursor")?,
            snapshot_json: row.try_get("snapshotJson")?,
            metadata_json: row.try_get("metadataJson")?,
            created_at: row.try_get("createdAt")?,
            updated_at: row.try_get("updatedAt")?,
        })
    }

    pub(super) fn into_record(self, snapshot: Value) -> AgentChatRecord {
        AgentChatRecord {
            chat_id: self.chat_id,
            tab_id: self.tab_id,
            workspace_id: self.workspace_id,
            provider_instance_id: self.provider_instance_id,
            provider: self.provider,
            native_thread_id: self.native_thread_id,
            generation: self.generation,
            archived: self.archived,
            archived_at: self.archived_at.as_deref().map(parse_timestamp),
            cursor: self.cursor,
            created_at: parse_timestamp(&self.created_at),
            updated_at: parse_timestamp(&self.updated_at),
            metadata: self
                .metadata_json
                .as_deref()
                .and_then(|json| serde_json::from_str(json).ok()),
            snapshot,
        }
    }
}

pub(super) async fn session_row_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
) -> Result<Option<SessionRow>> {
    let row = sqlx::query(sqlx::AssertSqlSafe(format!(
        "SELECT {SESSION_COLUMNS} FROM agentChatSessions WHERE chatId = ?"
    )))
    .bind(chat_id)
    .fetch_optional(&mut *connection)
    .await?;
    row.map(SessionRow::from_row).transpose()
}

pub(super) async fn require_session_row_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
) -> Result<SessionRow> {
    session_row_in(connection, chat_id)
        .await?
        .ok_or_else(|| AgentChatStoreError::NotFound(chat_id.to_string()).into())
}

pub(super) async fn full_snapshot_in(
    connection: &mut SqliteConnection,
    row: &SessionRow,
) -> Result<Value> {
    projected_snapshot_in(connection, row, true).await
}

pub(super) async fn insert_item_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    seq: i64,
    cursor: i64,
    item: &AgentChatItem,
) -> Result<()> {
    let json = item_json(item)?;
    sqlx::query(
        "INSERT INTO agentChatItems (chatId, itemId, seq, turnId, itemJson, byteSize, updatedCursor) \
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(chat_id)
    .bind(&item.item_id)
    .bind(seq)
    .bind(&item.turn_id)
    .bind(&json)
    .bind(json.len() as i64)
    .bind(cursor)
    .execute(&mut *connection)
    .await?;
    Ok(())
}

pub(super) async fn insert_tab_in(
    connection: &mut SqliteConnection,
    tab: &WorkspaceTabRecord,
) -> Result<()> {
    let result = sqlx::query(
        "INSERT INTO workspaceTabs (id, workspaceId, kind, title, createdAt, updatedAt, payloadJson) \
         VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING",
    )
    .bind(&tab.id)
    .bind(&tab.workspace_id)
    .bind(&tab.kind)
    .bind(&tab.title)
    .bind(format_timestamp(tab.created_at))
    .bind(format_timestamp(tab.updated_at))
    .bind(serde_json::to_string(&tab.payload)?)
    .execute(&mut *connection)
    .await?;
    if result.rows_affected() == 0 {
        anyhow::bail!(AgentChatStoreError::AlreadyExists(format!(
            "tab {}",
            tab.id
        )));
    }
    Ok(())
}

pub(super) async fn require_workspace_in(
    connection: &mut SqliteConnection,
    workspace_id: &str,
) -> Result<()> {
    let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workspaces WHERE id = ?)")
        .bind(workspace_id)
        .fetch_one(&mut *connection)
        .await?;
    if !exists {
        anyhow::bail!(AgentChatStoreError::Invalid(format!(
            "workspace not found: {workspace_id}"
        )));
    }
    Ok(())
}

pub(super) fn require_new_record(
    record: &AgentChatRecord,
    snapshot: &AgentChatSnapshot,
) -> Result<()> {
    require_chat_id(&record.chat_id)?;
    require_id("tabId", &record.tab_id)?;
    require_id("workspaceId", &record.workspace_id)?;
    require_id("provider", &record.provider)?;
    require_id("providerInstanceId", &record.provider_instance_id)?;
    if let Some(native) = &record.native_thread_id {
        require_id("nativeThreadId", native)?;
        if record.provider == super::AGENT_CHAT_UNSELECTED_PROVIDER {
            return Err(AgentChatStoreError::Invalid(
                "an unselected draft cannot have a native thread".into(),
            )
            .into());
        }
    }
    let invalid = |message: &str| -> anyhow::Error {
        AgentChatStoreError::Invalid(message.to_string()).into()
    };
    if record.generation != 1 || record.cursor != 0 || record.archived {
        return Err(invalid(
            "a new chat starts at generation 1, cursor 0, and open",
        ));
    }
    if snapshot.cursor != 0
        || snapshot.chat_id != record.chat_id
        || snapshot.tab_id != record.tab_id
        || snapshot.workspace_id != record.workspace_id
        || snapshot.provider != record.provider
        || snapshot.provider_instance_id != record.provider_instance_id
    {
        return Err(invalid(
            "snapshot identity must match the chat record at cursor 0",
        ));
    }
    Ok(())
}

impl RuntimeStore {
    /// Creates the chat, its `agentChat` tab, its initial items, and the
    /// optional command receipt in one transaction.
    pub async fn create_agent_chat(
        &self,
        record: &AgentChatRecord,
        tab: &WorkspaceTabRecord,
        receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatCreateOutcome> {
        let snapshot = parse_snapshot(&record.snapshot)?;
        require_new_record(record, &snapshot)?;
        require_tab(record, tab)?;
        let header = header_json(&snapshot)?;
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
                    return Ok(AgentChatCreateOutcome::Replay(value));
                }
                AgentChatReceiptCheck::Conflict => {
                    tx.commit().await?;
                    return Ok(AgentChatCreateOutcome::ReceiptConflict);
                }
            }
        }
        if session_row_in(&mut tx, &record.chat_id).await?.is_some() {
            anyhow::bail!(AgentChatStoreError::AlreadyExists(record.chat_id.clone()));
        }
        require_workspace_in(&mut tx, &record.workspace_id).await?;
        insert_tab_in(&mut tx, tab).await?;
        let now = format_timestamp(Utc::now());
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "INSERT INTO agentChatSessions ({SESSION_COLUMNS}) \
             VALUES (?, ?, ?, ?, ?, ?, 1, 0, NULL, 0, ?, ?, ?, ?)"
        )))
        .bind(&record.chat_id)
        .bind(&record.workspace_id)
        .bind(&record.tab_id)
        .bind(&record.provider_instance_id)
        .bind(&record.provider)
        .bind(&record.native_thread_id)
        .bind(&header)
        .bind(metadata_json(record.metadata.as_ref())?)
        .bind(&now)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
        write_turns_in(&mut tx, &record.chat_id, 0, &snapshot.turns).await?;
        let mut seen = std::collections::BTreeSet::new();
        for (index, item) in snapshot.items.iter().enumerate() {
            if !seen.insert(item.item_id.as_str()) {
                anyhow::bail!(AgentChatStoreError::Invalid(format!(
                    "duplicate itemId {}",
                    item.item_id
                )));
            }
            insert_item_in(&mut tx, &record.chat_id, index as i64 + 1, 0, item).await?;
        }
        if let Some(receipt) = receipt {
            insert_receipt_in(&mut tx, Some(&record.chat_id), Some(0), receipt).await?;
        }
        let row = require_session_row_in(&mut tx, &record.chat_id).await?;
        let snapshot = full_snapshot_in(&mut tx, &row).await?;
        tx.commit().await?;
        Ok(AgentChatCreateOutcome::Created(Box::new(
            row.into_record(snapshot),
        )))
    }

    /// The chat with the newest page of items in its snapshot.
    pub async fn agent_chat(&self, chat_id: &str) -> Result<Option<AgentChatRecord>> {
        let mut tx = self.pool().begin().await?;
        let Some(row) = session_row_in(&mut tx, chat_id).await? else {
            return Ok(None);
        };
        let snapshot = full_snapshot_in(&mut tx, &row).await?;
        tx.commit().await?;
        Ok(Some(row.into_record(snapshot)))
    }

    /// The open chat shown by a tab.
    pub async fn agent_chat_for_tab(&self, tab_id: &str) -> Result<Option<AgentChatRecord>> {
        let chat_id: Option<String> = sqlx::query_scalar(
            "SELECT chatId FROM agentChatSessions WHERE tabId = ? AND archived = 0",
        )
        .bind(tab_id)
        .fetch_optional(self.pool())
        .await?;
        match chat_id {
            Some(chat_id) => self.agent_chat(&chat_id).await,
            None => Ok(None),
        }
    }

    /// Chats in a workspace, newest first. Snapshots are headers: `items`
    /// stays empty so a listing never loads transcripts.
    pub async fn list_agent_chats(
        &self,
        workspace_id: &str,
        include_archived: bool,
    ) -> Result<Vec<AgentChatRecord>> {
        let mut tx = self.pool().begin().await?;
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {SESSION_COLUMNS} FROM agentChatSessions \
             WHERE workspaceId = ? AND (archived = 0 OR ?) ORDER BY updatedAt DESC, chatId"
        )))
        .bind(workspace_id)
        .bind(include_archived)
        .fetch_all(&mut *tx)
        .await?;
        let mut chats = Vec::new();
        for row in rows {
            let row = SessionRow::from_row(row)?;
            let snapshot = projected_snapshot_in(&mut tx, &row, false).await?;
            chats.push(row.into_record(snapshot));
        }
        tx.commit().await?;
        Ok(chats)
    }

    /// All chats, newest first, without loading transcript items.
    pub async fn list_all_agent_chats(
        &self,
        include_archived: bool,
    ) -> Result<Vec<AgentChatRecord>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {SESSION_COLUMNS} FROM agentChatSessions \
             WHERE (archived = 0 OR ?) ORDER BY updatedAt DESC, chatId"
        )))
        .bind(include_archived)
        .fetch_all(self.pool())
        .await?;
        let mut tx = self.pool().begin().await?;
        let mut chats = Vec::with_capacity(rows.len());
        for row in rows {
            let row = SessionRow::from_row(row)?;
            let snapshot = projected_snapshot_in(&mut tx, &row, false).await?;
            chats.push(row.into_record(snapshot));
        }
        tx.commit().await?;
        Ok(chats)
    }

    /// Items older than `before` (a `historyBefore` value), oldest first.
    pub async fn agent_chat_history(
        &self,
        chat_id: &str,
        before: i64,
        limit: i64,
    ) -> Result<AgentChatHistoryPage> {
        let mut tx = self.pool().begin().await?;
        require_session_row_in(&mut tx, chat_id).await?;
        let page = item_page_in(
            &mut tx,
            chat_id,
            Some(before),
            limit,
            ItemPageBudget::history(),
        )
        .await?;
        tx.commit().await?;
        Ok(AgentChatHistoryPage {
            chat_id: chat_id.to_string(),
            items: page.items,
            turns: page.turns,
            history_before: page.history_before,
        })
    }

    /// Deltas committed after `after`, within one page.
    pub async fn agent_chat_events(
        &self,
        chat_id: &str,
        after: i64,
        limit: i64,
    ) -> Result<AgentChatEventPage> {
        let limit = limit.clamp(1, AGENT_CHAT_EVENT_PAGE_MAX);
        let mut tx = self.pool().begin().await?;
        let row = require_session_row_in(&mut tx, chat_id).await?;
        let oldest: Option<i64> =
            sqlx::query_scalar("SELECT MIN(cursor) FROM agentChatEvents WHERE chatId = ?")
                .bind(chat_id)
                .fetch_one(&mut *tx)
                .await?;
        let behind_journal = after < row.cursor && oldest.is_none_or(|oldest| after + 1 < oldest);
        if after < 0 || after > row.cursor || behind_journal {
            tx.commit().await?;
            return Ok(AgentChatEventPage {
                chat_id: chat_id.to_string(),
                events: Vec::new(),
                cursor: row.cursor,
                has_more: false,
                snapshot_required: true,
            });
        }
        let rows = sqlx::query(
            "SELECT cursor, deltaJson, occurredAt FROM agentChatEvents \
             WHERE chatId = ? AND cursor > ? ORDER BY cursor ASC LIMIT ?",
        )
        .bind(chat_id)
        .bind(after)
        .bind(limit)
        .fetch_all(&mut *tx)
        .await?;
        tx.commit().await?;
        let mut events = Vec::new();
        let mut budget = 0_usize;
        let host_cursor = row.cursor;
        for row in rows {
            let json: String = row.try_get("deltaJson")?;
            let delta: Value = serde_json::from_str(&json)?;
            if delta.get("snapshotRequired").and_then(Value::as_bool) == Some(true) {
                return Ok(AgentChatEventPage {
                    chat_id: chat_id.to_string(),
                    events: Vec::new(),
                    cursor: host_cursor,
                    has_more: false,
                    snapshot_required: true,
                });
            }
            if !events.is_empty() && budget + json.len() > AGENT_CHAT_PAGE_MAX_BYTES {
                break;
            }
            budget += json.len();
            events.push(AgentChatEvent {
                chat_id: chat_id.to_string(),
                cursor: row.try_get("cursor")?,
                delta,
                occurred_at: row.try_get("occurredAt")?,
            });
        }
        let cursor = events.last().map_or(after, |event| event.cursor);
        Ok(AgentChatEventPage {
            chat_id: chat_id.to_string(),
            events,
            cursor,
            has_more: cursor < row.cursor,
            snapshot_required: false,
        })
    }
}

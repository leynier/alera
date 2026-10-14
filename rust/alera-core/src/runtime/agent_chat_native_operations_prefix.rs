//! One durable prefix-removal engine for transcript and native rewind.

use anyhow::Result;
use chrono::Utc;
use serde_json::{json, Value};
use sqlx::{Row, SqliteConnection};

use super::validation::invalid;
use crate::runtime::agent_chat_store::{full_snapshot_in, require_session_row_in, SessionRow};
use crate::runtime::agent_chat_validation::{header_json, metadata_json, parse_header, require_id};
use crate::runtime::{
    format_timestamp, AgentChatEvent, AgentChatRecord, AgentChatSessionStatus, AgentChatSnapshot,
};

pub(in crate::runtime) async fn target_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    turn_id: &str,
) -> Result<(i64, i64, i64)> {
    require_id("turnId", turn_id)?;
    let turn =
        sqlx::query("SELECT seq, status FROM agentChatTurns WHERE chatId = ? AND turnId = ?")
            .bind(chat_id)
            .bind(turn_id)
            .fetch_optional(&mut *connection)
            .await?
            .ok_or_else(|| invalid("selected turn not found"))?;
    let status: String = turn.try_get("status")?;
    if !matches!(
        status.as_str(),
        "completed" | "failed" | "interrupted" | "cancelled"
    ) {
        return Err(invalid("history mutations require a settled target turn"));
    }
    let bounds = sqlx::query("SELECT MIN(seq) AS first, MAX(seq) AS last FROM agentChatItems WHERE chatId = ? AND turnId = ?")
        .bind(chat_id).bind(turn_id).fetch_one(&mut *connection).await?;
    Ok((
        turn.try_get("seq")?,
        bounds
            .try_get::<Option<i64>, _>("first")?
            .ok_or_else(|| invalid("selected turn has no transcript"))?,
        bounds
            .try_get::<Option<i64>, _>("last")?
            .ok_or_else(|| invalid("selected turn has no transcript"))?,
    ))
}

pub(in crate::runtime) async fn prompt_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    turn_id: &str,
) -> Result<Value> {
    let prompts: Vec<String> = sqlx::query_scalar(
        "SELECT itemJson FROM agentChatItems WHERE chatId = ? AND turnId = ? \
        AND json_extract(itemJson, '$.type') = 'user_message' ORDER BY seq LIMIT 2",
    )
    .bind(chat_id)
    .bind(turn_id)
    .fetch_all(&mut *connection)
    .await?;
    if prompts.len() != 1 {
        return Err(invalid(
            "rewind requires exactly one user message in the selected turn",
        ));
    }
    Ok(serde_json::from_str(&prompts[0])?)
}

pub(in crate::runtime) fn require_rewind_header(snapshot: &AgentChatSnapshot) -> Result<()> {
    if !snapshot.items.is_empty()
        || !snapshot.turns.is_empty()
        || !snapshot.pending_requests.is_empty()
        || snapshot.session.status != AgentChatSessionStatus::Stopped
        || snapshot.session.active_turn_id.is_some()
        || snapshot.recovery.is_some()
        || snapshot.usage.is_some()
        || ["queue", "queuedMessages"].iter().any(|key| {
            snapshot
                .extra
                .get(*key)
                .and_then(Value::as_array)
                .is_some_and(|queue| !queue.is_empty())
        })
    {
        return Err(invalid("rewind requires a stopped header without history projections, requests, usage, or recovery"));
    }
    Ok(())
}

fn require_context(row: &SessionRow, snapshot: &AgentChatSnapshot) -> Result<()> {
    let old = parse_header(&row.snapshot_json)?;
    if row.archived
        || !old.pending_requests.is_empty()
        || old.session.active_turn_id.is_some()
        || matches!(
            old.session.status,
            AgentChatSessionStatus::Starting
                | AgentChatSessionStatus::Running
                | AgentChatSessionStatus::Waiting
        )
        || ["queue", "queuedMessages"].iter().any(|key| {
            old.extra
                .get(*key)
                .and_then(Value::as_array)
                .is_some_and(|queue| !queue.is_empty())
        })
    {
        return Err(invalid(
            "rewind requires an open idle chat without pending requests",
        ));
    }
    if snapshot.chat_id != row.chat_id
        || snapshot.workspace_id != row.workspace_id
        || snapshot.tab_id != row.tab_id
        || snapshot.provider != row.provider
        || snapshot.provider_instance_id != row.provider_instance_id
        || snapshot.cursor
            != row
                .cursor
                .checked_add(1)
                .ok_or_else(|| invalid("chat cursor exhausted"))?
    {
        return Err(invalid(
            "rewind header identity and next cursor must match the chat",
        ));
    }
    Ok(())
}

pub(in crate::runtime) async fn reset_context_in(
    connection: &mut SqliteConnection,
    row: &SessionRow,
    mut snapshot: AgentChatSnapshot,
    native_thread_id: Option<&str>,
    reason: &str,
) -> Result<(AgentChatRecord, AgentChatEvent)> {
    require_rewind_header(&snapshot)?;
    require_context(row, &snapshot)?;
    let now = format_timestamp(Utc::now());
    let generation = row
        .generation
        .checked_add(1)
        .ok_or_else(|| invalid("chat generation exhausted"))?;
    snapshot
        .session
        .extra
        .insert("generation".into(), json!(generation));
    snapshot
        .extra
        .insert("pendingNativeOperation".into(), Value::Null);
    snapshot.extra.remove("nativeOperationReconcile");
    let mut metadata = row
        .metadata_json
        .as_deref()
        .map(serde_json::from_str::<Value>)
        .transpose()?;
    if let Some(object) = metadata.as_mut().and_then(Value::as_object_mut) {
        object.remove("nativeFork");
        object.remove("nativeHistory");
    }
    sqlx::query("DELETE FROM agentChatNativeIds WHERE chatId = ?")
        .bind(&row.chat_id)
        .execute(&mut *connection)
        .await?;
    sqlx::query("DELETE FROM agentChatEvents WHERE chatId = ?")
        .bind(&row.chat_id)
        .execute(&mut *connection)
        .await?;
    sqlx::query("UPDATE agentChatSessions SET generation = ?, nativeThreadId = ?, cursor = ?, snapshotJson = ?, metadataJson = ?, updatedAt = ? WHERE chatId = ?")
        .bind(generation).bind(native_thread_id).bind(snapshot.cursor).bind(header_json(&snapshot)?)
        .bind(metadata_json(metadata.as_ref())?).bind(&now).bind(&row.chat_id).execute(&mut *connection).await?;
    sqlx::query("UPDATE chatOrchestrationCredentials SET revokedAt = ?, revokeReason = 'rewound' WHERE chatId = ? AND revokedAt IS NULL")
        .bind(&now).bind(&row.chat_id).execute(&mut *connection).await?;
    let event = AgentChatEvent {
        chat_id: row.chat_id.clone(),
        cursor: snapshot.cursor,
        delta: json!({"snapshotRequired": true, "reason": reason}),
        occurred_at: now.clone(),
    };
    sqlx::query(
        "INSERT INTO agentChatEvents (chatId, cursor, deltaJson, occurredAt) VALUES (?, ?, ?, ?)",
    )
    .bind(&row.chat_id)
    .bind(event.cursor)
    .bind(serde_json::to_string(&event.delta)?)
    .bind(&now)
    .execute(&mut *connection)
    .await?;
    let updated = require_session_row_in(connection, &row.chat_id).await?;
    let snapshot = full_snapshot_in(connection, &updated).await?;
    Ok((updated.into_record(snapshot), event))
}

pub(in crate::runtime) async fn rewind_in(
    connection: &mut SqliteConnection,
    row: &SessionRow,
    turn_id: &str,
    snapshot: AgentChatSnapshot,
    native_thread_id: Option<&str>,
) -> Result<(AgentChatRecord, AgentChatEvent, Value)> {
    require_rewind_header(&snapshot)?;
    require_context(row, &snapshot)?;
    let (turn_seq, item_seq, _) = target_in(connection, &row.chat_id, turn_id).await?;
    let prompt = prompt_in(connection, &row.chat_id, turn_id).await?;
    let now = format_timestamp(Utc::now());
    // Delayed old sends cannot become new turns after truncation.
    sqlx::query(
        "INSERT INTO agentChatCancelledMessages (chatId, clientMessageId, cancelledAt) \
        SELECT chatId, json_extract(itemJson, '$.clientMessageId'), ? FROM agentChatItems \
        WHERE chatId = ? AND seq >= ? AND json_type(itemJson, '$.clientMessageId') = 'text' \
        ON CONFLICT(chatId, clientMessageId) DO NOTHING",
    )
    .bind(&now)
    .bind(&row.chat_id)
    .bind(item_seq)
    .execute(&mut *connection)
    .await?;
    sqlx::query(
        "DELETE FROM agentChatItems WHERE chatId = ? AND (seq >= ? OR turnId IN \
        (SELECT turnId FROM agentChatTurns WHERE chatId = ? AND seq >= ?))",
    )
    .bind(&row.chat_id)
    .bind(item_seq)
    .bind(&row.chat_id)
    .bind(turn_seq)
    .execute(&mut *connection)
    .await?;
    sqlx::query("DELETE FROM agentChatTurns WHERE chatId = ? AND seq >= ?")
        .bind(&row.chat_id)
        .bind(turn_seq)
        .execute(&mut *connection)
        .await?;
    let (record, event) =
        reset_context_in(connection, row, snapshot, native_thread_id, "rewind").await?;
    Ok((record, event, prompt))
}

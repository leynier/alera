//! Durable turn rows. A snapshot is a view of these rows, never their owner.

use std::collections::BTreeMap;

use anyhow::Result;
use serde_json::Value;
use sqlx::{Row, SqliteConnection};

use super::agent_chat_models::*;
use super::agent_chat_validation::{parse_header, turn_json};
use super::RuntimeStore;

pub(super) async fn stored_turn_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    turn_id: &str,
) -> Result<Option<AgentChatTurn>> {
    let json: Option<String> =
        sqlx::query_scalar("SELECT turnJson FROM agentChatTurns WHERE chatId = ? AND turnId = ?")
            .bind(chat_id)
            .bind(turn_id)
            .fetch_optional(&mut *connection)
            .await?;
    json.map(|json| Ok(serde_json::from_str(&json)?))
        .transpose()
}

fn changed_turn_json(turn: &AgentChatTurn, stored: Option<&AgentChatTurn>) -> Result<String> {
    match turn_json(turn) {
        Ok(json) => Ok(json),
        Err(error) => {
            let Some(stored) = stored else {
                return Err(error);
            };
            let previous = serde_json::to_string(stored)?;
            let json = serde_json::to_string(turn)?;
            // Old headers could carry larger metadata. Lifecycle updates
            // must still settle those turns without trimming their fields.
            if previous.len() > AGENT_CHAT_TURN_MAX_BYTES
                && stored.extra == turn.extra
                && json.len() <= previous.len() + 1024
            {
                super::agent_chat_validation::require_turn(turn)?;
                Ok(json)
            } else {
                Err(error)
            }
        }
    }
}

pub(super) async fn write_turns_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    cursor: i64,
    turns: &[AgentChatTurn],
) -> Result<()> {
    let mut next_seq: i64 =
        sqlx::query_scalar("SELECT COALESCE(MAX(seq), 0) + 1 FROM agentChatTurns WHERE chatId = ?")
            .bind(chat_id)
            .fetch_one(&mut *connection)
            .await?;
    for turn in turns {
        let stored = stored_turn_in(connection, chat_id, &turn.turn_id).await?;
        if stored.as_ref() == Some(turn) {
            continue;
        }
        let json = changed_turn_json(turn, stored.as_ref())?;
        sqlx::query(
            "INSERT INTO agentChatTurns (chatId, turnId, seq, status, turnJson, byteSize, updatedCursor) \
             VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(chatId, turnId) DO UPDATE SET \
             status = excluded.status, turnJson = excluded.turnJson, byteSize = excluded.byteSize, \
             updatedCursor = excluded.updatedCursor",
        )
        .bind(chat_id)
        .bind(&turn.turn_id)
        .bind(next_seq)
        .bind(&turn.status)
        .bind(&json)
        .bind(json.len() as i64)
        .bind(cursor)
        .execute(&mut *connection)
        .await?;
        next_seq += 1;
    }
    Ok(())
}

/// Omission from the snapshot changes only its projection. Every supplied
/// turn must still equal its durable row or an explicit delta upsert.
pub(super) async fn require_turn_changes_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    committed: &[AgentChatTurn],
    delta: Option<&Vec<AgentChatTurn>>,
) -> Result<()> {
    let invalid = |message: String| AgentChatStoreError::Invalid(message);
    let mut changed = BTreeMap::new();
    for turn in delta.into_iter().flatten() {
        let stored = stored_turn_in(connection, chat_id, &turn.turn_id).await?;
        if stored.as_ref() != Some(turn) {
            changed_turn_json(turn, stored.as_ref())?;
        }
        if changed.insert(turn.turn_id.as_str(), turn).is_some() {
            return Err(invalid(format!("delta repeats turn {}", turn.turn_id)).into());
        }
    }
    for turn in committed {
        if let Some(expected) = changed.get(turn.turn_id.as_str()) {
            if *expected != turn {
                return Err(invalid(format!(
                    "delta turn {} differs from the snapshot",
                    turn.turn_id
                ))
                .into());
            }
        } else if stored_turn_in(connection, chat_id, &turn.turn_id)
            .await?
            .as_ref()
            != Some(turn)
        {
            return Err(invalid(format!(
                "turn {} changed without a delta entry",
                turn.turn_id
            ))
            .into());
        }
    }
    Ok(())
}

/// Move unreleased snapshot headers into rows without creating journal
/// changes. The transaction makes a crash or a repeated startup harmless.
pub(super) async fn migrate_turn_headers_in(connection: &mut SqliteConnection) -> Result<()> {
    let rows = sqlx::query(
        "SELECT chatId, cursor, snapshotJson FROM agentChatSessions \
         WHERE json_array_length(snapshotJson, '$.turns') > 0",
    )
    .fetch_all(&mut *connection)
    .await?;
    for row in rows {
        let chat_id: String = row.try_get("chatId")?;
        let cursor: i64 = row.try_get("cursor")?;
        let header: String = row.try_get("snapshotJson")?;
        let snapshot = parse_header(&header)?;
        let mut next_seq: i64 = sqlx::query_scalar(
            "SELECT COALESCE(MAX(seq), 0) + 1 FROM agentChatTurns WHERE chatId = ?",
        )
        .bind(&chat_id)
        .fetch_one(&mut *connection)
        .await?;
        for turn in &snapshot.turns {
            // Existing metadata predates the per-turn bound and remains intact.
            let json = serde_json::to_string(turn)?;
            sqlx::query(
                "INSERT INTO agentChatTurns (chatId, turnId, seq, status, turnJson, byteSize, updatedCursor) \
                 VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(chatId, turnId) DO NOTHING",
            )
            .bind(&chat_id)
            .bind(&turn.turn_id)
            .bind(next_seq)
            .bind(&turn.status)
            .bind(&json)
            .bind(json.len() as i64)
            .bind(cursor)
            .execute(&mut *connection)
            .await?;
            next_seq += 1;
        }
        sqlx::query(
            "UPDATE agentChatSessions SET snapshotJson = json_remove(snapshotJson, '$.turns') \
             WHERE chatId = ?",
        )
        .bind(&chat_id)
        .execute(&mut *connection)
        .await?;
    }
    Ok(())
}

impl RuntimeStore {
    /// The turn that actually consumed this client message. Queued input
    /// has no result until its durable user item is assigned a turn id.
    pub async fn agent_chat_turn_for_client_message(
        &self,
        chat_id: &str,
        client_message_id: &str,
    ) -> Result<Option<Value>> {
        let json: Option<String> = sqlx::query_scalar(
            "SELECT t.turnJson FROM agentChatItems i JOIN agentChatTurns t \
             ON t.chatId = i.chatId AND t.turnId = i.turnId \
             WHERE i.chatId = ? AND json_extract(i.itemJson, '$.clientMessageId') = ? \
             ORDER BY i.seq LIMIT 1",
        )
        .bind(chat_id)
        .bind(client_message_id)
        .fetch_optional(self.pool())
        .await?;
        json.map(|json| Ok(serde_json::from_str(&json)?))
            .transpose()
    }

    /// Durable metadata for any turn, including turns outside the snapshot.
    pub async fn agent_chat_turn(&self, chat_id: &str, turn_id: &str) -> Result<Option<Value>> {
        let json: Option<String> = sqlx::query_scalar(
            "SELECT turnJson FROM agentChatTurns WHERE chatId = ? AND turnId = ?",
        )
        .bind(chat_id)
        .bind(turn_id)
        .fetch_optional(self.pool())
        .await?;
        json.map(|json| Ok(serde_json::from_str(&json)?))
            .transpose()
    }
}

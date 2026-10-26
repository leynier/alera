//! Bounded transcript views over durable item and turn rows.

#[cfg(test)]
#[path = "agent_chat_projection_tests.rs"]
mod tests;

use std::collections::{btree_map::Entry, BTreeMap, BTreeSet};

use anyhow::Result;
use serde_json::Value;
use sqlx::{Row, SqliteConnection};

use super::agent_chat_models::*;
use super::agent_chat_store::SessionRow;

const SNAPSHOT_VIEW_MAX_BYTES: usize = 960 * 1024;

pub(super) struct ItemPage {
    pub items: Vec<Value>,
    pub turns: Vec<Value>,
    pub history_before: Option<i64>,
}

pub(super) struct ItemPageBudget {
    pub bytes: usize,
    pub turn_bytes: usize,
    pub hard_bytes: usize,
    pub known_turn_ids: BTreeSet<String>,
}

impl ItemPageBudget {
    pub fn history() -> Self {
        Self {
            bytes: AGENT_CHAT_PAGE_MAX_BYTES,
            turn_bytes: usize::MAX,
            hard_bytes: usize::MAX,
            known_turn_ids: BTreeSet::new(),
        }
    }
}

/// Item and matching turn bytes share the page budget. The first item is
/// always readable, including its complete turn metadata (normally at most
/// 320 KiB together). Existing larger turn rows remain readable as well.
pub(super) async fn item_page_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    before: Option<i64>,
    limit: i64,
    budget: ItemPageBudget,
) -> Result<ItemPage> {
    let limit = limit.clamp(1, AGENT_CHAT_PAGE_MAX_ITEMS);
    let sizes = sqlx::query(
        "SELECT i.seq, i.byteSize, i.turnId, COALESCE(t.byteSize, 0) AS turnBytes \
         FROM agentChatItems i LEFT JOIN agentChatTurns t ON t.chatId = i.chatId AND t.turnId = i.turnId \
         WHERE i.chatId = ? AND i.seq < ? AND NOT COALESCE(\
         json_extract(i.itemJson, '$.type') = 'payload' AND \
         json_type(i.itemJson, '$.normalized.hidden') = 'true', 0) \
         ORDER BY i.seq DESC LIMIT ?",
    )
    .bind(chat_id)
    .bind(before.unwrap_or(i64::MAX))
    .bind(limit + 1)
    .fetch_all(&mut *connection)
    .await?;
    let mut bytes = 0_usize;
    let mut item_bytes = 0_usize;
    let mut turn_ids = budget.known_turn_ids;
    let mut turn_bytes = 0_usize;
    let mut oldest = None;
    let mut taken = 0_i64;
    for row in &sizes {
        let size = row.try_get::<i64, _>("byteSize")? as usize;
        let turn_id: Option<String> = row.try_get("turnId")?;
        let turn_size = if turn_id.as_ref().is_some_and(|id| !turn_ids.contains(id)) {
            row.try_get::<i64, _>("turnBytes")? as usize
        } else {
            0
        };
        let grandfathered_first = taken == 0 && turn_size > AGENT_CHAT_TURN_MAX_BYTES;
        if bytes + size + turn_size > budget.hard_bytes
            || (!grandfathered_first && turn_bytes + turn_size > budget.turn_bytes)
            || taken == limit
            || (taken > 0
                && (bytes + size + turn_size > budget.bytes
                    || item_bytes + size > AGENT_CHAT_PAGE_MAX_BYTES))
        {
            break;
        }
        bytes += size + turn_size;
        turn_bytes += turn_size;
        item_bytes += size;
        if let Some(id) = turn_id {
            turn_ids.insert(id);
        }
        taken += 1;
        oldest = Some(row.try_get::<i64, _>("seq")?);
    }
    let Some(oldest) = oldest else {
        return Ok(ItemPage {
            items: Vec::new(),
            turns: Vec::new(),
            history_before: sizes.first().map(|row| row.get::<i64, _>("seq") + 1),
        });
    };
    let rows = sqlx::query(
        "SELECT itemJson FROM agentChatItems WHERE chatId = ? AND seq >= ? AND seq < ? \
         AND NOT COALESCE(json_extract(itemJson, '$.type') = 'payload' AND \
         json_type(itemJson, '$.normalized.hidden') = 'true', 0) ORDER BY seq",
    )
    .bind(chat_id)
    .bind(oldest)
    .bind(before.unwrap_or(i64::MAX))
    .fetch_all(&mut *connection)
    .await?;
    let items = rows
        .into_iter()
        .map(|row| Ok(serde_json::from_str(row.try_get::<&str, _>("itemJson")?)?))
        .collect::<Result<Vec<Value>>>()?;
    let turns = sqlx::query(
        "SELECT turnJson FROM agentChatTurns WHERE chatId = ? AND turnId IN \
         (SELECT turnId FROM agentChatItems WHERE chatId = ? AND seq >= ? AND seq < ? \
         AND NOT COALESCE(json_extract(itemJson, '$.type') = 'payload' AND \
         json_type(itemJson, '$.normalized.hidden') = 'true', 0)) ORDER BY seq",
    )
    .bind(chat_id)
    .bind(chat_id)
    .bind(oldest)
    .bind(before.unwrap_or(i64::MAX))
    .fetch_all(&mut *connection)
    .await?
    .into_iter()
    .map(|row| Ok(serde_json::from_str(row.try_get::<&str, _>("turnJson")?)?))
    .collect::<Result<Vec<Value>>>()?;
    Ok(ItemPage {
        items,
        turns,
        history_before: ((sizes.len() as i64) > taken).then_some(oldest),
    })
}

pub(super) async fn required_turns_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    snapshot: &AgentChatSnapshot,
) -> Result<Vec<AgentChatTurn>> {
    let requests = serde_json::to_string(&snapshot.pending_requests)?;
    let rows = sqlx::query(
        "SELECT turnJson FROM agentChatTurns WHERE chatId = ? AND \
         (status = 'running' OR turnId = ? OR turnId IN \
         (SELECT json_extract(value, '$.turnId') FROM json_each(?))) ORDER BY seq",
    )
    .bind(chat_id)
    .bind(&snapshot.session.active_turn_id)
    .bind(requests)
    .fetch_all(&mut *connection)
    .await?;
    rows.into_iter()
        .map(|row| Ok(serde_json::from_str(row.try_get::<&str, _>("turnJson")?)?))
        .collect()
}

pub(super) async fn require_snapshot_budget_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    snapshot: &AgentChatSnapshot,
    header_bytes: usize,
) -> Result<()> {
    let bytes: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(byteSize), 0) FROM agentChatTurns WHERE chatId = ? AND \
         (status = 'running' OR turnId = ? OR turnId IN \
         (SELECT json_extract(value, '$.turnId') FROM json_each(?)))",
    )
    .bind(chat_id)
    .bind(&snapshot.session.active_turn_id)
    .bind(serde_json::to_string(&snapshot.pending_requests)?)
    .fetch_one(&mut *connection)
    .await?;
    if header_bytes + bytes as usize + 4096 > SNAPSHOT_VIEW_MAX_BYTES {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "active turn metadata exceeds the snapshot view budget".into()
        ));
    }
    Ok(())
}

pub(super) async fn projected_snapshot_in(
    connection: &mut SqliteConnection,
    row: &SessionRow,
    include_items: bool,
) -> Result<Value> {
    let mut snapshot: AgentChatSnapshot = serde_json::from_str(&row.snapshot_json)?;
    snapshot.cursor = row.cursor;
    let required = required_turns_in(connection, &row.chat_id, &snapshot).await?;
    let mut turns = BTreeMap::new();
    let mut bytes = 0;
    for turn in required {
        let value = serde_json::to_value(turn)?;
        bytes += serde_json::to_string(&value)?.len();
        turns.insert(value["turnId"].as_str().unwrap().to_string(), value);
    }
    let page = if include_items {
        let available =
            SNAPSHOT_VIEW_MAX_BYTES.saturating_sub(row.snapshot_json.len() + bytes + 4096);
        item_page_in(
            connection,
            &row.chat_id,
            None,
            AGENT_CHAT_PAGE_MAX_ITEMS,
            ItemPageBudget {
                bytes: AGENT_CHAT_PAGE_MAX_BYTES,
                turn_bytes: AGENT_CHAT_TURN_PROJECTION_MAX_BYTES.saturating_sub(bytes),
                hard_bytes: available,
                known_turn_ids: turns.keys().cloned().collect(),
            },
        )
        .await?
    } else {
        ItemPage {
            items: Vec::new(),
            turns: Vec::new(),
            history_before: None,
        }
    };
    for turn in page.turns {
        let id = turn["turnId"].as_str().unwrap().to_string();
        if let Entry::Vacant(entry) = turns.entry(id) {
            bytes += serde_json::to_string(&turn)?.len();
            entry.insert(turn);
        }
    }
    let recent = sqlx::query(
        "SELECT turnId, turnJson, byteSize FROM agentChatTurns WHERE chatId = ? ORDER BY seq DESC LIMIT ?",
    )
    .bind(&row.chat_id)
    .bind(AGENT_CHAT_RECENT_TURNS)
    .fetch_all(&mut *connection)
    .await?;
    for turn in recent {
        let id: String = turn.try_get("turnId")?;
        let size = turn.try_get::<i64, _>("byteSize")? as usize;
        if !turns.contains_key(&id) && bytes + size <= AGENT_CHAT_TURN_PROJECTION_MAX_BYTES {
            turns.insert(id, serde_json::from_str(turn.try_get("turnJson")?)?);
            bytes += size;
        }
    }
    // Persisted order is independent of the provider's native turn ids.
    let order: Vec<String> = sqlx::query_scalar(
        "SELECT turnId FROM agentChatTurns WHERE chatId = ? AND turnId IN \
         (SELECT value FROM json_each(?)) ORDER BY seq",
    )
    .bind(&row.chat_id)
    .bind(serde_json::to_string(&turns.keys().collect::<Vec<_>>())?)
    .fetch_all(&mut *connection)
    .await?;
    snapshot.turns = order
        .into_iter()
        .map(|id| serde_json::from_value(turns.remove(&id).unwrap()).map_err(Into::into))
        .collect::<Result<_>>()?;
    snapshot.items = page
        .items
        .into_iter()
        .map(|item| serde_json::from_value(item).map_err(Into::into))
        .collect::<Result<_>>()?;
    snapshot.history_before = page.history_before;
    let value = serde_json::to_value(snapshot)?;
    if serde_json::to_string(&value)?.len() > SNAPSHOT_VIEW_MAX_BYTES {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "active turn metadata exceeds the snapshot view budget".into()
        ));
    }
    Ok(value)
}

//! Bounded reads of a visible item's retained, redacted native JSON.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{Row, SqliteConnection};

use super::agent_chat_models::{
    AgentChatStoreError, AGENT_CHAT_PAGE_MAX_BYTES, AGENT_CHAT_PAGE_MAX_ITEMS,
};
use super::agent_chat_store::require_session_row_in;
use super::agent_chat_validation::{require_chat_id, require_id};
use super::RuntimeStore;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentChatPayloadChunk {
    /// Zero-based cursor; stored payload rows use one-based payloadIndex.
    pub index: u64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatPayloadPage {
    pub chunks: Vec<AgentChatPayloadChunk>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_index: Option<u64>,
    pub segment_count: u64,
    pub format: String,
    /// Changes whenever the head or any linked chunk is committed again.
    pub revision: String,
}

fn invalid(message: &str) -> anyhow::Error {
    AgentChatStoreError::Invalid(message.into()).into()
}

impl RuntimeStore {
    /// Metadata-only lookup for removing obsolete chunks through a normal chat
    /// commit, including chunks absent from the bounded visible snapshot.
    pub async fn agent_chat_payload_item_ids(
        &self,
        chat_id: &str,
        item_id: &str,
    ) -> Result<Vec<String>> {
        require_chat_id(chat_id)?;
        require_id("itemId", item_id)?;
        let mut tx = self.pool().begin().await?;
        require_session_row_in(&mut tx, chat_id).await?;
        let ids = sqlx::query_scalar(
            "SELECT itemId FROM agentChatItems WHERE chatId = ? AND \
             json_extract(itemJson, '$.type') = 'payload' AND \
             json_type(itemJson, '$.normalized.hidden') = 'true' AND \
             json_extract(itemJson, '$.normalized.payloadOf') = ? ORDER BY seq",
        )
        .bind(chat_id)
        .bind(item_id)
        .fetch_all(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(ids)
    }

    /// Reads JSON linked by the head's payloadRef, never an arbitrary chunk id.
    /// Concatenating pages in index order reconstructs the exact retained JSON.
    pub async fn agent_chat_payload(
        &self,
        chat_id: &str,
        item_id: &str,
        index: u64,
        limit: i64,
    ) -> Result<AgentChatPayloadPage> {
        require_chat_id(chat_id)?;
        require_id("itemId", item_id)?;
        let mut tx = self.pool().begin().await?;
        require_session_row_in(&mut tx, chat_id).await?;
        let head = sqlx::query(
            "SELECT itemJson, updatedCursor FROM agentChatItems WHERE chatId = ? AND itemId = ?",
        )
        .bind(chat_id)
        .bind(item_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AgentChatStoreError::NotFound(item_id.into()))?;
        let head_cursor: i64 = head.try_get("updatedCursor")?;
        let head: Value = serde_json::from_str(head.try_get::<&str, _>("itemJson")?)?;
        if head["type"] == "payload" && head["normalized"]["hidden"] == true {
            return Err(invalid("payload reads require the visible head item"));
        }
        let reference = head["normalized"]["payloadRef"]
            .as_object()
            .ok_or_else(|| invalid("item has no payload reference"))?;
        if reference.get("format").and_then(Value::as_str) != Some("json") {
            return Err(invalid("payload reference format must be json"));
        }
        let page = if reference.get("field").and_then(Value::as_str) == Some("data") {
            if reference.contains_key("itemId") || reference.contains_key("segmentCount") {
                return Err(invalid("inline payload reference cannot link chunks"));
            }
            if index != 0 {
                return Err(invalid("payload index is outside the retained segments"));
            }
            let data = head
                .get("data")
                .ok_or_else(|| invalid("inline payload data is missing"))?;
            AgentChatPayloadPage {
                chunks: vec![AgentChatPayloadChunk {
                    index: 0,
                    text: serde_json::to_string(data)?,
                }],
                next_index: None,
                segment_count: 1,
                format: "json".into(),
                revision: head_cursor.to_string(),
            }
        } else {
            if reference.contains_key("field") {
                return Err(invalid("payload reference field must be data"));
            }
            let first_id = reference
                .get("itemId")
                .and_then(Value::as_str)
                .ok_or_else(|| invalid("payload reference itemId is missing"))?;
            require_id("payloadRef.itemId", first_id)?;
            let count = reference
                .get("segmentCount")
                .and_then(Value::as_u64)
                .filter(|count| *count > 0 && *count < i64::MAX as u64)
                .ok_or_else(|| invalid("payload reference segmentCount must be positive"))?;
            if index >= count {
                return Err(invalid("payload index is outside the retained segments"));
            }
            let version = reference
                .get("payloadVersion")
                .map(|value| {
                    value
                        .as_str()
                        .ok_or_else(|| invalid("payloadVersion must be a string"))
                })
                .transpose()?;
            if let Some(version) = version {
                require_id("payloadRef.payloadVersion", version)?;
            }
            let chunk_cursor =
                require_chunks_in(&mut tx, chat_id, item_id, first_id, count, version).await?;
            let mut page = chunk_page_in(&mut tx, chat_id, item_id, index, count, limit).await?;
            page.revision = format!("{head_cursor}:{chunk_cursor}");
            page
        };
        if serde_json::to_vec(&page)?.len() > AGENT_CHAT_PAGE_MAX_BYTES {
            return Err(invalid("payload segment exceeds the page budget"));
        }
        tx.commit().await?;
        Ok(page)
    }
}

async fn require_chunks_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    item_id: &str,
    first_id: &str,
    count: u64,
    version: Option<&str>,
) -> Result<i64> {
    let rows = sqlx::query(
        "SELECT COUNT(*) AS total, \
         COUNT(DISTINCT json_extract(itemJson, '$.normalized.payloadIndex')) AS distinctIndices, \
         MIN(json_extract(itemJson, '$.normalized.payloadIndex')) AS firstIndex, \
         MAX(json_extract(itemJson, '$.normalized.payloadIndex')) AS lastIndex, \
         SUM(CASE WHEN json_extract(itemJson, '$.type') = 'payload' AND \
         json_type(itemJson, '$.normalized.hidden') = 'true' AND \
         json_type(itemJson, '$.normalized.payloadOf') = 'text' AND \
         json_type(itemJson, '$.normalized.payloadIndex') = 'integer' AND \
         json_extract(itemJson, '$.normalized.format') = 'json' AND \
         json_type(itemJson, '$.text') = 'text' AND \
         (? IS NULL OR (json_type(itemJson, '$.normalized.payloadVersion') = 'text' AND \
         json_extract(itemJson, '$.normalized.payloadVersion') = ?)) \
         THEN 0 ELSE 1 END) AS invalidRows, MAX(updatedCursor) AS maxCursor, \
         MAX(CASE WHEN json_extract(itemJson, '$.normalized.payloadIndex') = 1 \
         THEN itemId ELSE NULL END) AS firstId \
         FROM agentChatItems WHERE chatId = ? AND \
         json_extract(itemJson, '$.normalized.payloadOf') = ? AND \
         json_extract(itemJson, '$.type') = 'payload' AND \
         json_type(itemJson, '$.normalized.hidden') = 'true'",
    )
    .bind(version)
    .bind(version)
    .bind(chat_id)
    .bind(item_id)
    .fetch_one(&mut *connection)
    .await?;
    if rows.try_get::<i64, _>("total")? != count as i64
        || rows.try_get::<i64, _>("distinctIndices")? != count as i64
        || rows.try_get::<Option<i64>, _>("invalidRows")? != Some(0)
        || rows.try_get::<Option<i64>, _>("firstIndex")? != Some(1)
        || rows.try_get::<Option<i64>, _>("lastIndex")? != Some(count as i64)
        || rows.try_get::<Option<String>, _>("firstId")?.as_deref() != Some(first_id)
    {
        return Err(invalid(
            "payload segments are missing, malformed, or not owned by the head",
        ));
    }
    Ok(rows.try_get("maxCursor")?)
}

async fn chunk_page_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    item_id: &str,
    index: u64,
    count: u64,
    limit: i64,
) -> Result<AgentChatPayloadPage> {
    let sizes = sqlx::query(
        "SELECT byteSize FROM agentChatItems WHERE chatId = ? AND \
         json_extract(itemJson, '$.normalized.payloadOf') = ? AND \
         json_extract(itemJson, '$.type') = 'payload' AND \
         json_type(itemJson, '$.normalized.hidden') = 'true' AND \
         json_extract(itemJson, '$.normalized.payloadIndex') >= ? \
         ORDER BY json_extract(itemJson, '$.normalized.payloadIndex') LIMIT ?",
    )
    .bind(chat_id)
    .bind(item_id)
    .bind((index + 1) as i64)
    .bind(limit.clamp(1, AGENT_CHAT_PAGE_MAX_ITEMS))
    .fetch_all(&mut *connection)
    .await?;
    let mut bytes = 4096_usize;
    let mut taken = 0_u64;
    for row in sizes {
        let size = row.try_get::<i64, _>("byteSize")? as usize;
        if taken > 0 && bytes.saturating_add(size) > AGENT_CHAT_PAGE_MAX_BYTES {
            break;
        }
        bytes = bytes.saturating_add(size);
        taken += 1;
    }
    let rows = sqlx::query(
        "SELECT json_extract(itemJson, '$.normalized.payloadIndex') AS payloadIndex, \
         json_extract(itemJson, '$.text') AS text FROM agentChatItems WHERE chatId = ? AND \
         json_extract(itemJson, '$.normalized.payloadOf') = ? AND \
         json_extract(itemJson, '$.type') = 'payload' AND \
         json_type(itemJson, '$.normalized.hidden') = 'true' AND \
         json_extract(itemJson, '$.normalized.payloadIndex') >= ? AND \
         json_extract(itemJson, '$.normalized.payloadIndex') < ? \
         ORDER BY json_extract(itemJson, '$.normalized.payloadIndex')",
    )
    .bind(chat_id)
    .bind(item_id)
    .bind((index + 1) as i64)
    .bind((index + taken + 1) as i64)
    .fetch_all(&mut *connection)
    .await?;
    let chunks = rows
        .into_iter()
        .map(|row| {
            Ok(AgentChatPayloadChunk {
                index: row.try_get::<i64, _>("payloadIndex")? as u64 - 1,
                text: row.try_get("text")?,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    let next = index + taken;
    Ok(AgentChatPayloadPage {
        chunks,
        next_index: (next < count).then_some(next),
        segment_count: count,
        format: "json".into(),
        revision: String::new(),
    })
}

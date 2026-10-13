use anyhow::Result;
use serde_json::Value;
use sha2::{Digest, Sha256};

use super::agent_chat_models::*;
pub(super) use super::agent_chat_secrets::reject_secret_fields;
use super::WorkspaceTabRecord;

fn invalid(message: impl Into<String>) -> anyhow::Error {
    AgentChatStoreError::Invalid(message.into()).into()
}

pub(super) fn require_id(label: &str, value: &str) -> Result<()> {
    if value.trim().is_empty() || value.trim() != value {
        return Err(invalid(format!(
            "{label} must be a non-empty trimmed string"
        )));
    }
    if value.len() > AGENT_CHAT_ID_MAX_BYTES {
        return Err(invalid(format!(
            "{label} exceeds {AGENT_CHAT_ID_MAX_BYTES} bytes"
        )));
    }
    Ok(())
}

/// Chat ids are the caller-owned provider thread ids: canonical lowercase
/// UUIDv4, so two spellings can never name the same chat.
pub(super) fn require_chat_id(chat_id: &str) -> Result<()> {
    let parsed = uuid::Uuid::parse_str(chat_id)
        .map_err(|_| invalid(format!("chatId is not a UUID: {chat_id}")))?;
    if parsed.get_version_num() != 4 || parsed.hyphenated().to_string() != chat_id {
        return Err(invalid(format!(
            "chatId must be a lowercase hyphenated UUIDv4: {chat_id}"
        )));
    }
    Ok(())
}

pub(super) fn require_tab(record: &AgentChatRecord, tab: &WorkspaceTabRecord) -> Result<()> {
    if tab.kind != AGENT_CHAT_TAB_KIND {
        return Err(invalid(format!("tab kind must be {AGENT_CHAT_TAB_KIND}")));
    }
    if tab.id != record.tab_id || tab.workspace_id != record.workspace_id {
        return Err(invalid("tab id and workspace must match the chat"));
    }
    let payload = tab
        .payload
        .as_object()
        .ok_or_else(|| invalid("tab payload must be an object"))?;
    for (key, expected) in [
        ("chatId", &record.chat_id),
        ("provider", &record.provider),
        ("providerInstanceId", &record.provider_instance_id),
    ] {
        if payload.get(key).and_then(Value::as_str) != Some(expected.as_str()) {
            return Err(invalid(format!("tab payload {key} must match the chat")));
        }
    }
    if payload.get("model").is_some_and(|model| !model.is_string()) {
        return Err(invalid("tab payload model must be a string"));
    }
    Ok(())
}

pub(super) fn parse_snapshot(value: &Value) -> Result<AgentChatSnapshot> {
    let snapshot: AgentChatSnapshot = serde_json::from_value(value.clone())
        .map_err(|error| invalid(format!("snapshot: {error}")))?;
    require_chat_id(&snapshot.chat_id)?;
    require_id("workspaceId", &snapshot.workspace_id)?;
    require_id("tabId", &snapshot.tab_id)?;
    require_id("provider", &snapshot.provider)?;
    require_id("providerInstanceId", &snapshot.provider_instance_id)?;
    if snapshot.cursor < 0 {
        return Err(invalid("snapshot cursor must not be negative"));
    }
    require_session(&snapshot.session)?;
    let mut turn_ids = std::collections::BTreeSet::new();
    for turn in &snapshot.turns {
        require_turn(turn)?;
        if !turn_ids.insert(turn.turn_id.as_str()) {
            return Err(invalid(format!("duplicate turnId {}", turn.turn_id)));
        }
    }
    require_requests(&snapshot.pending_requests)?;
    Ok(snapshot)
}

fn require_session(session: &AgentChatSession) -> Result<()> {
    require_id("runtimeMode", &session.runtime_mode)?;
    require_id("interactionMode", &session.interaction_mode)?;
    if let Some(turn_id) = &session.active_turn_id {
        require_id("activeTurnId", turn_id)?;
    }
    if !session.capabilities.is_object() {
        return Err(invalid("session capabilities must be an object"));
    }
    Ok(())
}

fn require_requests(requests: &[AgentChatRequest]) -> Result<()> {
    let mut ids = std::collections::BTreeSet::new();
    for request in requests {
        require_id("requestId", &request.request_id)?;
        require_id("request kind", &request.kind)?;
        if !ids.insert(request.request_id.as_str()) {
            return Err(invalid(format!(
                "duplicate requestId {}",
                request.request_id
            )));
        }
    }
    Ok(())
}

/// The header row: the snapshot without its item and turn projections.
pub(super) fn header_json(snapshot: &AgentChatSnapshot) -> Result<String> {
    let mut header = snapshot.clone();
    header.items.clear();
    header.turns.clear();
    header.history_before = None;
    let mut value = serde_json::to_value(&header)?;
    if let Some(object) = value.as_object_mut() {
        object.remove("items");
        object.remove("turns");
    }
    reject_secret_fields("snapshot", &value)?;
    let json = serde_json::to_string(&value)?;
    if json.len() > AGENT_CHAT_SNAPSHOT_HEADER_MAX_BYTES {
        return Err(invalid(format!(
            "snapshot header exceeds {AGENT_CHAT_SNAPSHOT_HEADER_MAX_BYTES} bytes"
        )));
    }
    Ok(json)
}

pub(super) fn require_turn(turn: &AgentChatTurn) -> Result<()> {
    require_id("turnId", &turn.turn_id)?;
    require_id("turn status", &turn.status)
}

pub(super) fn turn_json(turn: &AgentChatTurn) -> Result<String> {
    require_turn(turn)?;
    let value = serde_json::to_value(turn)?;
    reject_secret_fields("turn", &value)?;
    let json = serde_json::to_string(&value)?;
    if json.len() > AGENT_CHAT_TURN_MAX_BYTES {
        return Err(invalid(format!(
            "turn {} exceeds {AGENT_CHAT_TURN_MAX_BYTES} bytes",
            turn.turn_id
        )));
    }
    Ok(json)
}

pub(super) fn parse_header(json: &str) -> Result<AgentChatSnapshot> {
    Ok(serde_json::from_str(json)?)
}

fn is_snake_case(value: &str) -> bool {
    let mut chars = value.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

fn is_camel_case(value: &str) -> bool {
    let mut chars = value.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase()) && chars.all(|c| c.is_ascii_alphanumeric())
}

/// Validates an item and returns its stored JSON.
pub(super) fn item_json(item: &AgentChatItem) -> Result<String> {
    require_id("itemId", &item.item_id)?;
    if let Some(turn_id) = &item.turn_id {
        require_id("item turnId", turn_id)?;
    }
    if !is_snake_case(&item.item_type) {
        return Err(invalid(format!(
            "item type must be snake_case: {}",
            item.item_type
        )));
    }
    if !is_camel_case(&item.status) {
        return Err(invalid(format!(
            "item status must be camelCase: {}",
            item.status
        )));
    }
    for (label, stamp) in [
        ("createdAt", &item.created_at),
        ("updatedAt", &item.updated_at),
    ] {
        chrono::DateTime::parse_from_rfc3339(stamp)
            .map_err(|_| invalid(format!("item {label} must be RFC 3339: {stamp}")))?;
    }
    if !item.normalized.is_object() {
        return Err(invalid("item normalized must be an object"));
    }
    let json = serde_json::to_string(item)?;
    if json.len() > AGENT_CHAT_ITEM_MAX_BYTES {
        return Err(AgentChatStoreError::ItemTooLarge {
            item_id: item.item_id.clone(),
            bytes: json.len(),
            limit: AGENT_CHAT_ITEM_MAX_BYTES,
        }
        .into());
    }
    Ok(json)
}

pub(super) fn parse_delta(value: &Value) -> Result<AgentChatDelta> {
    let delta: AgentChatDelta = serde_json::from_value(value.clone())
        .map_err(|error| invalid(format!("delta: {error}")))?;
    if serde_json::to_string(&delta)?.len() > AGENT_CHAT_DELTA_MAX_BYTES {
        return Err(invalid(format!(
            "delta exceeds {AGENT_CHAT_DELTA_MAX_BYTES} bytes"
        )));
    }
    if let Some(session) = &delta.session {
        require_session(session)?;
    }
    if let Some(requests) = &delta.requests {
        require_requests(requests)?;
    }
    for turn in delta.turns.iter().flatten() {
        require_turn(turn)?;
    }
    for id in delta.removed_item_ids.iter().flatten() {
        require_id("removedItemId", id)?;
    }
    for append in &delta.text_appends {
        require_id("textAppend itemId", &append.item_id)?;
    }
    if let Some(provider) = &delta.provider {
        require_id("provider", provider)?;
    }
    if let Some(instance) = &delta.provider_instance_id {
        require_id("providerInstanceId", instance)?;
    }
    Ok(delta)
}

pub(super) fn utf16_len(text: &str) -> u64 {
    text.encode_utf16().count() as u64
}

/// Byte index of a UTF-16 offset, or `None` when it splits a code point or
/// lies past the end.
fn byte_index_for_utf16(text: &str, offset: u64) -> Option<usize> {
    let mut units = 0_u64;
    for (index, ch) in text.char_indices() {
        if units == offset {
            return Some(index);
        }
        units += ch.len_utf16() as u64;
        if units > offset {
            return None;
        }
    }
    (units == offset).then_some(text.len())
}

/// Applies an append at its offset. Replaying an append that is already
/// present is a no-op, so a commit may carry both the final item and the
/// appends that produced it; text that disagrees at the offset is an error.
pub(super) fn apply_text_append(
    item: &mut AgentChatItem,
    append: &AgentChatTextAppend,
) -> Result<()> {
    let field = match append.stream {
        AgentChatTextStream::Text => &mut item.text,
        AgentChatTextStream::ReasoningText => &mut item.reasoning_text,
        AgentChatTextStream::Output => &mut item.output,
    };
    let current = field.get_or_insert_with(String::new);
    let start = byte_index_for_utf16(current, append.offset).ok_or_else(|| {
        invalid(format!(
            "text append for {} at {} does not meet the stored text ({} units)",
            append.item_id,
            append.offset,
            utf16_len(current)
        ))
    })?;
    let tail = &current[start..];
    if tail.starts_with(append.text.as_str()) {
        return Ok(());
    }
    if let Some(rest) = append.text.strip_prefix(tail) {
        current.push_str(rest);
        return Ok(());
    }
    Err(invalid(format!(
        "text append for {} at {} conflicts with stored text",
        append.item_id, append.offset
    )))
}

/// SHA-256 over key-sorted JSON, so a retried command with the same payload
/// gets the same digest regardless of key order.
pub fn agent_chat_command_digest(payload: &Value) -> String {
    let mut text = String::new();
    write_canonical(payload, &mut text);
    hex::encode(Sha256::digest(text.as_bytes()))
}

fn write_canonical(value: &Value, out: &mut String) {
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
                write_canonical(&map[key], out);
            }
            out.push('}');
        }
        Value::Array(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                write_canonical(item, out);
            }
            out.push(']');
        }
        other => out.push_str(&other.to_string()),
    }
}

/// Chat metadata is an object within its size limit; `None` and `null` clear it.
pub(super) fn metadata_json(metadata: Option<&Value>) -> Result<Option<String>> {
    let json = match metadata {
        None | Some(Value::Null) => return Ok(None),
        Some(value @ Value::Object(_)) => {
            reject_secret_fields("metadata", value)?;
            serde_json::to_string(value)?
        }
        Some(_) => return Err(invalid("metadata must be an object")),
    };
    if json.len() > AGENT_CHAT_METADATA_MAX_BYTES {
        return Err(invalid(format!(
            "metadata exceeds {AGENT_CHAT_METADATA_MAX_BYTES} bytes"
        )));
    }
    Ok(Some(json))
}

/// Native ids keep their JSON type: `"7"` and `7` are different ids.
pub(super) fn native_id_json(native_id: &Value) -> Result<String> {
    match native_id {
        Value::String(text) => require_id("nativeId", text)?,
        Value::Number(number) if number.is_i64() || number.is_u64() => {}
        _ => return Err(invalid("nativeId must be a string or an integer")),
    }
    Ok(native_id.to_string())
}

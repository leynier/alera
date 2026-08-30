use serde_json::Value;

use super::{UsageProvider, UsageTokenTotals};

#[derive(Debug, Clone)]
pub(super) struct UsageRecord {
    pub provider: UsageProvider,
    pub timestamp_ms: i64,
    pub model: String,
    pub session_id: String,
    pub totals: UsageTokenTotals,
    pub reported_cost_usd: Option<f64>,
    pub dedupe_key: Option<String>,
}

pub(super) fn might_carry_usage(line: &str, provider: UsageProvider) -> bool {
    match provider {
        UsageProvider::Claude => line.contains("\"usage\""),
        UsageProvider::Grok => line.contains("\"turn_completed\""),
        UsageProvider::Codex => {
            line.contains("\"token_count\"")
                || line.contains("\"turn_context\"")
                || line.contains("\"session_meta\"")
        }
    }
}

pub(super) fn parse_claude_line(line: &str) -> Option<UsageRecord> {
    let record: Value = serde_json::from_str(line).ok()?;
    if record.get("type").and_then(Value::as_str) != Some("assistant") {
        return None;
    }
    let message = record.get("message")?;
    let usage = message.get("usage")?;
    let timestamp_ms = parse_timestamp(record.get("timestamp")?)?;
    let model = message.get("model")?.as_str()?.trim();
    if model.is_empty() {
        return None;
    }
    let message_id = message.get("id").and_then(Value::as_str);
    let request_id = record.get("requestId").and_then(Value::as_str);
    let dedupe_key = match (message_id, request_id) {
        (None, None) => None,
        _ => Some(format!(
            "{}:{}",
            message_id.unwrap_or_default(),
            request_id.unwrap_or_default()
        )),
    };
    let totals = UsageTokenTotals {
        uncached_input_tokens: positive_int(usage.get("input_tokens")),
        cached_input_tokens: positive_int(usage.get("cache_read_input_tokens")),
        cache_creation_tokens: positive_int(usage.get("cache_creation_input_tokens")),
        output_tokens: positive_int(usage.get("output_tokens")),
        reasoning_tokens: 0,
    };
    if totals.total() == 0 {
        return None;
    }
    Some(UsageRecord {
        provider: UsageProvider::Claude,
        timestamp_ms,
        model: model.to_string(),
        session_id: record
            .get("sessionId")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        totals,
        reported_cost_usd: record
            .get("costUSD")
            .and_then(Value::as_f64)
            .filter(|value| value.is_finite() && *value >= 0.0),
        dedupe_key,
    })
}

#[derive(Debug, Default)]
pub(super) struct CodexScanState {
    model: String,
    session_id: String,
    last_usage_signature: Option<String>,
    saw_session_meta: bool,
    suppressing_fork_copies: bool,
    fork_copy_anchor_ms: i64,
}

pub(super) fn parse_codex_line(line: &str, state: &mut CodexScanState) -> Option<UsageRecord> {
    let record: Value = serde_json::from_str(line).ok()?;
    let record_type = record.get("type").and_then(Value::as_str)?;
    let payload = record.get("payload")?;
    if record_type == "session_meta" {
        if state.saw_session_meta {
            return None;
        }
        state.saw_session_meta = true;
        state.session_id = payload
            .get("id")
            .or_else(|| payload.get("session_id"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        if is_forked_session(payload) {
            state.suppressing_fork_copies = true;
            state.fork_copy_anchor_ms = parse_timestamp(record.get("timestamp")?)?;
        }
        return None;
    }
    if record_type == "turn_context" {
        if let Some(model) = payload.get("model").and_then(Value::as_str) {
            state.model = model.to_string();
        }
        return None;
    }
    if payload.get("type").and_then(Value::as_str) != Some("token_count") {
        return None;
    }
    let last = payload.get("info")?.get("last_token_usage")?;
    let timestamp_ms = parse_timestamp(record.get("timestamp")?)?;
    if state.model.is_empty() {
        return None;
    }
    let signature = serde_json::to_string(last).ok()?;
    if state.last_usage_signature.as_deref() == Some(&signature) {
        return None;
    }
    state.last_usage_signature = Some(signature);
    if state.suppressing_fork_copies {
        if timestamp_ms - state.fork_copy_anchor_ms < 1000 {
            state.fork_copy_anchor_ms = timestamp_ms;
            return None;
        }
        state.suppressing_fork_copies = false;
    }
    let input = positive_int(last.get("input_tokens"));
    let cached = positive_int(last.get("cached_input_tokens"));
    let cache_creation = positive_int(last.get("cache_write_input_tokens"));
    let output = positive_int(last.get("output_tokens"));
    let totals = UsageTokenTotals {
        uncached_input_tokens: input.saturating_sub(cached.saturating_add(cache_creation)),
        cached_input_tokens: cached,
        cache_creation_tokens: cache_creation,
        output_tokens: output,
        reasoning_tokens: positive_int(last.get("reasoning_output_tokens")).min(output),
    };
    if totals.total() == 0 {
        return None;
    }
    Some(UsageRecord {
        provider: UsageProvider::Codex,
        timestamp_ms,
        model: state.model.clone(),
        session_id: state.session_id.clone(),
        totals,
        reported_cost_usd: None,
        dedupe_key: None,
    })
}

fn is_forked_session(payload: &Value) -> bool {
    payload
        .get("forked_from_id")
        .and_then(Value::as_str)
        .is_some()
        || payload
            .pointer("/source/subagent/thread_spawn/parent_thread_id")
            .and_then(Value::as_str)
            .is_some()
}

fn parse_timestamp(value: &Value) -> Option<i64> {
    chrono::DateTime::parse_from_rfc3339(value.as_str()?)
        .ok()
        .map(|date| date.timestamp_millis())
}

pub(super) fn positive_int(value: Option<&Value>) -> u64 {
    value
        .and_then(|value| {
            value
                .as_u64()
                .or_else(|| value.as_f64().map(|value| value as u64))
        })
        .unwrap_or_default()
}

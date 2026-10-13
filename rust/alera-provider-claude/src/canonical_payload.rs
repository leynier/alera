use serde_json::{json, Value};

pub(super) fn item_type_for_tool(name: &str) -> String {
    let lower = name.to_ascii_lowercase();
    if lower == "bash" || lower.contains("shell") || lower.contains("command") {
        "command_execution".into()
    } else if lower == "write" || lower == "edit" || lower.contains("file") {
        "file_change".into()
    } else if lower.starts_with("mcp__") || lower.contains("mcp") {
        "mcp_tool_call".into()
    } else if lower.contains("web_search") || lower.contains("search") {
        "web_search".into()
    } else {
        "dynamic_tool_call".into()
    }
}

pub(super) fn task_id(payload: &Value) -> Option<String> {
    ["taskId", "task_id", "taskID", "id", "uuid"]
        .iter()
        .find_map(|key| text_field(payload, &[*key]))
}

pub(super) fn text_field(payload: &Value, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        payload
            .get(*key)
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_owned)
    })
}

pub(super) fn task_status(payload: &Value) -> Option<&'static str> {
    match text_field(payload, &["status", "state"]).as_deref() {
        Some("pending" | "queued") => Some("pending"),
        Some("running" | "started" | "in_progress") => Some("running"),
        Some("waiting" | "paused") => Some("waiting"),
        Some("idle") => Some("idle"),
        Some("completed" | "complete" | "done") => Some("completed"),
        Some("failed" | "error") => Some("failed"),
        Some("cancelled" | "canceled") => Some("cancelled"),
        Some("interrupted" | "aborted") => Some("interrupted"),
        _ => None,
    }
}

pub(super) fn completed_task_status(payload: &Value) -> &'static str {
    match task_status(payload) {
        Some("failed") => "failed",
        Some("cancelled" | "interrupted") => "stopped",
        _ => "completed",
    }
}

pub(super) fn compact_nulls(mut payload: Value) -> Value {
    if let Value::Object(object) = &mut payload {
        object.retain(|_, value| !value.is_null());
    }
    payload
}

pub(super) fn rate_limit_window(payload: &Value) -> Option<Value> {
    let info = payload.get("rate_limit_info").unwrap_or(payload);
    let id = text_field(info, &["rateLimitType", "rate_limit_type", "id"])
        .unwrap_or_else(|| "primary".into());
    let normalized_id = id.to_ascii_lowercase();
    let (kind, known_label, known_duration) = match normalized_id.as_str() {
        "five_hour" => ("session", Some("Session"), Some(300_u64)),
        "seven_day" | "seven_day_overage_included" => ("weekly", Some("Weekly"), Some(7 * 24 * 60)),
        value if value.contains("week") || value.contains("7_day") => ("weekly", None, None),
        value if value.contains("month") || value.contains("30_day") => ("monthly", None, None),
        value if value.contains("hour") || value.contains("session") => ("session", None, None),
        _ => ("other", None, None),
    };
    let raw_utilization = info.get("utilization").and_then(Value::as_f64)?;
    let used_percent = if raw_utilization <= 1.0 {
        raw_utilization * 100.0
    } else {
        raw_utilization
    }
    .clamp(0.0, 100.0);
    let label = known_label
        .map(str::to_owned)
        .or_else(|| text_field(info, &["label", "rateLimitType", "rate_limit_type"]))
        .unwrap_or_else(|| id.clone());
    let duration = known_duration.or_else(|| {
        info.get("windowDurationMins")
            .or_else(|| info.get("window_duration_mins"))
            .and_then(Value::as_u64)
    });
    let mut window = json!({
        "id": id,
        "kind": kind,
        "label": label,
        "usedPercent": used_percent,
    });
    if let Some(duration) = duration {
        window["windowDurationMins"] = Value::from(duration);
    }
    if let Some(resets_at) = info
        .get("resetsAt")
        .or_else(|| info.get("resets_at"))
        .and_then(epoch_seconds_iso)
    {
        window["resetsAt"] = Value::String(resets_at);
    }
    Some(window)
}

fn epoch_seconds_iso(value: &Value) -> Option<String> {
    let seconds = value.as_i64()?;
    chrono::DateTime::<chrono::Utc>::from_timestamp(seconds, 0).map(|date| date.to_rfc3339())
}

pub(super) fn normalize_token_usage(value: Value) -> Option<Value> {
    let object = value.as_object()?;
    let input_tokens = object
        .get("inputTokens")
        .and_then(Value::as_u64)
        .or_else(|| {
            let base = number(object, &["input_tokens"]);
            let cached = number(
                object,
                &[
                    "cachedInputTokens",
                    "cache_read_input_tokens",
                    "cache_read_tokens",
                ],
            )
            .unwrap_or(0);
            let created = number(
                object,
                &["cacheCreationTokens", "cache_creation_input_tokens"],
            )
            .unwrap_or(0);
            base.map(|base| base.saturating_add(cached).saturating_add(created))
                .or_else(|| (cached > 0 || created > 0).then_some(cached.saturating_add(created)))
        });
    let output_tokens = number(object, &["outputTokens", "output_tokens"]);
    let cached_input_tokens = number(
        object,
        &[
            "cachedInputTokens",
            "cache_read_input_tokens",
            "cache_read_tokens",
        ],
    );
    let cache_creation_tokens = number(
        object,
        &["cacheCreationTokens", "cache_creation_input_tokens"],
    );
    let reasoning_tokens = number(object, &["reasoningTokens", "reasoning_tokens"]);
    if input_tokens.is_none()
        && output_tokens.is_none()
        && cached_input_tokens.is_none()
        && cache_creation_tokens.is_none()
        && reasoning_tokens.is_none()
    {
        return None;
    }
    let mut normalized = serde_json::Map::new();
    normalized.insert("usageScope".into(), Value::String("main_agent".into()));
    normalized.insert("hasSubagents".into(), Value::Bool(false));
    normalized.insert(
        "usageStatus".into(),
        Value::String(
            if input_tokens.is_some() && output_tokens.is_some() {
                "complete"
            } else {
                "partial"
            }
            .into(),
        ),
    );
    insert_number(&mut normalized, "inputTokens", input_tokens);
    insert_number(&mut normalized, "outputTokens", output_tokens);
    insert_number(&mut normalized, "cachedInputTokens", cached_input_tokens);
    insert_number(
        &mut normalized,
        "cacheCreationTokens",
        cache_creation_tokens,
    );
    insert_number(&mut normalized, "reasoningTokens", reasoning_tokens);
    Some(Value::Object(normalized))
}

fn number(object: &serde_json::Map<String, Value>, keys: &[&str]) -> Option<u64> {
    keys.iter()
        .find_map(|key| object.get(*key).and_then(Value::as_u64))
}

fn insert_number(object: &mut serde_json::Map<String, Value>, key: &str, value: Option<u64>) {
    if let Some(value) = value {
        object.insert(key.into(), Value::from(value));
    }
}

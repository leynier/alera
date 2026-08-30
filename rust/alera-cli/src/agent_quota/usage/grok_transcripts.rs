use std::path::{Path, PathBuf};

use serde_json::Value;

use super::transcripts::{positive_int, UsageRecord};
use super::{UsageProvider, UsageRequest, UsageSourceConfig, UsageTokenTotals};

pub(super) fn grok_usage_source(
    request: &UsageRequest,
    home: &Path,
    configured: Option<&str>,
) -> Option<UsageSourceConfig> {
    // Older clients classify unknown providers as Codex, so Grok requires opt-in.
    request.include_grok.then(|| UsageSourceConfig {
        provider: UsageProvider::Grok,
        account_id: "default".to_string(),
        display_name: "Default".to_string(),
        directory: grok_sessions_directory(home, configured),
    })
}

pub(super) fn grok_sessions_directory(home: &Path, configured: Option<&str>) -> PathBuf {
    let root = match configured.map(str::trim).filter(|value| !value.is_empty()) {
        None => home.join(".grok"),
        Some("~") => home.to_path_buf(),
        Some(value) => value
            .strip_prefix("~/")
            .or_else(|| value.strip_prefix("~\\"))
            .map(|suffix| home.join(suffix))
            .unwrap_or_else(|| PathBuf::from(value)),
    };
    root.join("sessions")
}

pub(super) fn parse_grok_line(line: &str) -> Vec<UsageRecord> {
    serde_json::from_str(line)
        .ok()
        .and_then(|record| parse_turn(&record))
        .unwrap_or_default()
}

fn parse_turn(record: &Value) -> Option<Vec<UsageRecord>> {
    let params = record.get("params")?;
    let update = params.get("update")?;
    if update.get("sessionUpdate")?.as_str()? != "turn_completed" {
        return None;
    }
    let usage = update.get("usage")?.as_object()?;
    let timestamp_ms = params
        .pointer("/_meta/agentTimestampMs")
        .and_then(|value| timestamp_millis(value, false))
        .or_else(|| timestamp_millis(record.get("timestamp")?, true))?;
    let session_id = params
        .get("sessionId")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let prompt_id = update
        .get("prompt_id")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty());
    let mut models: Vec<(&str, &Value)> = usage
        .get("modelUsage")
        .and_then(Value::as_object)
        .into_iter()
        .flatten()
        .filter(|(model, value)| !model.trim().is_empty() && value.is_object())
        .map(|(model, value)| (model.as_str(), value))
        .collect();
    if models.is_empty() {
        models.push(("grok", update.get("usage")?));
    }
    let mut records: Vec<UsageRecord> = models
        .into_iter()
        .filter_map(|(model, value)| {
            let totals = token_totals(value);
            if totals.total() == 0 {
                return None;
            }
            Some(UsageRecord {
                provider: UsageProvider::Grok,
                timestamp_ms,
                model: model.to_string(),
                session_id: session_id.to_string(),
                totals,
                reported_cost_usd: cost_usd(value.get("costUsdTicks")),
                // Missing identity must not merge unrelated same-second turns.
                dedupe_key: prompt_id.filter(|_| !session_id.is_empty()).map(|prompt| {
                    serde_json::to_string(&(session_id, prompt, model))
                        .expect("string tuple serializes")
                }),
            })
        })
        .collect();

    if let Some(total_cost) = cost_usd(usage.get("costUsdTicks")) {
        let assigned_cost: f64 = records.iter().filter_map(|row| row.reported_cost_usd).sum();
        let unpriced_tokens: f64 = records
            .iter()
            .filter(|row| row.reported_cost_usd.is_none())
            .map(|row| row.totals.total() as f64)
            .sum();
        // Preserve model costs and distribute only the remaining turn cost.
        // Zero-token models must not consume any of that remainder.
        let remainder = (total_cost - assigned_cost).max(0.0);
        if unpriced_tokens > 0.0 {
            for row in &mut records {
                if row.reported_cost_usd.is_none() {
                    row.reported_cost_usd =
                        Some(remainder * (row.totals.total() as f64 / unpriced_tokens));
                }
            }
        }
    }
    Some(records)
}

fn token_totals(value: &Value) -> UsageTokenTotals {
    let input = positive_int(value.get("inputTokens"));
    let cached = positive_int(value.get("cachedReadTokens"));
    let created = positive_int(value.get("cacheCreationTokens"));
    let output = positive_int(value.get("outputTokens"));
    UsageTokenTotals {
        // Input includes cache reads/writes; reasoning is part of output.
        uncached_input_tokens: input.saturating_sub(cached.saturating_add(created)),
        cached_input_tokens: cached,
        cache_creation_tokens: created,
        output_tokens: output,
        reasoning_tokens: positive_int(value.get("reasoningTokens")).min(output),
    }
}

fn cost_usd(value: Option<&Value>) -> Option<f64> {
    value
        .and_then(Value::as_f64)
        .filter(|ticks| ticks.is_finite() && *ticks >= 0.0)
        // Grok stores cost in ticks, with 10^10 ticks per USD.
        .map(|ticks| ticks / 10_000_000_000.0)
}

fn timestamp_millis(value: &Value, allow_seconds: bool) -> Option<i64> {
    let raw = value.as_f64()?;
    let millis = if allow_seconds && raw <= 1e12 {
        raw * 1000.0
    } else {
        raw
    };
    (millis.is_finite() && (0.0..i64::MAX as f64).contains(&millis)).then_some(millis as i64)
}

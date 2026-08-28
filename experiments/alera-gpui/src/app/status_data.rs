use std::collections::BTreeMap;
use std::time::Duration;

use gpui::Context;
use serde_json::{json, Value};

use super::AleraApp;

#[derive(Clone, Debug, Default)]
pub(super) struct StatusData {
    pub quotas: Vec<QuotaSnapshot>,
    pub quota_loading: bool,
    pub quota_error: Option<String>,
    pub quota_environment: BTreeMap<String, bool>,
    pub quota_generation: u64,
    pub resources: Option<Value>,
    pub resource_error: Option<String>,
    pub resource_generation: u64,
    pub runtime: Option<Value>,
    pub runtime_loading: bool,
    pub runtime_error: Option<String>,
    pub runtime_generation: u64,
    pub presence: Vec<Value>,
    pub presence_generation: u64,
}

#[derive(Clone, Debug)]
pub(super) struct QuotaSnapshot {
    pub provider: String,
    pub account_id: String,
    pub display_name: String,
    pub status: String,
    pub error: Option<String>,
    pub readings: Vec<QuotaReading>,
    pub reset_credits: Option<CodexResetCredits>,
}

#[derive(Clone, Debug)]
pub(super) struct CodexResetCredits {
    pub available_count: i64,
    pub next_expires_at: Option<i64>,
    pub offer_revision: Option<String>,
    pub can_consume: bool,
}

#[derive(Clone, Debug)]
pub(super) struct QuotaReading {
    pub label: String,
    pub full_label: String,
    pub remaining_percent: f64,
    pub resets_at: Option<i64>,
    pub reset_description: Option<String>,
}

impl AleraApp {
    pub(super) fn prune_presence_for_tabs(&mut self, tab_ids: &[String]) {
        prune_presence_entries(&mut self.status_data.presence, tab_ids);
    }

    pub(super) fn refresh_status_data(&mut self, cx: &mut Context<Self>) {
        self.refresh_quota_status(false, cx);
        self.refresh_resource_status(cx);
        self.refresh_runtime_status(cx);
        self.refresh_presence_status(cx);
    }

    pub(super) fn refresh_quota_status(&mut self, force: bool, cx: &mut Context<Self>) {
        self.status_data.quota_generation += 1;
        let generation = self.status_data.quota_generation;
        self.status_data.quota_loading = true;
        self.status_data.quota_error = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "agentQuota.snapshot",
                    json!({"forceRefresh": force}),
                    Duration::from_secs(30),
                )
                .await
                .and_then(|value| {
                    let environment = parse_quota_environment(&value);
                    parse_quota_snapshots(value).map(|quotas| (quotas, environment))
                });
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.status_data.quota_generation {
                    return;
                }
                this.status_data.quota_loading = false;
                match result {
                    Ok((quotas, environment)) => {
                        this.status_data.quotas = quotas;
                        this.status_data.quota_environment = environment;
                        this.status_data.quota_error = None;
                    }
                    Err(error) => {
                        this.status_data.quotas.clear();
                        this.status_data.quota_environment.clear();
                        this.status_data.quota_error = Some(error);
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn refresh_resource_status(&mut self, cx: &mut Context<Self>) {
        self.status_data.resource_generation += 1;
        let generation = self.status_data.resource_generation;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("resources.snapshot", json!({"appPid": std::process::id()}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.status_data.resource_generation {
                    return;
                }
                match result {
                    Ok(value) => {
                        this.status_data.resources = Some(value);
                        this.status_data.resource_error = None;
                    }
                    Err(error) => {
                        this.status_data.resources = None;
                        this.status_data.resource_error = Some(error);
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn refresh_runtime_status(&mut self, cx: &mut Context<Self>) {
        self.status_data.runtime_generation += 1;
        let generation = self.status_data.runtime_generation;
        self.status_data.runtime_loading = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("status.get", json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.status_data.runtime_generation {
                    return;
                }
                this.status_data.runtime_loading = false;
                match result {
                    Ok(value) => {
                        this.status_data.runtime = Some(value);
                        this.status_data.runtime_error = None;
                    }
                    Err(error) => {
                        this.status_data.runtime = None;
                        this.status_data.runtime_error = Some(error);
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn refresh_presence_status(&mut self, cx: &mut Context<Self>) {
        self.status_data.presence_generation += 1;
        let generation = self.status_data.presence_generation;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("agentPresence.list", json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.status_data.presence_generation {
                    return;
                }
                if let Ok(value) = result {
                    this.status_data.presence = value.as_array().cloned().unwrap_or_default();
                }
                cx.notify();
            });
        })
        .detach();
    }
}

fn prune_presence_entries(presence: &mut Vec<Value>, tab_ids: &[String]) {
    if tab_ids.is_empty() {
        return;
    }
    presence.retain(|entry| {
        !["tabId", "handle"].into_iter().any(|key| {
            entry
                .get(key)
                .and_then(Value::as_str)
                .is_some_and(|value| tab_ids.iter().any(|tab_id| tab_id == value))
        })
    });
}

fn parse_quota_environment(value: &Value) -> BTreeMap<String, bool> {
    value
        .get("environment")
        .and_then(Value::as_object)
        .into_iter()
        .flatten()
        .filter_map(|(name, present)| present.as_bool().map(|present| (name.clone(), present)))
        .collect()
}

fn parse_quota_snapshots(value: Value) -> Result<Vec<QuotaSnapshot>, String> {
    value
        .get("snapshots")
        .and_then(Value::as_array)
        .ok_or_else(|| "Quota Response Omitted Snapshots".to_owned())?
        .iter()
        .map(parse_quota_snapshot)
        .collect()
}

fn parse_quota_snapshot(value: &Value) -> Result<QuotaSnapshot, String> {
    let provider = required_string(value, "provider")?;
    let mut readings = value
        .get("windows")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .chain(
            value
                .get("buckets")
                .and_then(Value::as_array)
                .into_iter()
                .flatten(),
        )
        .map(|reading| parse_quota_reading(&provider, reading))
        .collect::<Result<Vec<_>, String>>()?;
    readings.sort_by_key(|reading| reading_order(&provider, &reading.full_label));
    Ok(QuotaSnapshot {
        provider,
        account_id: required_string(value, "accountId")?,
        display_name: required_string(value, "displayName")?,
        status: required_string(value, "status")?,
        error: value
            .get("error")
            .and_then(Value::as_str)
            .map(str::to_owned),
        readings,
        reset_credits: value
            .get("rateLimitResetCredits")
            .and_then(parse_codex_reset_credits),
    })
}

fn parse_codex_reset_credits(value: &Value) -> Option<CodexResetCredits> {
    Some(CodexResetCredits {
        available_count: value.get("availableCount")?.as_i64()?,
        next_expires_at: value.get("nextExpiresAt").and_then(Value::as_i64),
        offer_revision: value
            .get("offerRevision")
            .and_then(Value::as_str)
            .map(str::to_owned),
        can_consume: value
            .get("canConsume")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

fn parse_quota_reading(provider: &str, value: &Value) -> Result<QuotaReading, String> {
    let full_label = value
        .get("label")
        .or_else(|| value.get("name"))
        .and_then(Value::as_str)
        .ok_or_else(|| "Quota Reading Omitted Label".to_owned())?
        .to_owned();
    let used_percent = value
        .get("usedPercent")
        .and_then(Value::as_f64)
        .unwrap_or_default();
    Ok(QuotaReading {
        label: compact_reading_label(provider, &full_label),
        full_label,
        remaining_percent: (100.0 - used_percent).clamp(0.0, 100.0),
        resets_at: value.get("resetsAt").and_then(Value::as_i64),
        reset_description: value
            .get("resetDescription")
            .and_then(Value::as_str)
            .map(str::to_owned),
    })
}

fn compact_reading_label(provider: &str, label: &str) -> String {
    let lower = label.to_lowercase();
    if provider == "antigravity" {
        let group = if lower.contains("gemini") { "G" } else { "C/G" };
        return format!("{group}·{}", short_window_label(&lower));
    }
    if provider == "zai" && lower.contains("mcp") {
        return "MCP".to_owned();
    }
    if provider == "claude" && lower.contains("fable") {
        return "F".to_owned();
    }
    if provider == "minimax" {
        let model = label
            .strip_suffix(" Weekly")
            .or_else(|| label.strip_suffix(" weekly"))
            .unwrap_or(label)
            .strip_prefix("MiniMax-")
            .or_else(|| label.strip_prefix("Minimax-"))
            .unwrap_or(label)
            .trim();
        let compact_model = match model.to_lowercase().as_str() {
            "general" => "G".to_owned(),
            "video" => "V".to_owned(),
            _ => compact_model_label(model),
        };
        return format!("{compact_model}·{}", short_window_label(&lower));
    }
    short_window_label(&lower).to_owned()
}

fn compact_model_label(model: &str) -> String {
    let trimmed = model.trim();
    if trimmed.chars().count() <= 6 {
        return trimmed.to_owned();
    }
    let chars = trimmed.char_indices().collect::<Vec<_>>();
    for (index, (offset, character)) in chars.iter().enumerate() {
        if !character.eq_ignore_ascii_case(&'m') {
            continue;
        }
        let mut end = *offset + character.len_utf8();
        let mut saw_digit = false;
        for (_, next) in chars.iter().skip(index + 1) {
            if next.is_ascii_digit() {
                saw_digit = true;
                end += next.len_utf8();
            } else if *next == '.' && saw_digit {
                end += next.len_utf8();
            } else {
                break;
            }
        }
        if saw_digit {
            return trimmed[*offset..end].to_owned();
        }
    }
    trimmed.chars().take(6).collect()
}

fn short_window_label(label: &str) -> &str {
    if label.contains("5 hour") || label.contains("5h") {
        "5H"
    } else if label.contains("weekly") || label.contains("week") {
        "W"
    } else if label.contains("month") {
        "M"
    } else if label.contains("day") {
        "D"
    } else {
        "Q"
    }
}

fn reading_order(provider: &str, label: &str) -> u8 {
    let lower = label.to_lowercase();
    if provider == "antigravity" {
        let group = if lower.contains("gemini") { 0 } else { 10 };
        return group + u8::from(!(lower.contains("5 hour") || lower.contains("5h")));
    }
    if lower.contains("5 hour") || lower.contains("5h") {
        0
    } else if lower.contains("week") {
        1
    } else if lower.contains("fable") {
        2
    } else {
        3
    }
}

fn required_string(value: &Value, key: &str) -> Result<String, String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| format!("Quota Response Omitted {key}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_remaining_quota_readings_in_flutter_order() {
        let snapshots = parse_quota_snapshots(json!({
            "snapshots": [{
                "provider": "antigravity",
                "accountId": "default",
                "displayName": "Antigravity",
                "status": "ok",
                "windows": [],
                "buckets": [
                    {"name": "Gemini Models - Weekly", "usedPercent": 25},
                    {"name": "Gemini Models - 5 Hour", "usedPercent": 10},
                    {"name": "Claude And GPT Models - Weekly", "usedPercent": 50},
                    {"name": "Claude And GPT Models - 5 Hour", "usedPercent": 40}
                ]
            }]
        }))
        .unwrap();
        let readings = &snapshots[0].readings;
        assert_eq!(
            readings
                .iter()
                .map(|reading| reading.label.as_str())
                .collect::<Vec<_>>(),
            ["G·5H", "G·W", "C/G·5H", "C/G·W"]
        );
        assert_eq!(readings[0].remaining_percent, 90.0);
    }

    #[test]
    fn compacts_minimax_model_bucket_labels_like_flutter() {
        assert_eq!(
            compact_reading_label("minimax", "MiniMax-M2.5 Weekly"),
            "M2.5·W"
        );
        assert_eq!(
            compact_reading_label("minimax", "MiniMax-General Weekly"),
            "G·W"
        );
        assert_eq!(
            compact_reading_label("minimax", "MiniMax-Video Weekly"),
            "V·W"
        );
    }

    #[test]
    fn prunes_presence_by_tab_or_terminal_handle() {
        let mut presence = vec![
            json!({"tabId": "tab-1", "handle": "session-1"}),
            json!({"tabId": "tab-2", "handle": "session-2"}),
            json!({"tabId": "tab-3", "handle": "session-3"}),
        ];

        prune_presence_entries(&mut presence, &["tab-1".into(), "session-3".into()]);

        assert_eq!(
            presence,
            vec![json!({"tabId": "tab-2", "handle": "session-2"})]
        );
    }
}

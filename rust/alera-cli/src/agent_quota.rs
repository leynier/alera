use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use regex::Regex;
use reqwest::header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
#[cfg(target_os = "macos")]
use sha2::{Digest, Sha256};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader as AsyncBufReader};
use tokio::process::Command;
use tokio::sync::Semaphore;

const FETCH_TIMEOUT: Duration = Duration::from_secs(12);
const PTY_TIMEOUT: Duration = Duration::from_secs(18);
const SESSION_WINDOW_MINUTES: i64 = 300;
const WEEKLY_WINDOW_MINUTES: i64 = 10_080;
const AGENT_QUOTA_CLI_CONCURRENCY: usize = 2;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProxyRequest {
    id: i64,
    #[serde(rename = "type")]
    request_type: String,
    #[serde(default)]
    payload: Value,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct AgentQuotaFetchRequest {
    #[serde(default)]
    providers: Vec<String>,
    #[serde(default = "default_true")]
    claude_default_enabled: bool,
    #[serde(default)]
    claude_profiles: Vec<ClaudeProfileRequest>,
    #[serde(default)]
    environment_names: EnvironmentNames,
    #[serde(default = "default_true")]
    allow_cli_fallback: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeProfileRequest {
    alias: String,
    profile: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", default)]
struct EnvironmentNames {
    kimi_api_key: String,
    zai_api_key: String,
    zai_base_url: String,
    minimax_api_key: String,
    minimax_api_host: String,
}

impl Default for EnvironmentNames {
    fn default() -> Self {
        Self {
            kimi_api_key: KIMI_API_KEY_ENV.to_string(),
            zai_api_key: "ZAI_API_KEY".to_string(),
            zai_base_url: "ZAI_BASE_URL".to_string(),
            minimax_api_key: "MINIMAX_API_KEY".to_string(),
            minimax_api_host: "MINIMAX_API_HOST".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct QuotaWindow {
    label: String,
    used_percent: f64,
    window_minutes: Option<i64>,
    resets_at: Option<i64>,
    reset_description: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct QuotaBucket {
    name: String,
    used_percent: f64,
    window_minutes: Option<i64>,
    resets_at: Option<i64>,
    reset_description: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct QuotaSnapshot {
    provider: String,
    account_id: String,
    display_name: String,
    status: String,
    updated_at: i64,
    error: Option<String>,
    windows: Vec<QuotaWindow>,
    buckets: Vec<QuotaBucket>,
}

impl QuotaSnapshot {
    fn unavailable(
        provider: &str,
        account_id: &str,
        display_name: &str,
        error: impl Into<String>,
    ) -> Self {
        Self {
            provider: provider.to_string(),
            account_id: account_id.to_string(),
            display_name: display_name.to_string(),
            status: "unavailable".to_string(),
            updated_at: now_millis(),
            error: Some(error.into()),
            windows: Vec::new(),
            buckets: Vec::new(),
        }
    }

    fn error(
        provider: &str,
        account_id: &str,
        display_name: &str,
        error: impl Into<String>,
    ) -> Self {
        Self {
            provider: provider.to_string(),
            account_id: account_id.to_string(),
            display_name: display_name.to_string(),
            status: "error".to_string(),
            updated_at: now_millis(),
            error: Some(error.into()),
            windows: Vec::new(),
            buckets: Vec::new(),
        }
    }

    fn ok(
        provider: &str,
        account_id: &str,
        display_name: &str,
        windows: Vec<QuotaWindow>,
        buckets: Vec<QuotaBucket>,
    ) -> Self {
        Self {
            provider: provider.to_string(),
            account_id: account_id.to_string(),
            display_name: display_name.to_string(),
            status: "ok".to_string(),
            updated_at: now_millis(),
            error: None,
            windows,
            buckets,
        }
    }
}

pub(crate) async fn run_runtime_proxy() -> i32 {
    let stdin = tokio::io::stdin();
    let mut lines = AsyncBufReader::new(stdin).lines();
    let mut stdout = tokio::io::stdout();
    while let Ok(Some(line)) = lines.next_line().await {
        let response = match serde_json::from_str::<ProxyRequest>(&line) {
            Ok(request) => handle_proxy_request(request).await,
            Err(error) => json!({
                "id": Value::Null,
                "ok": false,
                "error": format!("Invalid runtime proxy request: {error}"),
            }),
        };
        let mut encoded = match serde_json::to_vec(&response) {
            Ok(value) => value,
            Err(error) => {
                eprintln!("runtime proxy response serialization failed: {error}");
                return 1;
            }
        };
        encoded.push(b'\n');
        if stdout.write_all(&encoded).await.is_err() || stdout.flush().await.is_err() {
            return 1;
        }
    }
    0
}

async fn handle_proxy_request(request: ProxyRequest) -> Value {
    let result = match request.request_type.as_str() {
        "agentQuota.fetch" => fetch_agent_quotas(request.payload).await,
        other => Err(anyhow!("Unsupported runtime proxy request: {other}")),
    };
    match result {
        Ok(payload) => json!({ "id": request.id, "ok": true, "payload": payload }),
        Err(error) => json!({
            "id": request.id,
            "ok": false,
            "error": redact_error(&error.to_string()),
        }),
    }
}

pub(crate) async fn fetch_agent_quotas(payload: Value) -> Result<Value> {
    let request: AgentQuotaFetchRequest =
        serde_json::from_value(payload).context("Invalid agent quota request")?;
    let providers = if request.providers.is_empty() {
        vec![
            "claude".to_string(),
            "codex".to_string(),
            "kimi".to_string(),
            "grok".to_string(),
            "antigravity".to_string(),
            "minimax".to_string(),
            "zai".to_string(),
        ]
    } else {
        request.providers.clone()
    };

    let cli_permits = Arc::new(Semaphore::new(AGENT_QUOTA_CLI_CONCURRENCY));
    let mut tasks = tokio::task::JoinSet::new();
    for provider in providers {
        match provider.as_str() {
            "claude" => {
                if request.claude_default_enabled {
                    let permits = Arc::clone(&cli_permits);
                    let allow_cli_fallback = request.allow_cli_fallback;
                    tasks.spawn(
                        async move { fetch_claude(None, permits, allow_cli_fallback).await },
                    );
                }
                for profile in &request.claude_profiles {
                    let profile = profile.clone();
                    let permits = Arc::clone(&cli_permits);
                    let allow_cli_fallback = request.allow_cli_fallback;
                    tasks.spawn(async move {
                        fetch_claude(Some(&profile), permits, allow_cli_fallback).await
                    });
                }
            }
            "codex" => {
                let permits = Arc::clone(&cli_permits);
                tasks.spawn(async move {
                    let _permit = permits.acquire_owned().await.ok();
                    fetch_codex().await
                });
            }
            "kimi" => {
                let names = request.environment_names.clone();
                tasks.spawn(async move { fetch_kimi(&names).await });
            }
            "grok" => {
                tasks.spawn(fetch_grok());
            }
            "antigravity" => {
                let permits = Arc::clone(&cli_permits);
                tasks.spawn(async move {
                    let _permit = permits.acquire_owned().await.ok();
                    fetch_tui_provider("antigravity", "Antigravity", "agy", "/usage").await
                });
            }
            "minimax" => {
                let names = request.environment_names.clone();
                tasks.spawn(async move { fetch_minimax(&names).await });
            }
            "zai" => {
                let names = request.environment_names.clone();
                tasks.spawn(async move { fetch_zai(&names).await });
            }
            _ => {}
        }
    }
    let mut snapshots = Vec::new();
    while let Some(result) = tasks.join_next().await {
        if let Ok(snapshot) = result {
            snapshots.push(snapshot);
        }
    }
    snapshots.sort_by(|left, right| {
        left.provider
            .cmp(&right.provider)
            .then(left.account_id.cmp(&right.account_id))
    });

    let environment = BTreeMap::from([
        (
            request.environment_names.kimi_api_key.clone(),
            environment_present(&request.environment_names.kimi_api_key),
        ),
        (
            request.environment_names.zai_api_key.clone(),
            environment_present(&request.environment_names.zai_api_key),
        ),
        (
            request.environment_names.zai_base_url.clone(),
            environment_present(&request.environment_names.zai_base_url),
        ),
        (
            request.environment_names.minimax_api_key.clone(),
            environment_present(&request.environment_names.minimax_api_key),
        ),
        (
            request.environment_names.minimax_api_host.clone(),
            environment_present(&request.environment_names.minimax_api_host),
        ),
    ]);
    Ok(json!({ "snapshots": snapshots, "environment": environment }))
}

include!("agent_quota/tui.rs");
include!("agent_quota/codex.rs");
include!("agent_quota/grok.rs");
include!("agent_quota/kimi.rs");
include!("agent_quota/plans.rs");

fn numeric(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .or_else(|| value.as_str().and_then(|raw| raw.parse::<f64>().ok()))
}

fn parse_timestamp_millis(value: &str) -> Option<i64> {
    chrono::DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|date| date.timestamp_millis())
}

fn normalize_timestamp_millis(value: i64) -> i64 {
    if value < 10_000_000_000 {
        value * 1000
    } else {
        value
    }
}

fn strip_terminal_sequences(value: &str) -> String {
    let ansi = Regex::new(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))").unwrap();
    let controls = Regex::new(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]").unwrap();
    controls
        .replace_all(&ansi.replace_all(value, ""), "")
        .to_string()
}

fn environment_present(name: &str) -> bool {
    environment_secret(name).is_some()
}

fn environment_secret(name: &str) -> Option<String> {
    if name.trim().is_empty() {
        return None;
    }
    let value = std::env::var(name).ok()?;
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn home_dir() -> Option<PathBuf> {
    dirs::home_dir()
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn redact_error(value: &str) -> String {
    let bearer = Regex::new(r"(?i)bearer\s+[A-Za-z0-9._~+/=-]+").unwrap();
    let secret = Regex::new(r"(?i)(sk-[A-Za-z0-9_-]{8,}|[A-Za-z0-9_-]{32,})").unwrap();
    secret
        .replace_all(
            &bearer.replace_all(value, "Bearer [redacted]"),
            "[redacted]",
        )
        .to_string()
}

#[cfg(test)]
mod tests;

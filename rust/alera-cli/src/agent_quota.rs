use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::RuntimeStore;
use anyhow::{anyhow, Context, Result};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use regex::Regex;
use reqwest::header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader as AsyncBufReader};
use tokio::sync::Semaphore;

const FETCH_TIMEOUT: Duration = Duration::from_secs(12);
/// Budget for a credential probe that macOS may answer with a keychain access
/// dialog. Nothing here can dismiss that dialog, so a short timeout would kill
/// the probe before the user could allow it and report a signed-in account as
/// signed out.
const KEYCHAIN_TIMEOUT: Duration = Duration::from_secs(15);
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
    #[serde(default)]
    environment_values: BTreeMap<String, String>,
    /// Retained for older clients; Claude snapshot never opens a TUI.
    #[serde(default)]
    #[allow(dead_code)]
    allow_cli_fallback: bool,
}

#[derive(Debug, Clone, Default)]
struct QuotaEnvironment {
    overrides: BTreeMap<String, String>,
}

impl QuotaEnvironment {
    fn from_request(request: &AgentQuotaFetchRequest) -> Self {
        let overrides = request
            .environment_values
            .iter()
            .filter(|(name, value)| {
                request.environment_names.contains(name)
                    && !name.trim().is_empty()
                    && !value.trim().is_empty()
            })
            .map(|(name, value)| (name.clone(), value.trim().to_string()))
            .collect();
        Self { overrides }
    }

    async fn value(&self, name: &str) -> Option<String> {
        match environment_secret(name).await {
            Some(value) => Some(value),
            None => self.overrides.get(name).cloned(),
        }
    }

    async fn present(&self, name: &str) -> bool {
        self.value(name).await.is_some()
    }
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

impl EnvironmentNames {
    fn contains(&self, candidate: &str) -> bool {
        [
            &self.kimi_api_key,
            &self.zai_api_key,
            &self.zai_base_url,
            &self.minimax_api_key,
            &self.minimax_api_host,
        ]
        .iter()
        .any(|name| name.as_str() == candidate)
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

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct CodexResetCredits {
    available_count: i64,
    total_earned_count: Option<i64>,
    next_expires_at: Option<i64>,
    offer_revision: String,
    can_consume: bool,
}

#[derive(Debug, Clone, Serialize)]
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
    #[serde(skip_serializing_if = "Option::is_none")]
    rate_limit_reset_credits: Option<Box<CodexResetCredits>>,
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
            rate_limit_reset_credits: None,
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
            rate_limit_reset_credits: None,
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
            rate_limit_reset_credits: None,
        }
    }
}

pub(crate) async fn run_runtime_proxy() -> i32 {
    let store = RuntimeStore::open(&crate::runtime_dir(&crate::cli::RuntimeDirArgs {
        runtime_dir: None,
    }))
    .await;
    let stdin = tokio::io::stdin();
    let mut lines = AsyncBufReader::new(stdin).lines();
    let mut stdout = tokio::io::stdout();
    while let Ok(Some(line)) = lines.next_line().await {
        let response = match serde_json::from_str::<ProxyRequest>(&line) {
            Ok(request) => handle_proxy_request(request, store.as_ref().ok()).await,
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

async fn handle_proxy_request(request: ProxyRequest, store: Option<&RuntimeStore>) -> Value {
    let result = match request.request_type.as_str() {
        "agentQuota.fetch" => fetch_agent_quotas(request.payload).await,
        "agentQuota.fetchClaudeTui" => fetch_claude_tui_proxy(request.payload).await,
        "agentQuota.consumeCodexResetCredit" => match store {
            Some(store) => consume_codex_reset_credit(store, request.payload).await,
            None => Err(anyhow!(
                "Codex reset attempt storage is unavailable in this runtime"
            )),
        },
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

async fn fetch_claude_tui_proxy(payload: Value) -> Result<Value> {
    let account_id = payload
        .get("accountId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("accountId must be a non-empty string"))?;
    let display_name = payload
        .get("displayName")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(account_id);
    let snapshot = fetch_claude_tui(account_id, display_name).await;
    Ok(json!({
        "snapshot": snapshot.clone(),
        "snapshots": [snapshot],
        "environment": {},
    }))
}

pub(crate) async fn fetch_agent_quotas(payload: Value) -> Result<Value> {
    let request: AgentQuotaFetchRequest =
        serde_json::from_value(payload).context("Invalid agent quota request")?;
    let environment = QuotaEnvironment::from_request(&request);
    let providers = if request.providers.is_empty() {
        vec![
            "claude".to_string(),
            "codex".to_string(),
            "kimi".to_string(),
            "grok".to_string(),
            "cursor".to_string(),
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
                    tasks.spawn(async move { fetch_claude(None).await });
                }
                for profile in &request.claude_profiles {
                    let profile = profile.clone();
                    tasks.spawn(async move { fetch_claude(Some(&profile)).await });
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
                let environment = environment.clone();
                tasks.spawn(async move { fetch_kimi(&names, &environment).await });
            }
            "grok" => {
                tasks.spawn(fetch_grok());
            }
            "cursor" => {
                tasks.spawn(fetch_cursor());
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
                let environment = environment.clone();
                tasks.spawn(async move { fetch_minimax(&names, &environment).await });
            }
            "zai" => {
                let names = request.environment_names.clone();
                let environment = environment.clone();
                tasks.spawn(async move { fetch_zai(&names, &environment).await });
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

    let mut environment_presence = BTreeMap::new();
    for name in [
        &request.environment_names.kimi_api_key,
        &request.environment_names.zai_api_key,
        &request.environment_names.zai_base_url,
        &request.environment_names.minimax_api_key,
        &request.environment_names.minimax_api_host,
    ] {
        let present = environment.present(name).await;
        environment_presence.insert(name.clone(), present);
    }
    let environment = environment_presence;
    Ok(json!({ "snapshots": snapshots, "environment": environment }))
}

include!("agent_quota/claude.rs");
include!("agent_quota/tui.rs");
include!("agent_quota/codex.rs");
include!("agent_quota/codex_reset_store.rs");
include!("agent_quota/grok.rs");
include!("agent_quota/cursor.rs");
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

async fn environment_secret(name: &str) -> Option<String> {
    if name.trim().is_empty() {
        return None;
    }
    let value = shell_environment_value(name).await?;
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

/// One variable as the user's shell sees it.
///
/// A quota lookup runs inside the sidecar, which a GUI launch starts with a
/// minimal environment, so reading the process environment alone would miss
/// every override the user exported from their shell rc files. A terminal tab
/// in the same app sees them because the shell sources those files itself.
async fn shell_environment_value(name: &str) -> Option<String> {
    crate::login_shell_environment::login_shell_variable(name).await
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

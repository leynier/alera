const OPENCODE_GO_PROVIDER: &str = "opencode-go";
const OPENCODE_ZEN_PROVIDER: &str = "opencode";
const OPENCODE_GO_USAGE_URL: &str = "https://opencode.ai/zen/go/v1/usage";
const OPENCODE_GO_LIMITS: [(i64, &str); 3] = [
    (5 * 60, "5 Hour"),
    (7 * 24 * 60, "Weekly"),
    (30 * 24 * 60, "Monthly"),
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct QuotaAmount {
    label: String,
    currency: String,
    spent_amount: Option<f64>,
    remaining_amount: Option<f64>,
    limit_amount: Option<f64>,
    resets_at: Option<i64>,
    reset_description: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
struct OpenCodeUsageEntry {
    provider: String,
    cost: f64,
    created_at: i64,
}

async fn fetch_opencode_snapshot(account: &str) -> QuotaSnapshot {
    let display_name = if account == "go" {
        "OpenCode Go"
    } else {
        "OpenCode Zen"
    };
    let provider = if account == "go" {
        OPENCODE_GO_PROVIDER
    } else {
        OPENCODE_ZEN_PROVIDER
    };

    if account == "go" {
        return fetch_opencode_go_snapshot(display_name).await;
    }

    let Some(_api_key) = opencode_auth_key(provider).await else {
        return QuotaSnapshot::unavailable(
            "opencode",
            account,
            display_name,
            "OpenCode Zen API key was not found",
        );
    };
    let Some(database) = opencode_database_path().await else {
        return QuotaSnapshot::unavailable(
            "opencode",
            account,
            display_name,
            "OpenCode local database was not found",
        );
    };
    let entries = match read_opencode_usage(&database).await {
        Ok(entries) => entries,
        Err(error) => {
            return QuotaSnapshot::error(
                "opencode",
                account,
                display_name,
                format!("Unable to read OpenCode usage: {error}"),
            );
        }
    };
    let now = now_millis();
    let month_start = now - 30 * 24 * 60 * 60 * 1000;
    let spent = entries
        .into_iter()
        .filter(|entry| entry.provider == provider && entry.created_at >= month_start)
        .map(|entry| entry.cost)
        .sum::<f64>();
    QuotaSnapshot::estimated(
        "opencode",
        account,
        display_name,
        Vec::new(),
        vec![QuotaAmount {
            label: "Local Spend (30d)".to_string(),
            currency: "USD".to_string(),
            spent_amount: Some(spent.max(0.0)),
            remaining_amount: None,
            limit_amount: None,
            resets_at: None,
            reset_description: Some("Host-local estimate; Zen balance is unavailable".to_string()),
        }],
    )
}

async fn fetch_opencode_go_snapshot(display_name: &str) -> QuotaSnapshot {
    let Some(api_key) = opencode_auth_key(OPENCODE_GO_PROVIDER).await else {
        return QuotaSnapshot::unavailable(
            "opencode",
            "go",
            display_name,
            "OpenCode Go API key was not found",
        );
    };
    let response = match reqwest::Client::new()
        .get(OPENCODE_GO_USAGE_URL)
        .header(AUTHORIZATION, format!("Bearer {api_key}"))
        .header(ACCEPT, "application/json")
        .timeout(FETCH_TIMEOUT)
        .send()
        .await
    {
        Ok(response) => response,
        Err(error) => {
            return QuotaSnapshot::error(
                "opencode",
                "go",
                display_name,
                format!("OpenCode Go usage request failed: {error}"),
            );
        }
    };
    let status = response.status();
    if status == reqwest::StatusCode::UNAUTHORIZED {
        return QuotaSnapshot::unavailable(
            "opencode",
            "go",
            display_name,
            "OpenCode Go API key was rejected",
        );
    }
    if status == reqwest::StatusCode::FORBIDDEN {
        return QuotaSnapshot::unavailable(
            "opencode",
            "go",
            display_name,
            "OpenCode Go subscription is not active",
        );
    }
    if !status.is_success() {
        return QuotaSnapshot::error(
            "opencode",
            "go",
            display_name,
            format!("OpenCode Go usage request failed (HTTP {status})"),
        );
    }
    let data: Value = match response.json().await {
        Ok(value) => value,
        Err(error) => {
            return QuotaSnapshot::error(
                "opencode",
                "go",
                display_name,
                format!("Unable to parse OpenCode Go usage: {error}"),
            );
        }
    };
    match parse_opencode_go_usage(&data) {
        Some(windows) => QuotaSnapshot::ok("opencode", "go", display_name, windows, Vec::new()),
        None => QuotaSnapshot::error(
            "opencode",
            "go",
            display_name,
            "OpenCode Go usage response did not include usage windows",
        ),
    }
}

async fn opencode_database_path() -> Option<PathBuf> {
    let data_dirs = opencode_data_dirs().await;
    if let Some(value) = shell_environment_value("OPENCODE_DB").await {
        let path = PathBuf::from(value.trim());
        if path.is_absolute() {
            return Some(path);
        }
        if !path.as_os_str().is_empty() {
            return data_dirs.first().map(|data_dir| data_dir.join(path));
        }
    }
    data_dirs
        .iter()
        .map(|data_dir| data_dir.join("opencode.db"))
        .find(|path| path.exists())
        .or_else(|| {
            data_dirs
                .first()
                .map(|data_dir| data_dir.join("opencode.db"))
        })
}

async fn opencode_data_dirs() -> Vec<PathBuf> {
    let explicit = shell_environment_value("OPENCODE_DATA_DIR").await;
    let xdg_data_home = shell_environment_value("XDG_DATA_HOME").await;
    let home = home_dir();
    let platform_data = if cfg!(any(target_os = "windows", target_os = "macos")) {
        dirs::data_local_dir()
    } else {
        None
    };
    opencode_data_dir_candidates(
        explicit.as_deref(),
        xdg_data_home.as_deref(),
        home.as_deref(),
        platform_data.as_deref(),
    )
}

fn opencode_data_dir_candidates(
    explicit: Option<&str>,
    xdg_data_home: Option<&str>,
    home: Option<&std::path::Path>,
    platform_data: Option<&std::path::Path>,
) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(value) = explicit {
        let path = PathBuf::from(value.trim());
        if !path.as_os_str().is_empty() {
            paths.push(path);
        }
        return paths;
    }
    if let Some(value) = xdg_data_home {
        let path = PathBuf::from(value.trim());
        if !path.as_os_str().is_empty() {
            paths.push(path.join("opencode"));
        }
    }
    if let Some(home) = home {
        paths.push(home.join(".local/share/opencode"));
    }
    if let Some(platform_data) = platform_data {
        paths.push(platform_data.join("opencode"));
    }
    let mut unique = Vec::with_capacity(paths.len());
    for path in paths {
        if !unique.iter().any(|candidate| candidate == &path) {
            unique.push(path);
        }
    }
    unique
}

async fn opencode_auth_key(provider: &str) -> Option<String> {
    for data_dir in opencode_data_dirs().await {
        let path = data_dir.join("auth.json");
        let Ok(raw) = tokio::fs::read_to_string(path).await else {
            continue;
        };
        let Ok(value) = serde_json::from_str(&raw) else {
            continue;
        };
        if let Some(key) = parse_opencode_auth_key(&value, provider) {
            return Some(key);
        }
    }
    None
}

fn parse_opencode_auth_key(value: &Value, provider: &str) -> Option<String> {
    let entry = value.get(provider)?;
    if entry.get("type").and_then(Value::as_str) != Some("api") {
        return None;
    }
    entry
        .get("key")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|key| !key.is_empty())
        .map(ToOwned::to_owned)
}

async fn read_opencode_usage(path: &PathBuf) -> Result<Vec<OpenCodeUsageEntry>> {
    if !path.exists() {
        anyhow::bail!("database does not exist");
    }
    let options = sqlx::sqlite::SqliteConnectOptions::new()
        .filename(path)
        .read_only(true)
        .create_if_missing(false)
        .busy_timeout(std::time::Duration::from_secs(2));
    let pool = sqlx::sqlite::SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .context("opening OpenCode database")?;
    let result = read_message_usage(&pool).await?;
    if !result.is_empty() {
        pool.close().await;
        return Ok(result);
    }
    let result = read_session_message_usage(&pool).await?;
    if !result.is_empty() {
        pool.close().await;
        return Ok(result);
    }
    let result = read_session_usage(&pool).await?;
    pool.close().await;
    Ok(result)
}

async fn read_message_usage(pool: &sqlx::SqlitePool) -> Result<Vec<OpenCodeUsageEntry>> {
    let exists = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'message'",
    )
    .fetch_one(pool)
    .await?;
    if exists == 0 {
        return Ok(Vec::new());
    }
    let rows = sqlx::query("SELECT time_created, data FROM message")
        .fetch_all(pool)
        .await?;
    let mut entries = Vec::new();
    for row in rows {
        let created_at: i64 = row.try_get("time_created")?;
        let data: String = row.try_get("data")?;
        if let Some(entry) = parse_opencode_usage_entry(created_at, &data) {
            entries.push(entry);
        }
    }
    Ok(entries)
}

async fn read_session_message_usage(pool: &sqlx::SqlitePool) -> Result<Vec<OpenCodeUsageEntry>> {
    let exists = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'session_message'",
    )
    .fetch_one(pool)
    .await?;
    if exists == 0 {
        return Ok(Vec::new());
    }
    let rows = sqlx::query("SELECT time_created, data FROM session_message")
        .fetch_all(pool)
        .await?;
    let mut entries = Vec::new();
    for row in rows {
        let created_at: i64 = row.try_get("time_created")?;
        let data: String = row.try_get("data")?;
        if let Some(entry) = parse_session_message_usage_entry(created_at, &data) {
            entries.push(entry);
        }
    }
    Ok(entries)
}

async fn read_session_usage(pool: &sqlx::SqlitePool) -> Result<Vec<OpenCodeUsageEntry>> {
    let exists = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'session'",
    )
    .fetch_one(pool)
    .await?;
    if exists == 0 {
        return Ok(Vec::new());
    }
    let rows = sqlx::query("SELECT time_created, cost, model FROM session")
        .fetch_all(pool)
        .await?;
    let mut entries = Vec::new();
    for row in rows {
        let created_at: i64 = row.try_get("time_created")?;
        let cost: f64 = row.try_get("cost")?;
        let model: Option<String> = row.try_get("model")?;
        let Some(model) = model.and_then(|value| serde_json::from_str::<Value>(&value).ok()) else {
            continue;
        };
        let Some(provider) = model
            .get("providerID")
            .or_else(|| model.get("providerId"))
            .and_then(Value::as_str)
        else {
            continue;
        };
        if cost.is_finite() && cost >= 0.0 {
            entries.push(OpenCodeUsageEntry {
                provider: provider.to_string(),
                cost,
                created_at,
            });
        }
    }
    Ok(entries)
}

fn parse_opencode_usage_entry(created_at: i64, raw: &str) -> Option<OpenCodeUsageEntry> {
    let value: Value = serde_json::from_str(raw).ok()?;
    let info = value.get("info").unwrap_or(&value);
    if info.get("role").and_then(Value::as_str) != Some("assistant") {
        return None;
    }
    let provider = info
        .get("providerID")
        .or_else(|| info.get("providerId"))
        .and_then(Value::as_str)?
        .trim();
    let cost = info.get("cost").and_then(numeric)?;
    (provider == OPENCODE_GO_PROVIDER || provider == OPENCODE_ZEN_PROVIDER).then_some(
        OpenCodeUsageEntry {
            provider: provider.to_string(),
            cost: cost.max(0.0),
            created_at,
        },
    )
}

fn parse_session_message_usage_entry(created_at: i64, raw: &str) -> Option<OpenCodeUsageEntry> {
    let value: Value = serde_json::from_str(raw).ok()?;
    if value.get("type").and_then(Value::as_str) != Some("assistant") {
        return None;
    }
    let model = value.get("model")?;
    let provider = model
        .get("providerID")
        .or_else(|| model.get("providerId"))
        .and_then(Value::as_str)?
        .trim();
    let cost = value.get("cost").and_then(numeric)?;
    (provider == OPENCODE_GO_PROVIDER || provider == OPENCODE_ZEN_PROVIDER).then_some(
        OpenCodeUsageEntry {
            provider: provider.to_string(),
            cost: cost.max(0.0),
            created_at,
        },
    )
}

fn parse_opencode_go_usage(data: &Value) -> Option<Vec<QuotaWindow>> {
    let usage = data.get("usage")?;
    let mut windows = Vec::new();
    for (key, (minutes, label)) in [
        ("rolling", OPENCODE_GO_LIMITS[0]),
        ("weekly", OPENCODE_GO_LIMITS[1]),
        ("monthly", OPENCODE_GO_LIMITS[2]),
    ] {
        let item = usage.get(key)?;
        let percent = numeric(item.get("percent")?)?;
        let resets_at = item
            .get("resetsAt")
            .and_then(Value::as_str)
            .and_then(parse_timestamp_millis);
        windows.push(QuotaWindow {
            label: label.to_string(),
            used_percent: percent.clamp(0.0, 100.0),
            window_minutes: Some(minutes),
            resets_at,
            reset_description: Some("OpenCode account usage".to_string()),
        });
    }
    Some(windows)
}

#[cfg(test)]
mod opencode_tests {
    use super::*;

    include!("opencode_tests.rs");
}

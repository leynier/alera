const OPENCODE_GO_PROVIDER: &str = "opencode-go";
const OPENCODE_ZEN_PROVIDER: &str = "opencode";
const OPENCODE_GO_LIMITS: [(i64, f64, &str); 3] = [
    (5 * 60, 12.0, "5 Hour"),
    (7 * 24 * 60, 30.0, "Weekly"),
    (30 * 24 * 60, 60.0, "Monthly"),
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

fn estimated_snapshot(
    account_id: &str,
    display_name: &str,
    windows: Vec<QuotaWindow>,
    amounts: Vec<QuotaAmount>,
) -> QuotaSnapshot {
    QuotaSnapshot {
        provider: "opencode".to_string(),
        account_id: account_id.to_string(),
        display_name: display_name.to_string(),
        status: "ok".to_string(),
        updated_at: now_millis(),
        error: None,
        windows,
        buckets: Vec::new(),
        amounts,
        data_quality: Some("estimated".to_string()),
        scope: Some("host".to_string()),
        rate_limit_reset_credits: None,
    }
}

#[derive(Debug, Clone, PartialEq)]
struct OpenCodeUsageEntry {
    provider: String,
    cost: f64,
    created_at: i64,
}

async fn fetch_opencode_snapshot(account: &str) -> QuotaSnapshot {
    let provider = if account == "go" {
        OPENCODE_GO_PROVIDER
    } else {
        OPENCODE_ZEN_PROVIDER
    };
    let display_name = if account == "go" {
        "OpenCode Go"
    } else {
        "OpenCode Zen"
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
    let provider_entries = entries
        .into_iter()
        .filter(|entry| entry.provider == provider)
        .collect::<Vec<_>>();
    if account == "go" {
        let windows = opencode_go_windows(&provider_entries, now_millis());
        return estimated_snapshot(account, display_name, windows, Vec::new());
    }
    let now = now_millis();
    let month_start = now - 30 * 24 * 60 * 60 * 1000;
    let spent = provider_entries
        .iter()
        .filter(|entry| entry.created_at >= month_start)
        .map(|entry| entry.cost)
        .sum::<f64>();
    let reset = next_local_month_reset(now);
    estimated_snapshot(
        account,
        display_name,
        Vec::new(),
        vec![QuotaAmount {
            label: "Local Spend (30d)".to_string(),
            currency: "USD".to_string(),
            spent_amount: Some(spent.max(0.0)),
            remaining_amount: None,
            limit_amount: None,
            resets_at: Some(reset),
            reset_description: Some("Host-local estimate; Zen balance is unavailable".to_string()),
        }],
    )
}

async fn opencode_database_path() -> Option<PathBuf> {
    if let Some(value) = shell_environment_value("OPENCODE_DB").await {
        let path = PathBuf::from(value);
        if path.is_absolute() {
            return Some(path);
        }
    }
    let data = if let Some(value) = shell_environment_value("OPENCODE_DATA_DIR").await {
        PathBuf::from(value)
    } else if cfg!(windows) {
        PathBuf::from(shell_environment_value("LOCALAPPDATA").await?)
            .join("opencode")
    } else if let Some(value) = shell_environment_value("XDG_DATA_HOME").await {
        PathBuf::from(value).join("opencode")
    } else {
        home_dir()?.join(".local/share/opencode")
    };
    Some(data.join("opencode.db"))
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
    let result = read_session_usage(&pool).await?;
    pool.close().await;
    Ok(result)
}

async fn read_message_usage(pool: &sqlx::SqlitePool) -> Result<Vec<OpenCodeUsageEntry>> {
    let tables = sqlx::query(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('message', 'session_message')",
    )
    .fetch_all(pool)
    .await?;
    let mut entries = Vec::new();
    for table in tables {
        let name: String = table.try_get("name")?;
        let rows = match name.as_str() {
            "message" => sqlx::query("SELECT time_created, data FROM message")
                .fetch_all(pool)
                .await,
            "session_message" => sqlx::query("SELECT time_created, data FROM session_message")
                .fetch_all(pool)
                .await,
            _ => continue,
        };
        let Ok(rows) = rows else { continue };
        for row in rows {
            let created_at: i64 = row.try_get("time_created")?;
            let data: String = row.try_get("data")?;
            if let Some(entry) = parse_opencode_usage_entry(created_at, &data) {
                entries.push(entry);
            }
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
    let mut entries = Vec::new();
    let Ok(rows) = sqlx::query("SELECT time_created, cost, model FROM session")
        .fetch_all(pool)
        .await else {
        return Ok(Vec::new());
    };
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
    (provider == OPENCODE_GO_PROVIDER || provider == OPENCODE_ZEN_PROVIDER)
        .then_some(OpenCodeUsageEntry {
            provider: provider.to_string(),
            cost: cost.max(0.0),
            created_at,
        })
}

fn opencode_go_windows(entries: &[OpenCodeUsageEntry], now: i64) -> Vec<QuotaWindow> {
    OPENCODE_GO_LIMITS
        .iter()
        .map(|(minutes, limit, label)| {
            let start = now - minutes * 60 * 1000;
            let recent = entries
                .iter()
                .filter(|entry| entry.created_at >= start)
                .collect::<Vec<_>>();
            let used = recent.iter().map(|entry| entry.cost).sum::<f64>();
            let resets_at = recent.iter().map(|entry| entry.created_at).min().map(|oldest| {
                oldest + minutes * 60 * 1000
            });
            QuotaWindow {
                label: (*label).to_string(),
                used_percent: ((used / limit) * 100.0).clamp(0.0, 100.0),
                window_minutes: Some(*minutes),
                resets_at,
                reset_description: Some("Host-local estimate".to_string()),
            }
        })
        .collect()
}

fn next_local_month_reset(now: i64) -> i64 {
    now + 30 * 24 * 60 * 60 * 1000
}

#[cfg(test)]
mod opencode_tests {
    use super::*;

    #[test]
    fn parses_assistant_usage_for_supported_open_code_providers() {
        let entry = parse_opencode_usage_entry(
            1_000,
            r#"{"role":"assistant","providerID":"opencode-go","cost":1.25}"#,
        )
        .expect("entry");
        assert_eq!(entry.provider, OPENCODE_GO_PROVIDER);
        assert_eq!(entry.cost, 1.25);
    }

    #[test]
    fn ignores_user_messages_and_other_providers() {
        assert!(parse_opencode_usage_entry(
            1_000,
            r#"{"role":"user","providerID":"opencode-go","cost":1.25}"#,
        )
        .is_none());
        assert!(parse_opencode_usage_entry(
            1_000,
            r#"{"role":"assistant","providerID":"anthropic","cost":1.25}"#,
        )
        .is_none());
    }

    #[test]
    fn calculates_go_windows_from_dollar_limits() {
        let entries = vec![OpenCodeUsageEntry {
            provider: OPENCODE_GO_PROVIDER.to_string(),
            cost: 6.0,
            created_at: 9_000,
        }];
        let windows = opencode_go_windows(&entries, 10_000);
        assert_eq!(windows.len(), 3);
        assert_eq!(windows[0].used_percent, 50.0);
        assert!(windows[0].resets_at.is_some());
    }
}

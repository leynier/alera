const CURSOR_PERIOD_USAGE_URL: &str =
    "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage";
const MONTHLY_WINDOW_MINUTES: i64 = 43_200;

async fn fetch_cursor() -> QuotaSnapshot {
    let Some(token) = read_cursor_access_token().await else {
        return QuotaSnapshot::unavailable(
            "cursor",
            "default",
            "Cursor",
            "Not signed in to Cursor",
        );
    };
    let client = reqwest::Client::new();
    let response = client
        .post(CURSOR_PERIOD_USAGE_URL)
        .header(AUTHORIZATION, format!("Bearer {token}"))
        .header(CONTENT_TYPE, "application/json")
        .header(ACCEPT, "application/json")
        .header("Connect-Protocol-Version", "1")
        .timeout(FETCH_TIMEOUT)
        .json(&json!({}))
        .send()
        .await;
    let response = match response {
        Ok(value) => value,
        Err(error) => {
            return QuotaSnapshot::error("cursor", "default", "Cursor", redact_error(&error.to_string()))
        }
    };
    let status = response.status();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return QuotaSnapshot::unavailable(
            "cursor",
            "default",
            "Cursor",
            "Cursor session expired; run cursor-agent login",
        );
    }
    if !status.is_success() {
        return QuotaSnapshot::error(
            "cursor",
            "default",
            "Cursor",
            format!("Cursor usage request failed (HTTP {status})"),
        );
    }
    let data: Value = match response.json().await {
        Ok(value) => value,
        Err(error) => {
            return QuotaSnapshot::error("cursor", "default", "Cursor", error.to_string())
        }
    };
    parse_cursor_period_usage(&data)
}

async fn read_cursor_access_token() -> Option<String> {
    let path = cursor_auth_path()?;
    let raw = tokio::fs::read_to_string(path).await.ok()?;
    let parsed: Value = serde_json::from_str(&raw).ok()?;
    let token = parsed
        .get("accessToken")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())?;
    Some(token.to_string())
}

fn cursor_auth_path() -> Option<PathBuf> {
    if let Ok(dir) = std::env::var("CURSOR_CONFIG_DIR") {
        let trimmed = dir.trim();
        if !trimmed.is_empty() {
            return Some(PathBuf::from(trimmed).join("auth.json"));
        }
    }
    let config_dir = std::env::var("XDG_CONFIG_HOME")
        .ok()
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
        .or_else(|| home_dir().map(|home| home.join(".config")))?;
    Some(config_dir.join("cursor").join("auth.json"))
}

fn parse_cursor_period_usage(data: &Value) -> QuotaSnapshot {
    let plan = data.get("planUsage").unwrap_or(data);
    let resets_at = parse_cycle_millis(data.get("billingCycleEnd"));
    let mut windows = Vec::new();
    push_cursor_window(
        &mut windows,
        "Included",
        plan.get("totalPercentUsed"),
        resets_at,
    );
    push_cursor_window(
        &mut windows,
        "Auto",
        plan.get("autoPercentUsed"),
        resets_at,
    );
    push_cursor_window(&mut windows, "API", plan.get("apiPercentUsed"), resets_at);
    if windows.is_empty() {
        QuotaSnapshot::error(
            "cursor",
            "default",
            "Cursor",
            "Cursor usage response did not include plan percentages",
        )
    } else {
        QuotaSnapshot::ok("cursor", "default", "Cursor", windows, Vec::new())
    }
}

fn push_cursor_window(
    windows: &mut Vec<QuotaWindow>,
    label: &str,
    value: Option<&Value>,
    resets_at: Option<i64>,
) {
    let Some(used_percent) = value.and_then(numeric) else {
        return;
    };
    if !used_percent.is_finite() {
        return;
    }
    windows.push(QuotaWindow {
        label: label.to_string(),
        used_percent: used_percent.clamp(0.0, 100.0),
        window_minutes: Some(MONTHLY_WINDOW_MINUTES),
        resets_at,
        reset_description: None,
    });
}

fn parse_cycle_millis(value: Option<&Value>) -> Option<i64> {
    let value = value?;
    if let Some(number) = value.as_i64() {
        return Some(normalize_timestamp_millis(number));
    }
    if let Some(number) = value.as_u64() {
        return Some(normalize_timestamp_millis(number as i64));
    }
    if let Some(number) = value.as_f64() {
        if number.is_finite() {
            return Some(normalize_timestamp_millis(number as i64));
        }
    }
    if let Some(raw) = value.as_str() {
        let trimmed = raw.trim();
        if let Ok(number) = trimmed.parse::<i64>() {
            return Some(normalize_timestamp_millis(number));
        }
        return parse_timestamp_millis(trimmed);
    }
    None
}

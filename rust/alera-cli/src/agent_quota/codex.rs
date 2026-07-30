const CODEX_USAGE_URL: &str = "https://chatgpt.com/backend-api/wham/usage";
const CODEX_RESET_CREDITS_URL: &str =
    "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits";
const CODEX_RESET_CONSUME_URL: &str =
    "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume";
const CODEX_REDEEM_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Debug, Clone)]
struct CodexBackendAuth {
    access_token: String,
    account_id: Option<String>,
}

async fn fetch_codex() -> QuotaSnapshot {
    if let Ok(Ok(Some(snapshot))) =
        tokio::time::timeout(FETCH_TIMEOUT, fetch_codex_via_backend()).await
    {
        return snapshot;
    }
    let mut snapshot = fetch_codex_via_rpc().await;
    if snapshot.status == "ok" && snapshot.rate_limit_reset_credits.is_none() {
        if let Ok(Some(auth)) = read_codex_backend_auth().await {
            if let Ok(Some(credits)) = fetch_codex_reset_credits(&auth).await {
                snapshot.rate_limit_reset_credits = Some(Box::new(credits));
            }
        }
    }
    snapshot
}

async fn fetch_codex_via_backend() -> Result<Option<QuotaSnapshot>> {
    let Some(auth) = read_codex_backend_auth().await? else {
        return Ok(None);
    };
    let response = codex_request(&auth, reqwest::Method::GET, CODEX_USAGE_URL)
        .send()
        .await
        .context("Codex usage request failed")?;
    if !response.status().is_success() {
        return Ok(None);
    }
    let raw: Value = response
        .json()
        .await
        .context("Codex usage response was not valid JSON")?;
    let rate_limit = raw.get("rate_limit").or_else(|| raw.get("rateLimit"));
    let mut windows = Vec::new();
    if let Some(window) = map_backend_codex_window(
        rate_limit.and_then(|value| {
            value
                .get("primary_window")
                .or_else(|| value.get("primaryWindow"))
        }),
        SESSION_WINDOW_MINUTES,
    ) {
        windows.push(window);
    }
    if let Some(window) = map_backend_codex_window(
        rate_limit.and_then(|value| {
            value
                .get("secondary_window")
                .or_else(|| value.get("secondaryWindow"))
        }),
        WEEKLY_WINDOW_MINUTES,
    ) {
        windows.push(window);
    }
    if windows.is_empty() {
        return Ok(None);
    }
    let mut snapshot = QuotaSnapshot::ok("codex", "default", "Codex", windows, Vec::new());
    snapshot.rate_limit_reset_credits = raw
        .get("rate_limit_reset_credits")
        .or_else(|| raw.get("rateLimitResetCredits"))
        .and_then(|value| map_codex_reset_credits(value, auth.account_id.as_deref()))
        .map(Box::new);
    if snapshot.rate_limit_reset_credits.is_none()
        || snapshot
            .rate_limit_reset_credits
            .as_ref()
            .is_some_and(|credits| credits.available_count > 0 && credits.next_expires_at.is_none())
    {
        if let Ok(Some(credits)) = fetch_codex_reset_credits(&auth).await {
            snapshot.rate_limit_reset_credits = Some(Box::new(credits));
        }
    }
    Ok(Some(snapshot))
}

async fn fetch_codex_via_rpc() -> QuotaSnapshot {
    let result = tokio::time::timeout(FETCH_TIMEOUT, async {
        let mut command = windowless_async_command("codex");
        command
            .args(["-s", "read-only", "-a", "untrusted", "app-server"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        crate::login_shell_environment::apply_login_shell_path(&mut command).await;
        let mut child = command
            .spawn()
            .context("Codex CLI not found or could not start")?;
        let mut stdin = child.stdin.take().context("Codex RPC stdin unavailable")?;
        let stdout = child.stdout.take().context("Codex RPC stdout unavailable")?;
        let mut lines = AsyncBufReader::new(stdout).lines();
        stdin
            .write_all(
                b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"alera\",\"version\":\"1.0.0\"}}}\n",
            )
            .await?;
        stdin.flush().await?;
        while let Some(line) = lines.next_line().await? {
            let Ok(message) = serde_json::from_str::<Value>(&line) else {
                continue;
            };
            if message.get("id").and_then(Value::as_i64) == Some(1) {
                stdin
                    .write_all(
                        b"{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{}}\n",
                    )
                    .await?;
                stdin.flush().await?;
                continue;
            }
            if message.get("id").and_then(Value::as_i64) != Some(2) {
                continue;
            }
            let _ = child.kill().await;
            let _ = child.wait().await;
            if let Some(error) = message
                .get("error")
                .and_then(|value| value.get("message"))
                .and_then(Value::as_str)
            {
                return Err(anyhow!(error.to_string()));
            }
            return Ok(message.get("result").cloned().unwrap_or(Value::Null));
        }
        Err(anyhow!("Codex RPC exited before returning quota data"))
    })
    .await;
    let raw = match result {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => return command_error_snapshot("codex", "default", "Codex", error),
        Err(_) => {
            return QuotaSnapshot::error(
                "codex",
                "default",
                "Codex",
                "Codex quota request timed out",
            )
        }
    };
    let limits = raw.get("rateLimits").unwrap_or(&raw);
    let mut windows = Vec::new();
    if let Some(window) = map_codex_window(limits.get("primary"), SESSION_WINDOW_MINUTES) {
        windows.push(window);
    }
    if let Some(window) = map_codex_window(limits.get("secondary"), WEEKLY_WINDOW_MINUTES) {
        windows.push(window);
    }
    if windows.is_empty() {
        return QuotaSnapshot::error(
            "codex",
            "default",
            "Codex",
            "Codex quota response did not include usage windows",
        );
    }
    let mut snapshot = QuotaSnapshot::ok("codex", "default", "Codex", windows, Vec::new());
    snapshot.rate_limit_reset_credits = raw
        .get("rateLimitResetCredits")
        .and_then(|value| map_codex_reset_credits(value, None))
        .map(Box::new);
    snapshot
}

async fn read_codex_backend_auth() -> Result<Option<CodexBackendAuth>> {
    let home = std::env::var("CODEX_HOME")
        .ok()
        .map(PathBuf::from)
        .or_else(|| home_dir().map(|home| home.join(".codex")));
    let Some(home) = home else {
        return Ok(None);
    };
    let contents = match tokio::fs::read_to_string(home.join("auth.json")).await {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error).context("Could not read Codex auth.json"),
    };
    let raw: Value = serde_json::from_str(&contents).context("Codex auth.json is not valid JSON")?;
    let Some(access_token) = raw
        .pointer("/tokens/access_token")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return Ok(None);
    };
    let account_id = raw
        .pointer("/tokens/account_id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string);
    Ok(Some(CodexBackendAuth {
        access_token: access_token.to_string(),
        account_id,
    }))
}

fn codex_request(
    auth: &CodexBackendAuth,
    method: reqwest::Method,
    url: &str,
) -> reqwest::RequestBuilder {
    let client = reqwest::Client::builder()
        .timeout(FETCH_TIMEOUT)
        .build()
        .expect("Codex HTTP client configuration must be valid");
    let mut request = client
        .request(method, url)
        .bearer_auth(&auth.access_token)
        .header("User-Agent", "codex-cli")
        .header("OpenAI-Beta", "codex-1")
        .header("originator", "Codex Desktop");
    if let Some(account_id) = &auth.account_id {
        request = request.header("ChatGPT-Account-Id", account_id);
    }
    request
}

async fn fetch_codex_reset_credits(
    auth: &CodexBackendAuth,
) -> Result<Option<CodexResetCredits>> {
    let response = codex_request(auth, reqwest::Method::GET, CODEX_RESET_CREDITS_URL)
        .send()
        .await
        .context("Codex reset credits request failed")?;
    if !response.status().is_success() {
        return Ok(None);
    }
    let raw: Value = response
        .json()
        .await
        .context("Codex reset credits response was not valid JSON")?;
    Ok(map_codex_reset_credits(&raw, auth.account_id.as_deref()))
}

fn map_codex_reset_credits(value: &Value, account_id: Option<&str>) -> Option<CodexResetCredits> {
    let credits = value.get("credits").and_then(Value::as_array);
    let available_count = value
        .get("available_count")
        .or_else(|| value.get("availableCount"))
        .and_then(Value::as_i64)
        .or_else(|| {
            credits.map(|items| {
                items
                    .iter()
                    .filter(|item| {
                        item.get("status")
                            .and_then(Value::as_str)
                            .is_some_and(|status| status.eq_ignore_ascii_case("available"))
                    })
                    .count() as i64
            })
        })?
        .max(0);
    let total_earned_count = value
        .get("total_earned_count")
        .or_else(|| value.get("totalEarnedCount"))
        .and_then(Value::as_i64)
        .map(|count| count.max(0));
    let direct_expiry = value
        .get("next_expires_at")
        .or_else(|| value.get("nextExpiresAt"))
        .and_then(parse_codex_timestamp);
    let next_expires_at = direct_expiry.or_else(|| {
        credits.and_then(|items| {
            items
                .iter()
                .filter(|item| {
                    item.get("status")
                        .and_then(Value::as_str)
                        .is_some_and(|status| status.eq_ignore_ascii_case("available"))
                })
                .filter_map(|item| {
                    item.get("expires_at")
                        .or_else(|| item.get("expiresAt"))
                        .and_then(parse_codex_timestamp)
                })
                .min()
        })
    });
    let mut hasher = Sha256::new();
    hasher.update(format!(
        "{}:{available_count}:{}:{}",
        account_id.unwrap_or("anonymous"),
        total_earned_count.unwrap_or(-1),
        next_expires_at.unwrap_or(-1)
    ));
    let offer_revision = hex::encode(hasher.finalize());
    Some(CodexResetCredits {
        available_count,
        total_earned_count,
        next_expires_at,
        offer_revision,
        can_consume: account_id.is_some() && available_count > 0,
    })
}

fn parse_codex_timestamp(value: &Value) -> Option<i64> {
    if let Some(number) = value.as_i64() {
        return Some(normalize_timestamp_millis(number));
    }
    let raw = value.as_str()?.trim();
    if let Ok(number) = raw.parse::<i64>() {
        return Some(normalize_timestamp_millis(number));
    }
    parse_timestamp_millis(raw)
}

fn map_backend_codex_window(
    value: Option<&Value>,
    fallback_minutes: i64,
) -> Option<QuotaWindow> {
    let value = value?;
    let used_percent = value
        .get("used_percent")
        .or_else(|| value.get("usedPercent"))
        .and_then(numeric)?
        .clamp(0.0, 100.0);
    let window_minutes = value
        .get("limit_window_seconds")
        .or_else(|| value.get("limitWindowSeconds"))
        .and_then(Value::as_i64)
        .filter(|seconds| *seconds > 0)
        .map(|seconds| (seconds + 59) / 60)
        .unwrap_or(fallback_minutes);
    let resets_at = value
        .get("reset_at")
        .or_else(|| value.get("resetAt"))
        .and_then(parse_codex_timestamp);
    Some(QuotaWindow {
        label: window_label(window_minutes),
        used_percent,
        window_minutes: Some(window_minutes),
        resets_at,
        reset_description: None,
    })
}

async fn fetch_codex_reset_offer() -> Result<(CodexBackendAuth, QuotaSnapshot)> {
    let auth = read_codex_backend_auth()
        .await?
        .ok_or_else(|| anyhow!("Codex is not signed in"))?;
    if auth.account_id.is_none() {
        return Err(anyhow!(
            "Codex account identity is unavailable; refusing to spend a reset credit"
        ));
    }
    let snapshot = fetch_codex_via_backend()
        .await?
        .ok_or_else(|| anyhow!("Codex reset offer is unavailable"))?;
    Ok((auth, snapshot))
}

async fn post_codex_reset_credit(auth: &CodexBackendAuth, idempotency_key: &str) -> Result<String> {
    let response = codex_request(auth, reqwest::Method::POST, CODEX_RESET_CONSUME_URL)
        .header(CONTENT_TYPE, "application/json")
        .json(&json!({ "redeem_request_id": idempotency_key }))
        .timeout(CODEX_REDEEM_TIMEOUT)
        .send()
        .await
        .context("Codex reset request failed")?;
    if !response.status().is_success() {
        return Err(anyhow!("Codex reset failed: HTTP {}", response.status()));
    }
    let payload: Value = response
        .json()
        .await
        .context("Codex reset response was not valid JSON")?;
    let outcome = match payload.get("code").and_then(Value::as_str) {
        Some("reset") => "reset",
        Some("nothing_to_reset") => "nothingToReset",
        Some("no_credit") => "noCredit",
        Some("already_redeemed") => "alreadyRedeemed",
        Some(code) => return Err(anyhow!("Unknown Codex reset outcome: {code}")),
        None => return Err(anyhow!("Codex reset response did not include an outcome")),
    };
    Ok(outcome.to_string())
}

fn map_codex_window(value: Option<&Value>, fallback_minutes: i64) -> Option<QuotaWindow> {
    let value = value?;
    let used_percent = value.get("usedPercent")?.as_f64()?.clamp(0.0, 100.0);
    let window_minutes = value
        .get("windowDurationMins")
        .and_then(Value::as_i64)
        .unwrap_or(fallback_minutes);
    let resets_at = value
        .get("resetsAt")
        .and_then(parse_codex_timestamp);
    Some(QuotaWindow {
        label: window_label(window_minutes),
        used_percent,
        window_minutes: Some(window_minutes),
        resets_at,
        reset_description: None,
    })
}

fn window_label(minutes: i64) -> String {
    match minutes {
        SESSION_WINDOW_MINUTES => "5 Hour".to_string(),
        WEEKLY_WINDOW_MINUTES => "Weekly".to_string(),
        value if value % 1440 == 0 => format!("{} Day", value / 1440),
        value if value % 60 == 0 => format!("{} Hour", value / 60),
        value => format!("{value} Minute"),
    }
}

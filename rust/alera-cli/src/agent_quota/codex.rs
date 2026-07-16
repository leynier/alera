async fn fetch_codex() -> QuotaSnapshot {
    let result = tokio::time::timeout(FETCH_TIMEOUT, async {
        let mut child = Command::new("codex")
            .args(["-s", "read-only", "-a", "untrusted", "app-server"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
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
        QuotaSnapshot::error(
            "codex",
            "default",
            "Codex",
            "Codex quota response did not include usage windows",
        )
    } else {
        QuotaSnapshot::ok("codex", "default", "Codex", windows, Vec::new())
    }
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
        .and_then(Value::as_i64)
        .map(normalize_timestamp_millis);
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

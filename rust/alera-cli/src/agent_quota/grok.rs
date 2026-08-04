async fn fetch_grok() -> QuotaSnapshot {
    let Some(home) = home_dir() else {
        return QuotaSnapshot::unavailable(
            "grok",
            "default",
            "Grok Build",
            "Home directory is unavailable",
        );
    };
    let root = shell_environment_value("GROK_HOME")
        .await
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".grok"));
    let raw = match tokio::fs::read_to_string(root.join("auth.json")).await {
        Ok(value) => value,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return QuotaSnapshot::unavailable(
                "grok",
                "default",
                "Grok Build",
                "Not signed in to Grok",
            )
        }
        Err(_) => {
            return QuotaSnapshot::error(
                "grok",
                "default",
                "Grok Build",
                "Unable to read Grok auth file",
            )
        }
    };
    let parsed: Value = match serde_json::from_str(&raw) {
        Ok(value) => value,
        Err(_) => {
            return QuotaSnapshot::error(
                "grok",
                "default",
                "Grok Build",
                "Grok auth file is invalid",
            )
        }
    };
    let Some(entries) = parsed.as_object() else {
        return QuotaSnapshot::error("grok", "default", "Grok Build", "Grok auth file is invalid");
    };
    let selected = entries
        .iter()
        .filter(|(issuer, _)| issuer.starts_with("https://auth.x.ai"))
        .chain(entries.iter())
        .find_map(|(_, value)| {
            let token = value.get("key").and_then(Value::as_str)?;
            if token.trim().is_empty() {
                return None;
            }
            Some((
                token.to_string(),
                value
                    .get("user_id")
                    .and_then(Value::as_str)
                    .map(str::to_string),
            ))
        });
    let Some((token, user_id)) = selected else {
        return QuotaSnapshot::unavailable(
            "grok",
            "default",
            "Grok Build",
            "Not signed in to Grok",
        );
    };
    let base = shell_environment_value("GROK_CLI_CHAT_PROXY_BASE_URL")
        .await
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "https://cli-chat-proxy.grok.com/v1".to_string());
    let client = reqwest::Client::new();
    let credits = fetch_grok_billing(
        &client,
        &format!("{}/billing?format=credits", base.trim_end_matches('/')),
        &token,
        user_id.as_deref(),
    )
    .await;
    if let Ok(data) = credits {
        let config = data.get("config").unwrap_or(&data);
        if let Some(used_percent) = config.get("creditUsagePercent").and_then(numeric) {
            let reset = config
                .get("currentPeriod")
                .and_then(|value| value.get("end"))
                .or_else(|| config.get("billingPeriodEnd"))
                .and_then(Value::as_str);
            return QuotaSnapshot::ok(
                "grok",
                "default",
                "Grok Build",
                vec![QuotaWindow {
                    label: "Weekly".to_string(),
                    used_percent: used_percent.clamp(0.0, 100.0),
                    window_minutes: Some(WEEKLY_WINDOW_MINUTES),
                    resets_at: reset.and_then(parse_timestamp_millis),
                    reset_description: reset.map(str::to_string),
                }],
                Vec::new(),
            );
        }
    }
    let default_data = match fetch_grok_billing(
        &client,
        &format!("{}/billing", base.trim_end_matches('/')),
        &token,
        user_id.as_deref(),
    )
    .await
    {
        Ok(value) => value,
        Err(error) => return command_error_snapshot("grok", "default", "Grok Build", error),
    };
    let config = default_data.get("config").unwrap_or(&default_data);
    let limit = config
        .get("monthlyLimit")
        .and_then(|value| value.get("val"))
        .and_then(numeric);
    let used = config
        .get("used")
        .and_then(|value| value.get("val"))
        .and_then(numeric);
    match (limit, used) {
        (Some(limit), Some(used)) if limit > 0.0 => QuotaSnapshot::ok(
            "grok",
            "default",
            "Grok Build",
            vec![QuotaWindow {
                label: "Monthly".to_string(),
                used_percent: ((used / limit) * 100.0).clamp(0.0, 100.0),
                window_minutes: Some(43_200),
                resets_at: None,
                reset_description: None,
            }],
            Vec::new(),
        ),
        _ => QuotaSnapshot::unavailable(
            "grok",
            "default",
            "Grok Build",
            "Grok billing response did not include usage",
        ),
    }
}

async fn fetch_grok_billing(
    client: &reqwest::Client,
    url: &str,
    token: &str,
    user_id: Option<&str>,
) -> Result<Value> {
    let mut request = client
        .get(url)
        .header(AUTHORIZATION, format!("Bearer {token}"))
        .header("X-XAI-Token-Auth", "xai-grok-cli")
        .header(ACCEPT, "application/json")
        .timeout(FETCH_TIMEOUT);
    if let Some(user_id) = user_id {
        request = request.header("x-userid", user_id);
    }
    let response = request.send().await?;
    if !response.status().is_success() {
        return Err(anyhow!(
            "Grok usage request failed (HTTP {})",
            response.status()
        ));
    }
    Ok(response.json().await?)
}

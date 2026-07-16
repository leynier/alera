async fn fetch_minimax(names: &EnvironmentNames) -> QuotaSnapshot {
    let Some(api_key) = environment_secret(&names.minimax_api_key) else {
        return QuotaSnapshot::unavailable(
            "minimax",
            "default",
            "MiniMax",
            format!(
                "Environment variable {} is not configured",
                names.minimax_api_key
            ),
        );
    };
    let configured_host = std::env::var(&names.minimax_api_host)
        .unwrap_or_else(|_| "https://api.minimax.io".to_string());
    let endpoint_host = if configured_host.contains("minimaxi") {
        "https://www.minimaxi.com"
    } else {
        "https://www.minimax.io"
    };
    let response = reqwest::Client::new()
        .get(format!("{endpoint_host}/v1/token_plan/remains"))
        .header(AUTHORIZATION, format!("Bearer {api_key}"))
        .header(CONTENT_TYPE, "application/json")
        .timeout(FETCH_TIMEOUT)
        .send()
        .await;
    let response = match response {
        Ok(value) => value,
        Err(error) => {
            return QuotaSnapshot::error("minimax", "default", "MiniMax", error.to_string())
        }
    };
    if !response.status().is_success() {
        return QuotaSnapshot::error(
            "minimax",
            "default",
            "MiniMax",
            format!("MiniMax quota request failed (HTTP {})", response.status()),
        );
    }
    let data: Value = match response.json().await {
        Ok(value) => value,
        Err(error) => {
            return QuotaSnapshot::error("minimax", "default", "MiniMax", error.to_string())
        }
    };
    let models = data
        .get("model_remains")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut buckets = Vec::new();
    for model in models {
        let name = model
            .get("model_name")
            .and_then(Value::as_str)
            .unwrap_or("Model");
        if let Some(bucket) = minimax_bucket(&model, name, false) {
            buckets.push(bucket);
        }
        if let Some(bucket) = minimax_bucket(&model, &format!("{name} Weekly"), true) {
            buckets.push(bucket);
        }
    }
    if buckets.is_empty() {
        QuotaSnapshot::error(
            "minimax",
            "default",
            "MiniMax",
            "MiniMax quota response did not include model quotas",
        )
    } else {
        QuotaSnapshot::ok("minimax", "default", "MiniMax", Vec::new(), buckets)
    }
}

fn minimax_bucket(model: &Value, name: &str, weekly: bool) -> Option<QuotaBucket> {
    let prefix = if weekly {
        "current_weekly"
    } else {
        "current_interval"
    };
    let status = model
        .get(format!("{prefix}_status"))
        .and_then(Value::as_i64);
    if weekly && status == Some(3) {
        return Some(QuotaBucket {
            name: name.to_string(),
            used_percent: 0.0,
            window_minutes: Some(WEEKLY_WINDOW_MINUTES),
            resets_at: model
                .get("weekly_end_time")
                .and_then(Value::as_i64)
                .map(normalize_timestamp_millis),
            reset_description: Some("Unlimited".to_string()),
        });
    }
    let used_percent = model
        .get(format!("{prefix}_remaining_percent"))
        .and_then(numeric)
        .map(|remaining| 100.0 - remaining)
        .or_else(|| {
            let total = model
                .get(format!("{prefix}_total_count"))
                .and_then(numeric)?;
            if total <= 0.0 {
                return None;
            }
            let used = model
                .get(format!("{prefix}_usage_count"))
                .and_then(numeric)?;
            Some((used / total) * 100.0)
        })?;
    let end_key = if weekly {
        "weekly_end_time"
    } else {
        "end_time"
    };
    Some(QuotaBucket {
        name: name.to_string(),
        used_percent: used_percent.clamp(0.0, 100.0),
        window_minutes: Some(if weekly {
            WEEKLY_WINDOW_MINUTES
        } else {
            SESSION_WINDOW_MINUTES
        }),
        resets_at: model
            .get(end_key)
            .and_then(Value::as_i64)
            .map(normalize_timestamp_millis),
        reset_description: None,
    })
}

async fn fetch_zai(names: &EnvironmentNames) -> QuotaSnapshot {
    let Some(api_key) = environment_secret(&names.zai_api_key) else {
        return QuotaSnapshot::unavailable(
            "zai",
            "default",
            "Z.ai",
            format!(
                "Environment variable {} is not configured",
                names.zai_api_key
            ),
        );
    };
    let configured = std::env::var(&names.zai_base_url)
        .unwrap_or_else(|_| "https://api.z.ai/api/anthropic".to_string());
    let parsed = match url::Url::parse(&configured) {
        Ok(value) => value,
        Err(error) => return QuotaSnapshot::error("zai", "default", "Z.ai", error.to_string()),
    };
    if parsed.host_str().is_none() {
        return QuotaSnapshot::error("zai", "default", "Z.ai", "Z.ai base URL has no host");
    }
    let base = parsed.origin().ascii_serialization();
    let response = reqwest::Client::new()
        .get(format!("{base}/api/monitor/usage/quota/limit"))
        .header(AUTHORIZATION, api_key)
        .header(ACCEPT, "application/json")
        .header(CONTENT_TYPE, "application/json")
        .timeout(FETCH_TIMEOUT)
        .send()
        .await;
    let response = match response {
        Ok(value) => value,
        Err(error) => return QuotaSnapshot::error("zai", "default", "Z.ai", error.to_string()),
    };
    if !response.status().is_success() {
        return QuotaSnapshot::error(
            "zai",
            "default",
            "Z.ai",
            format!("Z.ai quota request failed (HTTP {})", response.status()),
        );
    }
    let response: Value = match response.json().await {
        Ok(value) => value,
        Err(error) => return QuotaSnapshot::error("zai", "default", "Z.ai", error.to_string()),
    };
    let limits = response
        .get("data")
        .and_then(|value| value.get("limits"))
        .or_else(|| response.get("limits"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut buckets = Vec::new();
    for limit in limits {
        let kind = limit.get("type").and_then(Value::as_str).unwrap_or("Quota");
        let percentage = limit.get("percentage").and_then(numeric).unwrap_or(0.0);
        buckets.push(QuotaBucket {
            name: match kind {
                "TOKENS_LIMIT" => "Token Usage (5 Hour)".to_string(),
                "TIME_LIMIT" => "MCP Usage (1 Month)".to_string(),
                _ => kind.replace('_', " "),
            },
            used_percent: percentage.clamp(0.0, 100.0),
            window_minutes: match kind {
                "TOKENS_LIMIT" => Some(SESSION_WINDOW_MINUTES),
                "TIME_LIMIT" => Some(43_200),
                _ => None,
            },
            resets_at: None,
            reset_description: None,
        });
    }
    if buckets.is_empty() {
        QuotaSnapshot::error(
            "zai",
            "default",
            "Z.ai",
            "Z.ai quota response did not include limits",
        )
    } else {
        QuotaSnapshot::ok("zai", "default", "Z.ai", Vec::new(), buckets)
    }
}

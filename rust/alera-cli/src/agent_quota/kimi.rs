const KIMI_API_KEY_ENV: &str = "KIMI_API_KEY";

async fn fetch_kimi(names: &EnvironmentNames, environment: &QuotaEnvironment) -> QuotaSnapshot {
    let Some(api_key) = environment.value(&names.kimi_api_key) else {
        return QuotaSnapshot::unavailable(
            "kimi",
            "default",
            "Kimi",
            format!("{} is not configured", names.kimi_api_key),
        );
    };
    let base = std::env::var("KIMI_CODE_BASE_URL")
        .unwrap_or_else(|_| "https://api.kimi.com/coding/v1".to_string());
    let response = reqwest::Client::new()
        .get(format!("{}/usages", base.trim_end_matches('/')))
        .header(AUTHORIZATION, format!("Bearer {api_key}"))
        .header(ACCEPT, "application/json")
        .timeout(FETCH_TIMEOUT)
        .send()
        .await;
    let response = match response {
        Ok(value) => value,
        Err(error) => return QuotaSnapshot::error("kimi", "default", "Kimi", error.to_string()),
    };
    if !response.status().is_success() {
        return QuotaSnapshot::error(
            "kimi",
            "default",
            "Kimi",
            format!("Kimi quota request failed (HTTP {})", response.status()),
        );
    }
    let data: Value = match response.json().await {
        Ok(value) => value,
        Err(error) => return QuotaSnapshot::error("kimi", "default", "Kimi", error.to_string()),
    };
    parse_kimi_usage(&data)
}

fn parse_kimi_usage(data: &Value) -> QuotaSnapshot {
    let mut windows = Vec::new();
    if let Some(window) = map_count_window(data.get("usage"), "Weekly", WEEKLY_WINDOW_MINUTES) {
        windows.push(window);
    }
    if let Some(limits) = data.get("limits").and_then(Value::as_array) {
        let mut best: Option<(i64, QuotaWindow)> = None;
        for limit in limits {
            let minutes =
                kimi_window_minutes(limit.get("window")).unwrap_or(SESSION_WINDOW_MINUTES);
            let Some(window) = map_count_window(limit.get("detail"), "5 Hour", minutes) else {
                continue;
            };
            let distance = (minutes - SESSION_WINDOW_MINUTES).abs();
            if best.as_ref().is_none_or(|(current, _)| distance < *current) {
                best = Some((distance, window));
            }
        }
        if let Some((_, window)) = best {
            windows.insert(0, window);
        }
    }
    if windows.is_empty() {
        QuotaSnapshot::error(
            "kimi",
            "default",
            "Kimi",
            "Kimi quota response did not include usage windows",
        )
    } else {
        QuotaSnapshot::ok("kimi", "default", "Kimi", windows, Vec::new())
    }
}

fn kimi_window_minutes(value: Option<&Value>) -> Option<i64> {
    let value = value?;
    let duration = numeric(value.get("duration")?)? as i64;
    let unit = value
        .get("timeUnit")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_uppercase();
    Some(if unit.contains("DAY") {
        duration * 1440
    } else if unit.contains("HOUR") {
        duration * 60
    } else if unit.contains("SECOND") {
        duration / 60
    } else {
        duration
    })
}

fn map_count_window(value: Option<&Value>, label: &str, minutes: i64) -> Option<QuotaWindow> {
    let value = value?;
    let limit = numeric(value.get("limit")?)?;
    if limit <= 0.0 {
        return None;
    }
    let used = value.get("used").and_then(numeric).or_else(|| {
        value
            .get("remaining")
            .and_then(numeric)
            .map(|remaining| limit - remaining)
    })?;
    let reset = value
        .get("resetTime")
        .or_else(|| value.get("resetAt"))
        .and_then(Value::as_str);
    Some(QuotaWindow {
        label: label.to_string(),
        used_percent: ((used / limit) * 100.0).clamp(0.0, 100.0),
        window_minutes: Some(minutes),
        resets_at: reset.and_then(parse_timestamp_millis),
        reset_description: reset.map(str::to_string),
    })
}

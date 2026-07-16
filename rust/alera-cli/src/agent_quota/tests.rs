use super::*;

#[test]
fn parses_tui_used_and_remaining_percentages() {
    let snapshot = parse_tui_snapshot(
        "claude",
        "default",
        "Default",
        "Current session 20% used resets at 2 PM\nCurrent week 35% left",
    );
    assert_eq!(snapshot.status, "ok");
    assert_eq!(snapshot.windows.len(), 2);
    assert!(snapshot
        .windows
        .iter()
        .any(|window| window.used_percent == 20.0));
    assert!(snapshot
        .windows
        .iter()
        .any(|window| window.used_percent == 65.0));
}

#[test]
fn maps_minimax_usage_counts_as_used() {
    let model = json!({
        "current_interval_total_count": 100,
        "current_interval_usage_count": 25,
        "end_time": 1234,
    });
    let bucket = minimax_bucket(&model, "general", false).unwrap();
    assert_eq!(bucket.used_percent, 25.0);
}

#[test]
fn maps_kimi_api_usage_windows() {
    let snapshot = parse_kimi_usage(&json!({
        "usage": {
            "limit": 1000,
            "used": 250,
            "resetTime": "2026-07-20T00:00:00Z",
        },
        "limits": [{
            "window": { "duration": 5, "timeUnit": "HOUR" },
            "detail": {
                "limit": 100,
                "remaining": 80,
                "resetTime": "2026-07-16T20:00:00Z",
            },
        }],
    }));

    assert_eq!(snapshot.status, "ok");
    assert_eq!(snapshot.windows.len(), 2);
    assert_eq!(snapshot.windows[0].label, "5 Hour");
    assert_eq!(snapshot.windows[0].used_percent, 20.0);
    assert_eq!(snapshot.windows[1].label, "Weekly");
    assert_eq!(snapshot.windows[1].used_percent, 25.0);
}

#[test]
fn maps_claude_oauth_usage_windows() {
    let value = json!({
        "utilization": 42,
        "resets_at": 1_800_000_000,
    });
    let window = map_claude_oauth_window(Some(&value), "5 Hour", SESSION_WINDOW_MINUTES).unwrap();
    assert_eq!(window.used_percent, 42.0);
    assert_eq!(window.resets_at, Some(1_800_000_000_000));
}

#[test]
fn preserves_gpt_acronym_and_uses_normal_hyphens() {
    let snapshot = parse_tui_snapshot(
        "antigravity",
        "default",
        "Antigravity",
        "claude and gpt models\nWeekly limit\n75% left",
    );
    assert_eq!(snapshot.buckets.len(), 1);
    assert_eq!(snapshot.buckets[0].name, "Claude And GPT Models - Weekly");
}

#[test]
fn detects_complete_antigravity_usage_without_fixed_delay() {
    let complete = [
        "Gemini Models",
        "Weekly limit",
        "99% left",
        "5 hour limit",
        "100% left",
        "Claude and GPT Models",
        "Weekly limit",
        "75% left",
        "5 hour limit",
        "100% left",
    ]
    .join("\n");
    assert!(antigravity_usage_complete(&complete));
    assert!(!antigravity_usage_complete(
        "Gemini Models\nWeekly limit\n99% left"
    ));
}

#[test]
fn redacts_bearer_and_api_keys() {
    let redacted = redact_error("Bearer sk-example-secret-value-1234567890");
    assert!(!redacted.contains("secret-value"));
}

#[test]
fn defaults_claude_default_to_enabled_for_older_clients() {
    let request: AgentQuotaFetchRequest = serde_json::from_value(json!({})).unwrap();
    assert!(request.claude_default_enabled);
    assert_eq!(request.environment_names.kimi_api_key, KIMI_API_KEY_ENV);
}

#[test]
fn accepts_disabling_claude_default_independently() {
    let request: AgentQuotaFetchRequest =
        serde_json::from_value(json!({ "claudeDefaultEnabled": false })).unwrap();
    assert!(!request.claude_default_enabled);
}

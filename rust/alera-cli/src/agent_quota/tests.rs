use super::*;

#[tokio::test]
async fn accepts_only_configured_transient_environment_values() {
    let secret = "quota-secret-must-not-be-returned";
    let payload = fetch_agent_quotas(json!({
        "providers": ["__none__"],
        "environmentNames": {
            "kimiApiKey": "ALERA_TEST_KIMI_KEY",
            "zaiApiKey": "ALERA_TEST_ZAI_KEY",
            "zaiBaseUrl": "ALERA_TEST_ZAI_URL",
            "minimaxApiKey": "ALERA_TEST_MINIMAX_KEY",
            "minimaxApiHost": "ALERA_TEST_MINIMAX_HOST"
        },
        "environmentValues": {
            "ALERA_TEST_KIMI_KEY": secret,
            "UNCONFIGURED_SECRET": secret
        }
    }))
    .await
    .expect("quota payload");

    assert_eq!(
        payload["environment"]["ALERA_TEST_KIMI_KEY"],
        Value::Bool(true)
    );
    assert!(payload["environment"].get("UNCONFIGURED_SECRET").is_none());
    assert!(!payload.to_string().contains(secret));
}

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
fn maps_cursor_period_usage_like_cli_usage_panel() {
    // Matches cursor-agent /usage: Included/Auto/API percentages, not spend/limit.
    let snapshot = parse_cursor_period_usage(&json!({
        "billingCycleStart": "1783357994000",
        "billingCycleEnd": "1786036394000",
        "planUsage": {
            "totalSpend": 625,
            "includedSpend": 625,
            "remaining": 1375,
            "limit": 2000,
            "autoPercentUsed": 0,
            "apiPercentUsed": 14.08888888888889,
            "totalPercentUsed": 1.8376811594202898
        },
        "displayMessage": "You've used 32% of your included usage"
    }));

    assert_eq!(snapshot.status, "ok");
    assert_eq!(snapshot.provider, "cursor");
    assert_eq!(snapshot.windows.len(), 3);
    assert_eq!(snapshot.windows[0].label, "Included");
    assert!((snapshot.windows[0].used_percent - 1.8376811594202898).abs() < 1e-9);
    assert_eq!(snapshot.windows[0].resets_at, Some(1_786_036_394_000));
    assert_eq!(snapshot.windows[1].label, "Auto");
    assert_eq!(snapshot.windows[1].used_percent, 0.0);
    assert_eq!(snapshot.windows[2].label, "API");
    assert!((snapshot.windows[2].used_percent - 14.08888888888889).abs() < 1e-9);
    // Spend/limit must not drive Included (would incorrectly be ~31%).
    assert!(snapshot.windows[0].used_percent < 5.0);
}

#[test]
fn cursor_period_usage_without_percentages_is_error() {
    let snapshot = parse_cursor_period_usage(&json!({
        "planUsage": {
            "limit": 2000,
            "remaining": 1000
        }
    }));
    assert_eq!(snapshot.status, "error");
    assert!(snapshot.windows.is_empty());
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
fn parses_claude_auth_status_without_exposing_credentials() {
    assert_eq!(
        parse_claude_auth_status(br#"{"loggedIn":true,"authMethod":"oauth"}"#),
        Some(true)
    );
    assert_eq!(
        parse_claude_auth_status(br#"{"loggedIn":false,"authMethod":"none"}"#),
        Some(false)
    );
    assert_eq!(parse_claude_auth_status(b"not-json"), None);
}

#[cfg(target_os = "macos")]
#[test]
fn isolates_custom_claude_profiles_to_their_scoped_keychain() {
    let services = claude_keychain_services(std::path::Path::new("/tmp/claude-profile"));
    assert_eq!(services.len(), 1);
    assert!(services[0].starts_with("Claude Code-credentials-"));
    assert_eq!(services[0].len(), "Claude Code-credentials-".len() + 8);
}

#[cfg(target_os = "macos")]
#[test]
fn default_claude_profile_falls_back_to_legacy_keychain() {
    let services = claude_keychain_services(&home_dir().unwrap().join(".claude"));
    assert_eq!(services.len(), 2);
    assert_eq!(services[1], "Claude Code-credentials");
}

#[test]
fn each_available_credential_gap_says_something_different() {
    // These collapsed into "Not signed in to Claude", which sent users to
    // re-authenticate an account that was signed in the whole time.
    let messages = [
        ClaudeCredentialGap::Absent.message(),
        ClaudeCredentialGap::NotOauth.message(),
    ];
    assert_eq!(
        messages
            .iter()
            .collect::<std::collections::HashSet<_>>()
            .len(),
        2
    );
    assert_eq!(
        ClaudeCredentialGap::Absent.message(),
        "Not signed in to Claude"
    );
}

#[cfg(target_os = "macos")]
#[test]
fn unreadable_credential_gap_explains_keychain_access() {
    assert!(ClaudeCredentialGap::Unreadable
        .message()
        .contains("keychain"));
}

#[test]
fn a_quota_command_runs_with_the_shell_environment_and_the_callers_overrides() {
    // The CLI is exec'd directly, so unlike a terminal tab nothing re-sources
    // the user's rc files for it.
    let environment = tui_command_environment(
        Some(BTreeMap::from([
            ("PATH".to_string(), "/opt/homebrew/bin".to_string()),
            ("CCS_DIR".to_string(), "/home/user/.ccs".to_string()),
            ("TERM".to_string(), "dumb".to_string()),
        ])),
        BTreeMap::from([(
            "CLAUDE_CONFIG_DIR".to_string(),
            "/home/user/.ccs/instances/work".to_string(),
        )]),
    )
    .expect("hydrated environment");

    assert_eq!(environment["PATH"], "/opt/homebrew/bin");
    assert_eq!(environment["CCS_DIR"], "/home/user/.ccs");
    assert_eq!(
        environment["CLAUDE_CONFIG_DIR"],
        "/home/user/.ccs/instances/work"
    );
    // The PTY is the reason this one is not negotiable.
    assert_eq!(environment["TERM"], "xterm-256color");
}

#[test]
fn a_quota_command_inherits_when_the_shell_cannot_be_probed() {
    // Clearing the inherited environment on a failed probe would leave the
    // child with nothing at all, which is worse than the minimal environment.
    assert!(tui_command_environment(None, BTreeMap::new()).is_none());
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
    assert!(!request.allow_cli_fallback);
    assert_eq!(request.environment_names.kimi_api_key, KIMI_API_KEY_ENV);
}

#[test]
fn accepts_disabling_claude_default_independently() {
    let request: AgentQuotaFetchRequest =
        serde_json::from_value(json!({ "claudeDefaultEnabled": false })).unwrap();
    assert!(!request.claude_default_enabled);
}

#[test]
fn accepts_legacy_cli_fallback_flag_without_enabling_tui() {
    let request: AgentQuotaFetchRequest =
        serde_json::from_value(json!({ "allowCliFallback": true })).unwrap();
    assert!(request.allow_cli_fallback);
}

#[test]
fn maps_codex_reset_credits_and_scopes_offer_revision_to_account() {
    let raw = json!({
        "available_count": 2,
        "total_earned_count": 5,
        "credits": [
            {
                "status": "available",
                "expires_at": "2030-01-02T03:04:05Z"
            },
            {
                "status": "used",
                "expires_at": "2030-01-01T03:04:05Z"
            }
        ]
    });
    let first = map_codex_reset_credits(&raw, Some("account-a")).unwrap();
    let second = map_codex_reset_credits(&raw, Some("account-b")).unwrap();
    assert_eq!(first.available_count, 2);
    assert_eq!(first.total_earned_count, Some(5));
    assert_eq!(
        first.next_expires_at,
        parse_timestamp_millis("2030-01-02T03:04:05Z")
    );
    assert!(first.can_consume);
    assert_ne!(first.offer_revision, second.offer_revision);
    assert!(!map_codex_reset_credits(&raw, None).unwrap().can_consume);
}

#[tokio::test]
async fn codex_reset_attempt_reuses_pending_idempotency_key() {
    let runtime = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(runtime.path()).await.unwrap();
    let first = prepare_codex_reset_attempt(&store, "account-a", "offer-a")
        .await
        .unwrap();
    let first_key = match first {
        PreparedCodexReset::Pending { idempotency_key } => idempotency_key,
        PreparedCodexReset::Settled { .. } => panic!("expected pending attempt"),
    };
    drop(store);
    let store = RuntimeStore::open(runtime.path()).await.unwrap();
    let retry = prepare_codex_reset_attempt(&store, "account-a", "offer-b")
        .await
        .unwrap();
    let retry_key = match retry {
        PreparedCodexReset::Pending { idempotency_key } => idempotency_key,
        PreparedCodexReset::Settled { .. } => panic!("expected pending retry"),
    };
    assert_eq!(retry_key, first_key);
    assert_eq!(
        settle_codex_reset_attempt(&store, "account-a", &first_key, "reset")
            .await
            .unwrap(),
        "reset"
    );
    assert_eq!(
        settle_codex_reset_attempt(&store, "account-a", &first_key, "alreadyRedeemed")
            .await
            .unwrap(),
        "reset"
    );
    let settled = prepare_codex_reset_attempt(&store, "account-a", "offer-a")
        .await
        .unwrap();
    assert!(matches!(
        settled,
        PreparedCodexReset::Settled { outcome } if outcome == "reset"
    ));
}

#[tokio::test]
#[ignore = "network smoke; run with --ignored when signed into cursor-agent"]
async fn live_fetch_cursor_period_usage_when_signed_in() {
    let payload = fetch_agent_quotas(json!({ "providers": ["cursor"] }))
        .await
        .expect("cursor quota fetch");
    let snapshots = payload["snapshots"].as_array().expect("snapshots");
    assert_eq!(snapshots.len(), 1);
    let snapshot = &snapshots[0];
    assert_eq!(snapshot["provider"], "cursor");
    assert_eq!(snapshot["status"], "ok");
    let windows = snapshot["windows"].as_array().expect("windows");
    assert!(windows.iter().any(|w| w["label"] == "Included"));
    assert!(windows.iter().any(|w| w["label"] == "API"));
    println!("{}", serde_json::to_string_pretty(snapshot).unwrap());
}

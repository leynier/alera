use super::grok_transcripts::grok_sessions_directory;
use super::*;
use chrono::Local;

fn turn(usage: Value) -> Value {
    json!({
        "timestamp": 1_786_372_566,
        "method": "_x.ai/session/update",
        "params": {
            "sessionId": "session-1",
            "_meta": {"agentTimestampMs": 1_786_372_566_485_i64},
            "update": {
                "sessionUpdate": "turn_completed",
                "prompt_id": "prompt-1",
                "usage": usage
            }
        }
    })
}

#[test]
fn grok_separates_cache_and_reasoning_without_counting_aggregate_twice() {
    let records = parse_grok_line(
        &turn(json!({
            "inputTokens": 20_272, "outputTokens": 272, "costUsdTicks": 230_272_000,
            "modelUsage": {"grok-4.5-build": {
                "inputTokens": 20_272, "outputTokens": 272,
                "cachedReadTokens": 11_264, "cacheCreationTokens": 8,
                "reasoningTokens": 180, "costUsdTicks": 230_272_000
            }}
        }))
        .to_string(),
    );
    assert_eq!(records.len(), 1);
    let record = &records[0];
    assert_eq!(record.provider, UsageProvider::Grok);
    assert_eq!(record.timestamp_ms, 1_786_372_566_485);
    assert_eq!(record.session_id, "session-1");
    assert_eq!(record.model, "grok-4.5-build");
    assert_eq!(record.totals.uncached_input_tokens, 9_000);
    assert_eq!(record.totals.cached_input_tokens, 11_264);
    assert_eq!(record.totals.cache_creation_tokens, 8);
    assert_eq!(record.totals.reasoning_tokens, 180);
    assert_eq!(record.totals.total(), 20_544);
    assert!((record.reported_cost_usd.unwrap() - 0.0230272).abs() < 1e-12);
}

#[test]
fn grok_preserves_model_costs_and_allocates_only_the_remaining_cost() {
    for (explicit_cost, expected_a, expected_b) in [
        (Value::Null, 0.75, 0.25),
        (json!(4_000_000_000_u64), 0.4, 0.6),
        (json!(12_000_000_000_u64), 1.2, 0.0),
        (json!(0), 0.0, 1.0),
        (json!(-1), 0.75, 0.25),
    ] {
        let records = parse_grok_line(
            &turn(json!({
                "costUsdTicks": 10_000_000_000_u64,
                "modelUsage": {
                    "a": {"inputTokens": 300, "costUsdTicks": explicit_cost},
                    "b": {"inputTokens": 100},
                    "empty": {"inputTokens": 0, "costUsdTicks": 10_000_000_000_u64}
                }
            }))
            .to_string(),
        );
        assert_eq!(records.len(), 2);
        assert_eq!(records[0].model, "a");
        assert!((records[0].reported_cost_usd.unwrap() - expected_a).abs() < 1e-12);
        assert!((records[1].reported_cost_usd.unwrap() - expected_b).abs() < 1e-12);
    }
}

#[test]
fn grok_uses_aggregate_when_models_are_missing_and_preserves_zero_cost() {
    for model_usage in [Value::Null, json!({}), json!({"": {}, "invalid": 12})] {
        let records = parse_grok_line(
            &turn(json!({
                "inputTokens": 10, "outputTokens": 2,
                "modelUsage": model_usage, "costUsdTicks": 0
            }))
            .to_string(),
        );
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].model, "grok");
        assert_eq!(records[0].totals.total(), 12);
        assert_eq!(records[0].reported_cost_usd, Some(0.0));
    }
    let records = parse_grok_line(
        &turn(json!({
            "inputTokens": 10, "costUsdTicks": -1
        }))
        .to_string(),
    );
    assert_eq!(records[0].reported_cost_usd, None);
}

#[test]
fn grok_missing_cost_uses_model_rates_or_remains_unpriced() {
    let rates = pricing::parse_rate_table(&json!({
        "xai/grok-known": {
            "input_cost_per_token": 0.01,
            "output_cost_per_token": 0.02,
            "cache_read_input_token_cost": 0.001
        }
    }));
    let mut aggregator = UsageAggregator::new("2026-08-01", "2026-08-31", &rates);
    for record in parse_grok_line(
        &turn(json!({"modelUsage": {
            "grok-known": {"inputTokens": 20, "cachedReadTokens": 10, "outputTokens": 5},
            "grok-unknown": {"inputTokens": 10}
        }}))
        .to_string(),
    ) {
        assert!(aggregator.add("default", "Default", record));
    }
    let buckets = aggregator.finish();
    assert!((buckets[0].cost_usd - 0.21).abs() < 1e-12);
    assert!((buckets[0].cache_savings_usd - 0.09).abs() < 1e-12);
    assert!(matches!(
        buckets[0].cost_source,
        UsageCostSource::ModelPriced
    ));
    assert_eq!(buckets[1].unpriced_records, 1);
    assert!(matches!(buckets[1].cost_source, UsageCostSource::Unpriced));
}

#[test]
fn grok_falls_back_to_seconds_or_milliseconds_and_rejects_invalid_dates() {
    let mut event = turn(json!({"inputTokens": 1}));
    event["params"]["_meta"] = Value::Null;
    for timestamp in [json!(1_786_372_566), json!(1_786_372_566_000_i64)] {
        event["timestamp"] = timestamp;
        assert_eq!(
            parse_grok_line(&event.to_string())[0].timestamp_ms,
            1_786_372_566_000
        );
    }
    for timestamp in [Value::Null, json!("invalid"), json!(-1), json!(1e30)] {
        event["timestamp"] = timestamp;
        assert!(parse_grok_line(&event.to_string()).is_empty());
    }
}

#[test]
fn grok_skips_incomplete_updates_and_clamps_inconsistent_token_subsets() {
    for line in [
        "{",
        "null",
        "[]",
        "{}",
        "{\"params\":{\"update\":{\"sessionUpdate\":\"turn_started\"}}}",
    ] {
        assert!(parse_grok_line(line).is_empty());
    }
    assert!(parse_grok_line(&turn(json!({"inputTokens": 0})).to_string()).is_empty());
    let records = parse_grok_line(
        &turn(json!({
            "inputTokens": -5, "cachedReadTokens": 10, "cacheCreationTokens": 2,
            "outputTokens": 3, "reasoningTokens": 100
        }))
        .to_string(),
    );
    assert_eq!(records[0].totals.uncached_input_tokens, 0);
    assert_eq!(records[0].totals.reasoning_tokens, 3);
    assert_eq!(records[0].totals.total(), 15);
}

#[test]
fn grok_deduplicates_turn_models_but_retains_turns_without_identity() {
    let rates = RateTable::new();
    let mut aggregator = UsageAggregator::new("2026-08-01", "2026-08-31", &rates);
    let event = turn(json!({"modelUsage": {
        "a": {"inputTokens": 10}, "b": {"inputTokens": 20}
    }}));
    let records = parse_grok_line(&event.to_string());
    for record in &records {
        assert!(aggregator.add("default", "Default", record.clone()));
        assert!(!aggregator.add("default", "Default", record.clone()));
    }
    for identity in ["prompt_id", "sessionId"] {
        let mut incomplete_identity = event.clone();
        if identity == "sessionId" {
            incomplete_identity["params"][identity] = Value::Null;
        } else {
            incomplete_identity["params"]["update"][identity] = Value::Null;
        }
        for record in parse_grok_line(&incomplete_identity.to_string()) {
            assert!(record.dedupe_key.is_none());
            assert!(aggregator.add("default", "Default", record.clone()));
            assert!(aggregator.add("default", "Default", record));
        }
    }
    assert_eq!(
        aggregator
            .finish()
            .iter()
            .map(|row| row.records)
            .sum::<u64>(),
        10
    );
}

#[test]
fn grok_home_defaults_and_overrides_stay_under_sessions() {
    let home = Path::new("user-home");
    for configured in [None, Some(""), Some("   ")] {
        assert_eq!(
            grok_sessions_directory(home, configured),
            home.join(".grok/sessions")
        );
    }
    assert_eq!(
        grok_sessions_directory(home, Some("~/custom")),
        home.join("custom/sessions")
    );
    assert_eq!(
        grok_sessions_directory(home, Some("~\\custom")),
        home.join("custom/sessions")
    );
    assert_eq!(
        grok_sessions_directory(home, Some("~")),
        home.join("sessions")
    );
    assert_eq!(
        grok_sessions_directory(home, Some("  custom  ")),
        Path::new("custom").join("sessions")
    );
}

#[test]
fn grok_opt_in_preserves_legacy_buckets_and_sources_after_cached_scans() {
    let root = tempfile::tempdir().unwrap();
    let grok_dir = root.path().join(".grok/sessions/session-1");
    let codex_dir = root.path().join("codex");
    std::fs::create_dir_all(&grok_dir).unwrap();
    std::fs::create_dir_all(&codex_dir).unwrap();
    std::fs::write(
        grok_dir.join("updates.jsonl"),
        turn(json!({"inputTokens": 100})).to_string(),
    )
    .unwrap();
    let timestamp = chrono::DateTime::from_timestamp_millis(1_786_372_566_485).unwrap();
    let codex_lines = [
        json!({"type": "session_meta", "payload": {"id": "codex-session"}}),
        json!({"type": "turn_context", "payload": {"model": "gpt-5.6-codex"}}),
        json!({"type": "event_msg", "timestamp": timestamp.to_rfc3339(),
            "payload": {"type": "token_count", "info": {
                "last_token_usage": {"input_tokens": 10}
            }}
        }),
    ]
    .map(|line| line.to_string())
    .join("\n");
    std::fs::write(codex_dir.join("rollout.jsonl"), codex_lines).unwrap();
    let day = timestamp.with_timezone(&Local).date_naive();
    for include_grok in [Some(true), None, Some(false), Some(true)] {
        let mut payload = json!({"sinceDay": day.to_string(), "untilDay": day.to_string()});
        if let Some(enabled) = include_grok {
            payload["includeGrok"] = json!(enabled);
        }
        let request: UsageRequest = serde_json::from_value(payload).unwrap();
        let mut sources = vec![UsageSourceConfig {
            provider: UsageProvider::Codex,
            account_id: "default".to_string(),
            display_name: "Default".to_string(),
            directory: codex_dir.clone(),
        }];
        sources.extend(grok_usage_source(&request, root.path(), None));
        let snapshot = scan_sources(
            &request.since_day,
            &request.until_day,
            day,
            sources,
            &RateTable::new(),
            PricingState {
                status: "unavailable",
                source: "test",
                known_models: 0,
            },
        )
        .unwrap();
        let expected_count = if include_grok == Some(true) { 2 } else { 1 };
        assert_eq!(snapshot.sources.len(), expected_count);
        assert_eq!(snapshot.buckets.len(), expected_count);
        assert_eq!(snapshot.sources[0].provider, UsageProvider::Codex);
        assert_eq!(snapshot.sources[0].distinct_sessions, 1);
        assert_eq!(snapshot.buckets[0].provider, UsageProvider::Codex);
        assert_eq!(snapshot.buckets[0].totals.total(), 10);
        if include_grok == Some(true) {
            assert_eq!(snapshot.buckets[1].provider, UsageProvider::Grok);
            assert_eq!(snapshot.buckets[1].totals.total(), 100);
        }
    }
}

#[test]
fn grok_scan_filters_logs_deduplicates_copies_and_refreshes_changed_files() {
    let root = tempfile::tempdir().unwrap();
    let session = root.path().join("session-1");
    let copy = root.path().join("copy");
    std::fs::create_dir_all(&session).unwrap();
    std::fs::create_dir_all(&copy).unwrap();
    let event = turn(json!({
        "inputTokens": 10, "costUsdTicks": 10_000_000_000_u64
    }));
    let line = event.to_string();
    let path = session.join("updates.jsonl");
    std::fs::write(&path, format!("{line}\n{{\n")).unwrap();
    std::fs::write(copy.join("updates.jsonl"), &line).unwrap();
    let mut other = event.clone();
    other["params"]["update"]["prompt_id"] = json!("excluded");
    for name in ["events.jsonl", "chat_history.jsonl"] {
        std::fs::write(session.join(name), other.to_string()).unwrap();
    }
    let day = Local
        .timestamp_millis_opt(1_786_372_566_485)
        .single()
        .unwrap()
        .date_naive();
    let day_label = day.to_string();
    let scan = || {
        scan_sources(
            &day_label,
            &day_label,
            day,
            vec![UsageSourceConfig {
                provider: UsageProvider::Grok,
                account_id: "default".to_string(),
                display_name: "Default".to_string(),
                directory: root.path().to_path_buf(),
            }],
            &RateTable::new(),
            PricingState {
                status: "unavailable",
                source: "test",
                known_models: 0,
            },
        )
        .unwrap()
    };
    for _ in 0..2 {
        let snapshot = scan();
        assert_eq!(snapshot.sources[0].scanned_files, 2);
        assert_eq!(snapshot.sources[0].distinct_sessions, 1);
        assert_eq!(snapshot.buckets[0].records, 1);
        assert_eq!(snapshot.buckets[0].cost_usd, 1.0);
        assert!(matches!(
            snapshot.buckets[0].cost_source,
            UsageCostSource::ProviderReported
        ));
        assert_eq!(
            serde_json::to_value(&snapshot).unwrap()["buckets"][0]["provider"],
            "grok"
        );
    }
    other["params"]["update"]["prompt_id"] = json!("prompt-2");
    std::fs::write(&path, format!("{line}\n{other}\n")).unwrap();
    let snapshot = scan();
    assert_eq!(snapshot.buckets[0].records, 2);
    assert_eq!(snapshot.buckets[0].totals.total(), 20);
    assert_eq!(snapshot.buckets[0].cost_usd, 2.0);
    let rates = RateTable::new();
    let mut outside_window = UsageAggregator::new("2020-01-01", "2020-01-01", &rates);
    assert!(!outside_window.add("default", "Default", parse_grok_line(&line).remove(0)));
}

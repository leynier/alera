use std::collections::HashSet;

use chrono::{Local, TimeZone};
use serde_json::json;

use super::aggregation::UsageAggregator;
use super::pricing::{parse_rate_table, PricingState};
use super::transcripts::{parse_claude_line, parse_codex_line, CodexScanState};
use super::*;

#[test]
fn parses_and_deduplicates_claude_usage() {
    let line = json!({
        "type": "assistant",
        "timestamp": "2026-08-10T12:00:00Z",
        "sessionId": "session-1",
        "requestId": "request-1",
        "message": {
            "id": "message-1",
            "model": "claude-opus-5",
            "usage": {
                "input_tokens": 10,
                "cache_read_input_tokens": 20,
                "cache_creation_input_tokens": 5,
                "output_tokens": 7
            }
        }
    })
    .to_string();
    let record = parse_claude_line(&line).expect("usage record");
    let day = Local
        .timestamp_millis_opt(record.timestamp_ms)
        .single()
        .unwrap()
        .date_naive()
        .format("%Y-%m-%d")
        .to_string();
    let rates = parse_rate_table(&json!({
        "claude-opus-5": {
            "input_cost_per_token": 0.00001,
            "output_cost_per_token": 0.00002,
            "cache_read_input_token_cost": 0.000001,
            "cache_creation_input_token_cost": 0.0000125
        }
    }));
    let mut aggregator = UsageAggregator::new(&day, &day, &rates);
    assert!(aggregator.add("default", "Default", record.clone()));
    assert!(!aggregator.add("default", "Default", record));
    let bucket = aggregator.finish().pop().unwrap();
    assert_eq!(bucket.totals.total(), 42);
    assert_eq!(bucket.records, 1);
    assert!(bucket.cost_usd > 0.0);
}

#[test]
fn codex_uses_deltas_and_drops_fork_history() {
    let mut state = CodexScanState::default();
    assert!(parse_codex_line(
        &json!({
            "timestamp": "2026-08-10T12:00:00Z",
            "type": "session_meta",
            "payload": {"id": "child", "forked_from_id": "parent"}
        })
        .to_string(),
        &mut state
    )
    .is_none());
    parse_codex_line(
        &json!({
            "timestamp": "2026-08-10T12:00:00.010Z",
            "type": "turn_context",
            "payload": {"model": "gpt-5.6-codex"}
        })
        .to_string(),
        &mut state,
    );
    let copied = codex_usage_line("2026-08-10T12:00:00.020Z", 10);
    assert!(parse_codex_line(&copied, &mut state).is_none());
    let fresh = codex_usage_line("2026-08-10T12:00:02Z", 11);
    let record = parse_codex_line(&fresh, &mut state).expect("fresh usage");
    assert_eq!(record.session_id, "child");
    assert_eq!(record.model, "gpt-5.6-codex");
    assert_eq!(record.totals.uncached_input_tokens, 7);
    assert_eq!(record.totals.cached_input_tokens, 4);
}

#[test]
fn scan_keeps_ccs_accounts_separate() {
    let root = tempfile::tempdir().unwrap();
    let default_dir = root.path().join("default");
    let ccs_dir = root.path().join("profile");
    std::fs::create_dir_all(&default_dir).unwrap();
    std::fs::create_dir_all(&ccs_dir).unwrap();
    let line = json!({
        "type": "assistant",
        "timestamp": chrono::Utc::now().to_rfc3339(),
        "sessionId": "session",
        "message": {
            "model": "claude-sonnet-5",
            "usage": {"input_tokens": 1, "output_tokens": 2}
        }
    })
    .to_string();
    std::fs::write(default_dir.join("a.jsonl"), format!("{line}\n")).unwrap();
    std::fs::write(ccs_dir.join("b.jsonl"), format!("{line}\n")).unwrap();
    let today = Local::now().date_naive().format("%Y-%m-%d").to_string();
    let snapshot = scan_sources(
        &today,
        &today,
        Local::now().date_naive(),
        vec![
            UsageSourceConfig {
                provider: UsageProvider::Claude,
                account_id: "default".to_string(),
                display_name: "Default".to_string(),
                directory: default_dir,
            },
            UsageSourceConfig {
                provider: UsageProvider::Claude,
                account_id: "dev".to_string(),
                display_name: "ccdev".to_string(),
                directory: ccs_dir,
            },
        ],
        &RateTable::new(),
        PricingState {
            status: "unavailable",
            source: "test",
            known_models: 0,
        },
    )
    .unwrap();
    assert_eq!(snapshot.buckets.len(), 2);
    assert_eq!(
        snapshot
            .buckets
            .iter()
            .map(|bucket| bucket.account_id.as_str())
            .collect::<HashSet<_>>(),
        HashSet::from(["default", "dev"])
    );
}

#[test]
fn rejects_invalid_or_unbounded_windows() {
    assert!(parse_day("not-a-day", "sinceDay").is_err());
    let since = NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
    let until = NaiveDate::from_ymd_opt(2026, 4, 1).unwrap();
    assert!(until.signed_duration_since(since).num_days() + 1 > MAX_WINDOW_DAYS);
}

fn codex_usage_line(timestamp: &str, input: u64) -> String {
    json!({
        "timestamp": timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {"last_token_usage": {
                "input_tokens": input,
                "cached_input_tokens": 4,
                "output_tokens": 3,
                "reasoning_output_tokens": 2
            }}
        }
    })
    .to_string()
}

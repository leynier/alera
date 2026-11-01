use super::*;

/// `agy -p "/usage"` captured at 2026-11-01T10:25:32Z with untouched quotas.
const CAPTURED: &str = "Gemini Models\tWeekly Limit Remaining\t100%\t2026-11-08T10:25:32Z\n\
Gemini Models\tFive Hour Limit Remaining\t100%\t2026-11-01T15:25:32Z\n\
Claude and GPT models\tWeekly Limit Remaining\t100%\t2026-11-08T10:25:32Z\n\
Claude and GPT models\tFive Hour Limit Remaining\t100%\t2026-11-01T15:25:32Z\n\
Gemini 4 Argon\tGemini 4 Argon Weekly Limit\t100%\t2026-11-08T10:25:32Z\n";

fn requested_at() -> i64 {
    chrono::DateTime::parse_from_rfc3339("2026-11-01T10:25:32Z")
        .unwrap()
        .timestamp_millis()
}

fn bucket<'a>(snapshot: &'a QuotaSnapshot, name: &str) -> &'a QuotaBucket {
    snapshot
        .buckets
        .iter()
        .find(|bucket| bucket.name == name)
        .unwrap_or_else(|| panic!("{name}"))
}

#[test]
fn untouched_buckets_hide_their_rolling_reset() {
    let snapshot = parse_antigravity_usage(CAPTURED, requested_at() + 900);
    assert_eq!(snapshot.status, "ok");
    let names: Vec<_> = snapshot.buckets.iter().map(|bucket| bucket.name.as_str()).collect();
    assert_eq!(
        names,
        vec![
            "Gemini Models - Weekly",
            "Gemini Models - 5 Hour",
            "Claude And GPT Models - Weekly",
            "Claude And GPT Models - 5 Hour",
            "Gemini 4 Argon - Weekly",
        ]
    );
    for bucket in &snapshot.buckets {
        assert_eq!(bucket.used_percent, 0.0);
        assert_eq!(bucket.resets_at, None, "{}", bucket.name);
    }
    assert_eq!(bucket(&snapshot, "Gemini Models - 5 Hour").window_minutes, Some(300));
    assert_eq!(bucket(&snapshot, "Gemini Models - Weekly").window_minutes, Some(10_080));
}

#[test]
fn used_buckets_and_distant_resets_keep_their_reset() {
    let output = "Gemini Models\tFive Hour Limit Remaining\t60%\t2026-11-01T15:25:32Z\n\
Gemini Models\tWeekly Limit Remaining\t100%\t2026-11-05T00:00:00Z\n";
    let snapshot = parse_antigravity_usage(output, requested_at());
    let five_hour = bucket(&snapshot, "Gemini Models - 5 Hour");
    assert_eq!(five_hour.used_percent, 40.0);
    assert_eq!(five_hour.resets_at, Some(requested_at() + 300 * 60_000));
    assert!(bucket(&snapshot, "Gemini Models - Weekly").resets_at.is_some());
}

#[test]
fn the_rolling_reset_tolerance_is_one_minute_each_way() {
    let window = 300 * 60_000;
    for (offset, rolling) in [(-60_000, true), (60_000, true), (-60_001, false), (60_001, false)] {
        assert_eq!(
            rolling_reset(100.0, requested_at() + window + offset, Some(300), requested_at()),
            rolling,
            "{offset}"
        );
    }
    assert!(!rolling_reset(99.5, requested_at() + window, Some(300), requested_at()));
}

#[test]
fn unknown_windows_keep_their_label_and_reset() {
    let output = "Gemini Models\tDaily Limit Remaining\t100%\t2026-11-02T10:25:32Z\n";
    let snapshot = parse_antigravity_usage(output, requested_at());
    let daily = bucket(&snapshot, "Gemini Models - Daily Limit Remaining");
    assert_eq!(daily.window_minutes, None);
    assert!(daily.resets_at.is_some());
}

#[test]
fn malformed_lines_are_skipped() {
    let output = "Usage\n\
Gemini Models\tWeekly Limit Remaining\tlots\t2026-11-08T10:25:32Z\n\
Gemini Models\tWeekly Limit Remaining\t140%\t2026-11-08T10:25:32Z\n\
\tWeekly Limit Remaining\t50%\t2026-11-08T10:25:32Z\n\
Gemini Models\tFive Hour Limit Remaining\t50%\tsoon\n";
    let snapshot = parse_antigravity_usage(output, requested_at());
    assert_eq!(snapshot.buckets.len(), 1);
    assert_eq!(snapshot.buckets[0].name, "Gemini Models - 5 Hour");
    assert_eq!(snapshot.buckets[0].resets_at, None);
    assert_eq!(parse_antigravity_usage("nothing here", requested_at()).status, "error");
}

//! Shapes the `resources.snapshot` wire payload.
//!
//! Kept apart from the sampler so the JSON field names and the arithmetic that
//! feeds them stay readable side by side. Every byte field is named `*Bytes` and
//! carries bytes; CPU is percent of a single core, so it can exceed 100.

use chrono::Utc;
use serde_json::{json, Value};

use super::process_tree::SubtreeUsage;

/// History keys for the two rows that are not sessions.
pub const HOST_HISTORY_KEY: &str = "__host__";
pub const APP_HISTORY_KEY: &str = "__app__";

/// The payload returned before the first sweep lands, so a client that asks the
/// instant the ticker starts gets a well-formed answer instead of an error.
pub fn warming_snapshot() -> Value {
    json!({
        "collectedAt": Utc::now().timestamp_millis(),
        "warming": true,
        "host": {
            "totalMemoryBytes": 0,
            "availableMemoryBytes": 0,
            "usedMemoryBytes": 0,
            "memoryUsagePercent": 0.0,
            "cpuCoreCount": 0,
            "loadAverage1m": 0.0,
        },
        "processes": { "host": Value::Null, "app": Value::Null },
        "sessions": [],
        "totals": { "cpuPercent": 0.0, "memoryBytes": 0 },
    })
}

pub fn process_json(pid: u32, usage: SubtreeUsage, history: Vec<u64>) -> Value {
    json!({
        "pid": pid,
        "cpuPercent": usage.cpu_percent,
        "memoryBytes": usage.memory_bytes,
        "processCount": usage.process_count,
        "history": history,
    })
}

pub fn accumulate(totals: &mut SubtreeUsage, usage: SubtreeUsage) {
    totals.cpu_percent += usage.cpu_percent;
    totals.memory_bytes = totals.memory_bytes.saturating_add(usage.memory_bytes);
    totals.process_count += usage.process_count;
}

pub fn memory_usage_percent(total: u64, available: u64) -> f64 {
    if total == 0 {
        return 0.0;
    }
    (total.saturating_sub(available) as f64) * 100.0 / (total as f64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_usage_percent_handles_an_unknown_total() {
        assert_eq!(memory_usage_percent(0, 0), 0.0);
    }

    #[test]
    fn memory_usage_percent_reports_the_used_share() {
        assert!((memory_usage_percent(1000, 250) - 75.0).abs() < f64::EPSILON);
    }

    #[test]
    fn the_warming_snapshot_is_shaped_like_a_real_one() {
        let snapshot = warming_snapshot();

        assert_eq!(snapshot["warming"], json!(true));
        assert!(snapshot["sessions"].is_array());
        assert!(snapshot["host"]["totalMemoryBytes"].is_number());
        assert!(snapshot["totals"]["memoryBytes"].is_number());
    }

    #[test]
    fn accumulating_sums_every_field() {
        let mut totals = SubtreeUsage {
            cpu_percent: 1.0,
            memory_bytes: 100,
            process_count: 1,
        };

        accumulate(
            &mut totals,
            SubtreeUsage {
                cpu_percent: 2.0,
                memory_bytes: 200,
                process_count: 2,
            },
        );

        assert_eq!(totals.memory_bytes, 300);
        assert_eq!(totals.process_count, 3);
        assert!((totals.cpu_percent - 3.0).abs() < f64::EPSILON);
    }
}

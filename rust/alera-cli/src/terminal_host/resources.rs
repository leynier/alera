use std::collections::HashSet;
use std::time::{Duration, Instant};

use chrono::Utc;
use serde_json::{json, Value};
use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

mod history;
mod process_tree;

use history::ResourceHistory;
use process_tree::{ProcessIndex, ProcessRow, SubtreeUsage};

/// Sampling cadence while a client is watching. Matches the panel's refresh.
pub const RESOURCE_SAMPLE_INTERVAL: Duration = Duration::from_secs(2);
/// The ticker stops itself once no client has asked for a snapshot this long,
/// so an unattended host does not sweep the process table forever.
pub const RESOURCE_IDLE_STOP: Duration = Duration::from_secs(10);
/// `sysinfo` derives CPU from the delta between two refreshes, so the first
/// sweep after a (re)start reports zero for everything.
const REFRESHES_BEFORE_CPU_IS_VALID: u32 = 2;

/// The attribution root for one terminal session.
#[derive(Debug, Clone)]
pub struct SessionPidRoot {
    pub session_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub running: bool,
    pub shell_pid: Option<u32>,
}

/// Owns the `sysinfo` handle across samples.
///
/// The handle has to outlive a single sample: CPU is a delta between two
/// refreshes, so a fresh `System` per request would always report 0%.
pub struct ResourceSampler {
    system: System,
    history: ResourceHistory,
    refreshes: u32,
}

impl Default for ResourceSampler {
    fn default() -> Self {
        ResourceSampler {
            system: System::new(),
            history: ResourceHistory::default(),
            refreshes: 0,
        }
    }
}

impl ResourceSampler {
    /// Forget the CPU baseline. Called when the ticker restarts after an idle
    /// gap, because a delta measured across that gap would describe minutes of
    /// history as if it were the last two seconds.
    pub fn reset_cpu_baseline(&mut self) {
        self.refreshes = 0;
    }

    /// Sweep the process table and build the wire payload.
    ///
    /// Runs on a blocking thread: a full refresh walks every process on the
    /// machine and must not sit on the async runtime.
    pub fn sample(
        &mut self,
        roots: &[SessionPidRoot],
        host_pid: u32,
        app_pid: Option<u32>,
    ) -> Value {
        self.system.refresh_memory();
        self.system.refresh_cpu_usage();
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing().with_cpu().with_memory(),
        );
        self.refreshes = self.refreshes.saturating_add(1);
        let warming = self.refreshes < REFRESHES_BEFORE_CPU_IS_VALID;

        let index =
            ProcessIndex::build(
                self.system
                    .processes()
                    .iter()
                    .map(|(pid, process)| ProcessRow {
                        pid: pid.as_u32(),
                        parent_pid: process.parent().map(|parent| parent.as_u32()),
                        cpu_percent: process.cpu_usage(),
                        memory_bytes: process.memory(),
                    }),
            );

        let now = Instant::now();
        let mut claimed: HashSet<u32> = HashSet::new();
        let mut totals = SubtreeUsage::default();

        // Sessions are claimed first, and deliberately so: every PTY shell is a
        // child of the host process, so measuring the host first would swallow
        // all of them into one unattributed row.
        let mut sessions = Vec::with_capacity(roots.len());
        for root in roots {
            let usage = match root.shell_pid {
                Some(pid) if root.running => index.collect_subtree(pid, &mut claimed),
                _ => SubtreeUsage::default(),
            };
            let measured = root.shell_pid.is_some_and(|pid| index.contains(pid));
            accumulate(&mut totals, usage);
            let history = self
                .history
                .record(&root.session_id, usage.memory_bytes, now);
            sessions.push(json!({
                "sessionId": root.session_id,
                "workspaceId": root.workspace_id,
                "tabId": root.tab_id,
                "running": root.running,
                "shellPid": root.shell_pid,
                "measured": measured,
                "cpuPercent": usage.cpu_percent,
                "memoryBytes": usage.memory_bytes,
                "processCount": usage.process_count,
                "history": history,
            }));
        }

        let host = index.collect_subtree(host_pid, &mut claimed);
        accumulate(&mut totals, host);
        let host_history = self
            .history
            .record(HOST_HISTORY_KEY, host.memory_bytes, now);

        let app = app_pid
            .map(|pid| index.collect_subtree(pid, &mut claimed))
            .unwrap_or_default();
        accumulate(&mut totals, app);
        let app_history = self.history.record(APP_HISTORY_KEY, app.memory_bytes, now);

        self.history.evict_stale(now);

        let total_memory = self.system.total_memory();
        let available_memory = self.system.available_memory();
        let load = System::load_average();
        json!({
            "collectedAt": Utc::now().timestamp_millis(),
            "warming": warming,
            "host": {
                "totalMemoryBytes": total_memory,
                "availableMemoryBytes": available_memory,
                "usedMemoryBytes": total_memory.saturating_sub(available_memory),
                "memoryUsagePercent": memory_usage_percent(total_memory, available_memory),
                "cpuCoreCount": self.system.cpus().len(),
                // Zero on Windows: the platform has no load average.
                "loadAverage1m": load.one,
            },
            "processes": {
                "host": process_json(host_pid, host, host_history),
                "app": app_pid.map(|pid| process_json(pid, app, app_history)),
            },
            "sessions": sessions,
            "totals": {
                "cpuPercent": totals.cpu_percent,
                "memoryBytes": totals.memory_bytes,
            },
        })
    }
}

const HOST_HISTORY_KEY: &str = "__host__";
const APP_HISTORY_KEY: &str = "__app__";

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

fn process_json(pid: u32, usage: SubtreeUsage, history: Vec<u64>) -> Value {
    json!({
        "pid": pid,
        "cpuPercent": usage.cpu_percent,
        "memoryBytes": usage.memory_bytes,
        "processCount": usage.process_count,
        "history": history,
    })
}

fn accumulate(totals: &mut SubtreeUsage, usage: SubtreeUsage) {
    totals.cpu_percent += usage.cpu_percent;
    totals.memory_bytes = totals.memory_bytes.saturating_add(usage.memory_bytes);
    totals.process_count += usage.process_count;
}

fn memory_usage_percent(total: u64, available: u64) -> f64 {
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
    fn a_sample_measures_this_process_and_reports_warming_first() {
        let mut sampler = ResourceSampler::default();
        let self_pid = std::process::id();

        let first = sampler.sample(&[], self_pid, None);
        assert_eq!(first["warming"], json!(true));
        assert!(first["processes"]["host"]["memoryBytes"].as_u64().unwrap() > 0);
        assert_eq!(first["processes"]["app"], Value::Null);

        let second = sampler.sample(&[], self_pid, None);
        assert_eq!(second["warming"], json!(false));
        // Two samples of the same key, so the sparkline has two points.
        assert_eq!(
            second["processes"]["host"]["history"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
    }

    #[test]
    fn a_session_without_a_live_pid_reports_zero_and_is_not_measured() {
        let mut sampler = ResourceSampler::default();
        let roots = vec![SessionPidRoot {
            session_id: "session-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            tab_id: "tab-1".to_string(),
            running: false,
            shell_pid: None,
        }];

        let snapshot = sampler.sample(&roots, std::process::id(), None);

        let session = &snapshot["sessions"][0];
        assert_eq!(session["measured"], json!(false));
        assert_eq!(session["memoryBytes"], json!(0));
        assert_eq!(session["processCount"], json!(0));
    }

    #[test]
    fn resetting_the_baseline_marks_the_next_sample_as_warming() {
        let mut sampler = ResourceSampler::default();
        let self_pid = std::process::id();
        sampler.sample(&[], self_pid, None);
        sampler.sample(&[], self_pid, None);

        sampler.reset_cpu_baseline();

        assert_eq!(sampler.sample(&[], self_pid, None)["warming"], json!(true));
    }
}

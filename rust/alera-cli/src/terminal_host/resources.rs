use std::collections::HashSet;
use std::time::{Duration, Instant};

use chrono::Utc;
use serde_json::{json, Value};
use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System};

mod history;
mod process_tree;
mod snapshot_payload;

use history::ResourceHistory;
use process_tree::{ProcessRow, SubtreeUsage};
use snapshot_payload::{
    accumulate, memory_usage_percent, process_json, APP_HISTORY_KEY, HOST_HISTORY_KEY,
};

pub use process_tree::{ProcessIndex, ShellProcess};
pub use snapshot_payload::warming_snapshot;

/// Sampling cadence while a client is watching. Matches the panel's refresh.
pub const RESOURCE_SAMPLE_INTERVAL: Duration = Duration::from_secs(2);
/// The ticker stops itself once no client has asked for a snapshot this long,
/// so an unattended host does not sweep the process table forever.
pub const RESOURCE_IDLE_STOP: Duration = Duration::from_secs(10);
/// `sysinfo` derives CPU from the delta between refreshes, so the first sweeps
/// after a (re)start report zero for every process.
///
/// Windows needs one sweep more than the others. Measured on sysinfo 0.39.6
/// against processes pegging a full core: Linux and macOS report ~100% on the
/// second sweep, Windows still reports 0.0 there and only reports ~96% on the
/// third. Treating the second sweep as valid on Windows would publish a
/// confident 0% for a machine that is actually saturated.
#[cfg(windows)]
const REFRESHES_BEFORE_CPU_IS_VALID: u32 = 3;
#[cfg(not(windows))]
const REFRESHES_BEFORE_CPU_IS_VALID: u32 = 2;

/// The attribution root for one terminal session.
#[derive(Debug, Clone)]
pub struct SessionPidRoot {
    pub session_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub running: bool,
    pub shell: Option<ShellProcess>,
}

/// Observe a freshly spawned pid's start time, so later sweeps can tell that
/// process apart from whatever the OS puts at the same pid once it exits.
///
/// Refreshes only that pid. This runs on every terminal spawn, and a full
/// process-table walk there would be charged to every new tab.
///
/// `None` when the pid is already gone, which leaves the session unmeasured
/// rather than measuring a guess.
pub fn seal_shell_process(pid: u32) -> Option<ShellProcess> {
    let sysinfo_pid = Pid::from_u32(pid);
    let mut system = System::new();
    system.refresh_processes_specifics(
        ProcessesToUpdate::Some(&[sysinfo_pid]),
        true,
        ProcessRefreshKind::nothing(),
    );
    system.process(sysinfo_pid).map(|process| ShellProcess {
        pid,
        start_time: process.start_time(),
    })
}

/// Index the whole process table for identity and parent links only.
///
/// Skips the cpu and memory refresh the sampler needs, so a caller that only
/// walks the tree (terminating a shell's descendants) pays for a much cheaper
/// sweep. The usage fields on those rows read zero, since they were never
/// collected.
///
/// `without_tasks` keeps threads out of the table. They would otherwise show up
/// as child processes, which makes a shell's own threads read as its
/// descendants: the kill walk would then signal the shell before the root killer
/// runs, and `descendants` would stop meaning what its name says.
pub fn sweep_process_topology() -> ProcessIndex {
    let mut system = System::new();
    system.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing().without_tasks(),
    );
    ProcessIndex::build(system.processes().iter().map(|(pid, process)| {
        ProcessRow::topology_only(
            pid.as_u32(),
            process.parent().map(|parent| parent.as_u32()),
            process.start_time(),
        )
    }))
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
        // `nothing()` is not nothing: it defaults `tasks` on, and on Linux that
        // puts every thread in the table as a child process of its own. Each one
        // reports the whole process's RSS, because they share the address space,
        // so a subtree total scales with the thread count instead of measuring
        // memory: the app read 26x its real size at 97 threads. Thread CPU
        // double counts the same way, since the leader's `/proc/<pid>/stat` is
        // already the thread-group aggregate.
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing()
                .without_tasks()
                .with_cpu()
                .with_memory(),
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
                        start_time: process.start_time(),
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
            // Identity, not just presence: a pid the OS has already recycled
            // would otherwise bill a stranger's memory to this terminal.
            let measured = root.shell.is_some_and(|shell| index.holds(shell));
            let usage = match root.shell {
                Some(shell) if root.running && measured => {
                    index.collect_subtree(shell.pid, &mut claimed)
                }
                _ => SubtreeUsage::default(),
            };
            accumulate(&mut totals, usage);
            let history = self
                .history
                .record(&root.session_id, usage.memory_bytes, now);
            sessions.push(json!({
                "sessionId": root.session_id,
                "workspaceId": root.workspace_id,
                "tabId": root.tab_id,
                "running": root.running,
                "shellPid": root.shell.map(|shell| shell.pid),
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

#[cfg(test)]
mod tests {
    use std::sync::{mpsc, Arc, Barrier};

    use super::*;

    #[test]
    fn a_sample_measures_this_process_and_reports_warming_until_cpu_is_valid() {
        let mut sampler = ResourceSampler::default();
        let self_pid = std::process::id();

        // Every sweep before the platform threshold is warming, because its CPU
        // numbers would all read zero.
        for _ in 1..REFRESHES_BEFORE_CPU_IS_VALID {
            let warming = sampler.sample(&[], self_pid, None);
            assert_eq!(warming["warming"], json!(true));
            assert!(
                warming["processes"]["host"]["memoryBytes"]
                    .as_u64()
                    .unwrap()
                    > 0
            );
            assert_eq!(warming["processes"]["app"], Value::Null);
        }

        let settled = sampler.sample(&[], self_pid, None);
        assert_eq!(settled["warming"], json!(false));
        // One history point per sweep taken so far.
        assert_eq!(
            settled["processes"]["host"]["history"]
                .as_array()
                .unwrap()
                .len(),
            REFRESHES_BEFORE_CPU_IS_VALID as usize
        );
    }

    fn root(shell: Option<ShellProcess>, running: bool) -> SessionPidRoot {
        SessionPidRoot {
            session_id: "session-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            tab_id: "tab-1".to_string(),
            running,
            shell,
        }
    }

    #[test]
    fn a_session_without_a_live_pid_reports_zero_and_is_not_measured() {
        let mut sampler = ResourceSampler::default();
        let roots = vec![root(None, false)];

        let snapshot = sampler.sample(&roots, std::process::id(), None);

        let session = &snapshot["sessions"][0];
        assert_eq!(session["measured"], json!(false));
        assert_eq!(session["memoryBytes"], json!(0));
        assert_eq!(session["processCount"], json!(0));
    }

    #[test]
    fn a_session_whose_pid_was_recycled_is_not_measured() {
        // The pid is live and running, but it no longer holds the shell this
        // session spawned. Attributing it would bill a stranger's memory to
        // this terminal, so the session reports unmeasured instead.
        let mut sampler = ResourceSampler::default();
        let self_pid = std::process::id();
        let sealed = seal_shell_process(self_pid).expect("this process is live");
        let recycled = ShellProcess {
            pid: self_pid,
            start_time: sealed.start_time + 1,
        };

        let snapshot = sampler.sample(&[root(Some(recycled), true)], self_pid, None);

        let session = &snapshot["sessions"][0];
        assert_eq!(session["shellPid"], json!(self_pid));
        assert_eq!(session["measured"], json!(false));
        assert_eq!(session["memoryBytes"], json!(0));
        assert_eq!(session["processCount"], json!(0));
    }

    #[test]
    fn a_session_still_holding_its_shell_is_measured() {
        let mut sampler = ResourceSampler::default();
        let self_pid = std::process::id();
        let sealed = seal_shell_process(self_pid).expect("this process is live");

        // Measured against this process, standing in for a session's shell.
        let snapshot = sampler.sample(&[root(Some(sealed), true)], 1, None);

        let session = &snapshot["sessions"][0];
        assert_eq!(session["measured"], json!(true));
        assert!(session["memoryBytes"].as_u64().unwrap() > 0);
    }

    /// Sample once and read back the subtree measured for `pid`.
    fn host_subtree(sampler: &mut ResourceSampler, pid: u32) -> (u64, u64) {
        let snapshot = sampler.sample(&[], pid, None);
        let row = &snapshot["processes"]["host"];
        (
            row["memoryBytes"].as_u64().expect("memory is a number"),
            row["processCount"].as_u64().expect("the count is a number"),
        )
    }

    /// The regression case for counting threads as processes.
    ///
    /// A thread costs a stack, not an address space, so a batch of them must
    /// barely move a subtree total. When the process refresh leaves `tasks` on,
    /// every thread instead enters the table as a child process whose `statm`
    /// repeats the whole process's RSS, and the total scales with the thread
    /// count: this process measured 26x its real memory at 97 threads.
    #[test]
    fn a_subtree_does_not_scale_with_the_thread_count() {
        const THREADS: usize = 64;
        let mut sampler = ResourceSampler::default();
        let self_pid = std::process::id();

        let (memory_before, count_before) = host_subtree(&mut sampler, self_pid);

        // Each thread reports in before parking on the gate, so the sample below
        // cannot race a thread that has not started yet. The gate then holds all
        // of them alive until the measurement is taken.
        let (ready_tx, ready_rx) = mpsc::channel();
        let gate = Arc::new(Barrier::new(THREADS + 1));
        let threads: Vec<_> = (0..THREADS)
            .map(|_| {
                let gate = Arc::clone(&gate);
                let ready = ready_tx.clone();
                std::thread::spawn(move || {
                    ready.send(()).expect("the test is still listening");
                    gate.wait();
                })
            })
            .collect();
        drop(ready_tx);
        for _ in 0..THREADS {
            ready_rx.recv().expect("every thread reports in");
        }

        let (memory_after, count_after) = host_subtree(&mut sampler, self_pid);

        gate.wait();
        for thread in threads {
            thread.join().expect("the gated thread returns");
        }

        // The process count is the sharp signal, because a thread row simply is
        // an extra row. Bounds are loose on purpose: the other cases in this
        // binary run alongside this one and spawn their own children, and the
        // whole-binary RSS moves under them. The bug multiplied this subtree by
        // 8.6x when it was measured, so it clears both by a wide margin.
        assert!(
            count_after < count_before + 16,
            "the subtree gained {} processes after spawning {THREADS} threads \
             ({count_before} -> {count_after}), so thread rows are being counted",
            count_after.saturating_sub(count_before),
        );
        assert!(
            memory_after < memory_before.saturating_mul(4),
            "subtree memory scaled with the thread count ({memory_before} -> \
             {memory_after} after spawning {THREADS} threads), so thread rows are \
             being summed"
        );
    }

    /// Guards the two invariants a real machine cannot break. Neither is a tight
    /// bound, which is the point: they only trip on double counting, and a
    /// version bump that changes what the refresh returns trips them here rather
    /// than in the panel.
    #[test]
    fn the_totals_stay_within_what_the_machine_has() {
        let mut sampler = ResourceSampler::default();
        let self_pid = std::process::id();
        // CPU is a delta between refreshes, so it only carries a reading once
        // the baseline has settled.
        for _ in 0..REFRESHES_BEFORE_CPU_IS_VALID {
            sampler.sample(&[], self_pid, None);
        }

        let snapshot = sampler.sample(&[], self_pid, None);

        let machine_memory = snapshot["host"]["totalMemoryBytes"]
            .as_u64()
            .expect("the machine reports its memory");
        let attributed_memory = snapshot["totals"]["memoryBytes"]
            .as_u64()
            .expect("the totals carry memory");
        assert!(
            attributed_memory <= machine_memory,
            "attributed {attributed_memory} bytes, more than the {machine_memory} \
             the machine has"
        );

        let cores = snapshot["host"]["cpuCoreCount"]
            .as_u64()
            .expect("the machine reports its cores");
        let attributed_cpu = snapshot["totals"]["cpuPercent"]
            .as_f64()
            .expect("the totals carry cpu");
        // `sysinfo` already caps a single row at `cores * 100`, so a total above
        // it can only come from summing the same work twice.
        let ceiling = (cores * 100) as f64;
        assert!(
            attributed_cpu <= ceiling,
            "attributed {attributed_cpu}% cpu, more than the {ceiling}% \
             {cores} cores can do"
        );
    }

    #[test]
    fn resetting_the_baseline_marks_the_next_sample_as_warming() {
        let mut sampler = ResourceSampler::default();
        let self_pid = std::process::id();
        for _ in 0..REFRESHES_BEFORE_CPU_IS_VALID {
            sampler.sample(&[], self_pid, None);
        }
        assert_eq!(
            sampler.sample(&[], self_pid, None)["warming"],
            json!(false),
            "the sampler should have settled before the reset"
        );

        sampler.reset_cpu_baseline();

        assert_eq!(sampler.sample(&[], self_pid, None)["warming"], json!(true));
    }
}

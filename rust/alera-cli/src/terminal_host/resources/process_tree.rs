use std::collections::{HashMap, HashSet, VecDeque};

/// One row of the host process table, decoupled from `sysinfo` so the tree
/// arithmetic can be tested without touching the real system.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ProcessRow {
    pub pid: u32,
    pub parent_pid: Option<u32>,
    /// Seconds since the UNIX epoch. Carried so a pid can be checked against
    /// the process that was actually spawned at it.
    pub start_time: u64,
    /// Percent of a single core, so it can exceed 100 on a multi-core machine.
    pub cpu_percent: f32,
    pub memory_bytes: u64,
}

impl ProcessRow {
    /// A row for callers that only walk identity and parent links, like process
    /// tree termination. Usage reads zero because it was never refreshed.
    pub fn topology_only(pid: u32, parent_pid: Option<u32>, start_time: u64) -> ProcessRow {
        ProcessRow {
            pid,
            parent_pid,
            start_time,
            cpu_percent: 0.0,
            memory_bytes: 0,
        }
    }
}

/// A spawned shell's pid together with the start time observed at spawn.
///
/// The two travel together because a pid on its own is not an identity. The OS
/// reaps a shell before the reader thread reports the exit, so in that window
/// the pid may already belong to something else; the start time is what tells
/// the two apart.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ShellProcess {
    pub pid: u32,
    pub start_time: u64,
}

/// Aggregated usage of one process subtree.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct SubtreeUsage {
    pub cpu_percent: f64,
    pub memory_bytes: u64,
    pub process_count: u32,
}

/// Indexed process table: lookup by pid plus the child lists needed to walk
/// downwards from a shell.
pub struct ProcessIndex {
    by_pid: HashMap<u32, ProcessRow>,
    children_of: HashMap<u32, Vec<u32>>,
}

impl ProcessIndex {
    pub fn build(rows: impl IntoIterator<Item = ProcessRow>) -> ProcessIndex {
        let mut by_pid = HashMap::new();
        let mut children_of: HashMap<u32, Vec<u32>> = HashMap::new();
        for row in rows {
            if let Some(parent) = row.parent_pid {
                children_of.entry(parent).or_default().push(row.pid);
            }
            by_pid.insert(row.pid, row);
        }
        ProcessIndex {
            by_pid,
            children_of,
        }
    }

    /// Whether the pid still holds the process that was spawned at it.
    ///
    /// False for a pid that is gone, and false for one the OS has recycled onto
    /// an unrelated process. The check has second resolution, so a pid reused
    /// within the same second as the original spawn still matches: this bounds
    /// the window rather than closing it.
    pub fn holds(&self, shell: ShellProcess) -> bool {
        self.by_pid
            .get(&shell.pid)
            .is_some_and(|row| row.start_time == shell.start_time)
    }

    /// Every pid below `root`, excluding `root` itself.
    ///
    /// Only meaningful while the root is alive in this snapshot. Once it exits,
    /// its children reparent away and stop being reachable through it, and any
    /// row still naming the vacated pid as its parent is a recycle coincidence
    /// rather than a descendant. Callers prove liveness with `holds` first.
    pub fn descendants(&self, root: u32) -> Vec<u32> {
        let mut found = Vec::new();
        let mut seen = HashSet::from([root]);
        let mut pending = VecDeque::from([root]);
        while let Some(pid) = pending.pop_front() {
            let Some(children) = self.children_of.get(&pid) else {
                continue;
            };
            for &child in children {
                // `seen` also guards the cycle a mid-sweep recycle can fake.
                if seen.insert(child) {
                    found.push(child);
                    pending.push_back(child);
                }
            }
        }
        found
    }

    /// Sum a process and every descendant, skipping pids already claimed by an
    /// earlier subtree.
    ///
    /// The `claimed` set is what keeps a shared ancestor from being counted
    /// twice when one session's shell happens to sit under another's: the first
    /// caller wins and later callers see the pid as already spent.
    pub fn collect_subtree(&self, root: u32, claimed: &mut HashSet<u32>) -> SubtreeUsage {
        let mut usage = SubtreeUsage::default();
        let mut pending = VecDeque::from([root]);
        while let Some(pid) = pending.pop_front() {
            if !claimed.insert(pid) {
                continue;
            }
            let Some(row) = self.by_pid.get(&pid) else {
                continue;
            };
            usage.cpu_percent += f64::from(row.cpu_percent);
            usage.memory_bytes = usage.memory_bytes.saturating_add(row.memory_bytes);
            usage.process_count += 1;
            if let Some(children) = self.children_of.get(&pid) {
                pending.extend(children.iter().copied());
            }
        }
        usage
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Start time the tree-arithmetic cases share, since none of them turn on
    /// identity.
    const SPAWNED_AT: u64 = 1_000;

    fn row(pid: u32, parent_pid: Option<u32>, cpu_percent: f32, memory_bytes: u64) -> ProcessRow {
        ProcessRow {
            pid,
            parent_pid,
            start_time: SPAWNED_AT,
            cpu_percent,
            memory_bytes,
        }
    }

    fn shell(pid: u32, start_time: u64) -> ShellProcess {
        ShellProcess { pid, start_time }
    }

    #[test]
    fn a_subtree_sums_every_descendant() {
        let index = ProcessIndex::build([
            row(1, None, 1.0, 100),
            row(2, Some(1), 2.0, 200),
            row(3, Some(2), 4.0, 400),
            row(9, None, 8.0, 800),
        ]);

        let usage = index.collect_subtree(1, &mut HashSet::new());

        assert_eq!(usage.process_count, 3);
        assert_eq!(usage.memory_bytes, 700);
        assert!((usage.cpu_percent - 7.0).abs() < f64::EPSILON);
    }

    #[test]
    fn a_pid_is_only_counted_by_the_first_subtree_that_claims_it() {
        // A nested shell: session B's root sits inside session A's tree.
        let index = ProcessIndex::build([
            row(1, None, 1.0, 100),
            row(2, Some(1), 2.0, 200),
            row(3, Some(2), 4.0, 400),
        ]);
        let mut claimed = HashSet::new();

        let first = index.collect_subtree(1, &mut claimed);
        let second = index.collect_subtree(2, &mut claimed);

        assert_eq!(first.process_count, 3);
        assert_eq!(first.memory_bytes, 700);
        // Everything below 2 was already spent, so the total stays honest
        // instead of double counting 600 bytes.
        assert_eq!(second, SubtreeUsage::default());
    }

    #[test]
    fn an_unknown_root_yields_nothing() {
        let index = ProcessIndex::build([row(1, None, 1.0, 100)]);

        assert_eq!(
            index.collect_subtree(404, &mut HashSet::new()),
            SubtreeUsage::default()
        );
        assert!(!index.holds(shell(404, SPAWNED_AT)));
    }

    #[test]
    fn a_pid_still_running_the_spawned_process_is_held() {
        let index = ProcessIndex::build([row(1, None, 1.0, 100)]);

        assert!(index.holds(shell(1, SPAWNED_AT)));
    }

    #[test]
    fn a_recycled_pid_is_not_held() {
        // Same pid, later start time: the shell exited and the OS handed the
        // number to something else before the reader thread noticed.
        let index = ProcessIndex::build([row(1, None, 1.0, 100)]);

        assert!(!index.holds(shell(1, SPAWNED_AT + 1)));
    }

    /// Why the defense against thread rows has to live in the refresh rather
    /// than here.
    ///
    /// A thread looks exactly like a child process to this index: a pid whose
    /// parent is the process, reporting the RSS of the shared address space. The
    /// tree arithmetic cannot tell it apart from a real child that genuinely
    /// costs that memory, so it sums it and the total scales with the thread
    /// count. `claimed` does not help either, because every tid is a distinct pid
    /// nothing has claimed. The refresh must therefore never hand these rows
    /// over: see `without_tasks` in `sweep_process_topology` and `sample`.
    #[test]
    fn thread_shaped_rows_would_be_summed_as_real_children() {
        // One 100-byte process, plus three "threads" each repeating that RSS.
        let index = ProcessIndex::build([
            row(1, None, 1.0, 100),
            row(2, Some(1), 1.0, 100),
            row(3, Some(1), 1.0, 100),
            row(4, Some(1), 1.0, 100),
        ]);

        let usage = index.collect_subtree(1, &mut HashSet::new());

        assert_eq!(usage.memory_bytes, 400, "100 bytes counted once per row");
        assert_eq!(usage.process_count, 4);
    }

    #[test]
    fn a_parent_cycle_terminates() {
        // Defensive: a recycled pid can make the table look cyclic mid-sweep.
        let index = ProcessIndex::build([row(1, Some(2), 1.0, 100), row(2, Some(1), 2.0, 200)]);

        let usage = index.collect_subtree(1, &mut HashSet::new());

        assert_eq!(usage.process_count, 2);
        assert_eq!(usage.memory_bytes, 300);
    }
}

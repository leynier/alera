use std::collections::{HashMap, HashSet, VecDeque};

/// One row of the host process table, decoupled from `sysinfo` so the tree
/// arithmetic can be tested without touching the real system.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ProcessRow {
    pub pid: u32,
    pub parent_pid: Option<u32>,
    /// Percent of a single core, so it can exceed 100 on a multi-core machine.
    pub cpu_percent: f32,
    pub memory_bytes: u64,
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

    pub fn contains(&self, pid: u32) -> bool {
        self.by_pid.contains_key(&pid)
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

    fn row(pid: u32, parent_pid: Option<u32>, cpu_percent: f32, memory_bytes: u64) -> ProcessRow {
        ProcessRow {
            pid,
            parent_pid,
            cpu_percent,
            memory_bytes,
        }
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
        assert!(!index.contains(404));
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

use std::collections::HashSet;

use alera_core::git::hosted_review::HostedReviewOperation;
use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System};

pub(super) fn active_operation_ids(operations: &[HostedReviewOperation]) -> HashSet<String> {
    let pids = operations
        .iter()
        .map(|operation| Pid::from_u32(operation.owner_pid))
        .collect::<Vec<_>>();
    if pids.is_empty() {
        return HashSet::new();
    }
    let mut system = System::new();
    system.refresh_processes_specifics(
        ProcessesToUpdate::Some(&pids),
        true,
        ProcessRefreshKind::nothing().without_tasks(),
    );
    // A recycled pid can only preserve stale refs. That safe leak is preferable
    // to deleting a live fetch owned by another app process.
    operations
        .iter()
        .filter(|operation| system.process(Pid::from_u32(operation.owner_pid)).is_some())
        .map(|operation| operation.retention_id.clone())
        .collect()
}

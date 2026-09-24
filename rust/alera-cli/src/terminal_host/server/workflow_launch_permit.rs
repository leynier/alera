use alera_core::runtime::{WorkflowCoordinatorReceipt, WorkflowLaunchRecord, WorkflowLaunchStatus};

use super::WorkflowLaunchPermit;

impl WorkflowLaunchPermit {
    pub(in crate::terminal_host::server) fn coordinator(
        receipt: WorkflowCoordinatorReceipt,
    ) -> Self {
        Self {
            record: None,
            coordinator: Some(receipt),
        }
    }

    pub(in crate::terminal_host::server) fn allows(
        &self,
        record: &WorkflowLaunchRecord,
        workspace: &str,
        tab: &str,
    ) -> bool {
        self.record.as_ref().is_some_and(|owned| {
            owned.id == record.id && owned.terminal_handle == record.terminal_handle
        }) && record.request.workspace_id == workspace
            && record.terminal_handle == tab
            && record.status == WorkflowLaunchStatus::Starting
    }
}

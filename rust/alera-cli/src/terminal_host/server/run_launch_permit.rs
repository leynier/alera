use alera_core::runtime::{WorkflowCoordinatorReceipt, WorkflowLaunchRecord, WorkflowLaunchStatus};

/// Constructed only after the durable one-shot claim. No payload grants this.
pub(crate) struct WorkflowLaunchPermit {
    pub(super) record: Option<WorkflowLaunchRecord>,
    pub(super) coordinator: Option<WorkflowCoordinatorReceipt>,
}

impl WorkflowLaunchPermit {
    pub(in crate::terminal_host::server) fn coordinator(
        receipt: WorkflowCoordinatorReceipt,
    ) -> Self {
        Self {
            record: None,
            coordinator: Some(receipt),
        }
    }

    /// The run whose coordinator this permit launches.
    pub(in crate::terminal_host::server) fn coordinator_run_id(&self) -> Option<&str> {
        self.coordinator
            .as_ref()
            .map(|receipt| receipt.run_id.as_str())
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

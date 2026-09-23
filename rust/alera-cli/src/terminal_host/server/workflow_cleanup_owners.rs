use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    /// Runs after a durable claim, on the actor lane. A spawn already past its
    /// fence finishes on this same lane before this inspection can be handled.
    pub(in crate::terminal_host::server) async fn inspect_workflow_cleanup_owners(
        &self,
        cleanup_id: &str,
        digest: &str,
        workspace_id: &str,
    ) -> HostResult<()> {
        self.runtime_store
            .require_retained_cleanup_resource(cleanup_id, digest, workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if self
            .sessions
            .values()
            .any(|session| session.workspace_id == workspace_id && session.running())
        {
            return Err(HostError::state("Workspace has a live terminal or process. Stop it explicitly before retrying cleanup."));
        }
        if self.browser.has_pages_for_workspace(workspace_id) {
            return Err(HostError::state(
                "Workspace has a live browser page. Close it explicitly before retrying cleanup.",
            ));
        }
        if self.emulator_requests.has_runtime_mutations() || self.managed_workspace_jobs > 1 {
            return Err(HostError::state(
                "Runtime workspace jobs are still active. Retry cleanup after they settle.",
            ));
        }
        Ok(())
    }
}

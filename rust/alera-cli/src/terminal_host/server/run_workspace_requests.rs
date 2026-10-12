use serde_json::Value;

use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::protocol::{error_response, ok_response};

use super::{ServerActor, ServerCommand};

#[cfg(test)]
mod tests;

impl ServerActor {
    pub(super) fn has_blocking_managed_workspace_jobs(&self) -> bool {
        // Workflow requests and startup reconciliation use per-resource locks
        // and retained ownership receipts. They keep the host alive, but must
        // not reject unrelated terminal or orchestration requests.
        self.managed_workspace_jobs > usize::from(self.workflow_workspace_recovery_running)
    }

    pub(super) fn start_workflow_workspace_recovery(&mut self) {
        self.managed_workspace_jobs += 1;
        self.workflow_workspace_recovery_running = true;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let directory = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        let runtime = tokio::runtime::Handle::current();
        tokio::spawn(async move {
            let events = inbox.clone();
            let result = tokio::task::spawn_blocking(move || {
                runtime.block_on(async {
                    crate::managed_workspace::run::integration::reconcile(&store, &directory)
                        .await?;
                    crate::managed_workspace::run::recovery::reconcile(&store, &directory).await?;
                    super::run_cleanup_execution::reconcile(&store, &directory, &events).await
                })
            })
            .await;
            if !matches!(&result, Ok(Ok(()))) {
                tracing::warn!("workflow workspace recovery needs attention: {result:?}");
            }
            let _ = inbox
                .send_wait(ServerCommand::WorkflowWorkspaceRecoveryFinished)
                .await;
        });
    }

    pub(super) async fn handle_workflow_workspace_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
        mutated: bool,
    ) {
        self.workflow_workspace_jobs = self.workflow_workspace_jobs.saturating_sub(1);
        match result {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
        if mutated {
            self.broadcast_workspaces_changed(None);
            self.broadcast_orchestration_board_change().await;
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn handle_workflow_workspace_recovery_finished(&mut self) {
        self.workflow_execution.ready = true;
        self.wake_workflow_execution();
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        self.workflow_workspace_recovery_running = false;
        self.broadcast_workspaces_changed(None);
        self.broadcast_orchestration_board_change().await;
        self.schedule_shutdown_if_idle();
    }
}

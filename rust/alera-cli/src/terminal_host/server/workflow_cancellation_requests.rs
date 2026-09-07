use alera_core::runtime::WorkflowCancellationTarget;

use super::{ServerActor, WorkflowLaunchCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::ServerCommand;

impl ServerActor {
    pub(in crate::terminal_host::server) fn wake_workflow_cancellation(&mut self) {
        if self.workflow_execution.cancelling {
            self.workflow_execution.cancellation_dirty = true;
            return;
        }
        self.workflow_execution.cancelling = true;
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        // Independent from worktree setup/integration so a slow Git or setup
        // job never delays stopping the run's already-active workers.
        tokio::spawn(async move {
            let result = async {
                let targets = store.workflow_cancellation_page().await?;
                let progress = !targets.is_empty();
                for target in targets {
                    let (reply, done) = tokio::sync::oneshot::channel();
                    inbox
                        .send(ServerCommand::WorkflowLaunch(
                            WorkflowLaunchCommand::CancelTerminal {
                                target: target.clone(),
                                reply,
                            },
                        ))
                        .map_err(|_| {
                            anyhow::anyhow!("runtime closed before workflow cancellation")
                        })?;
                    let result = done.await.map_err(|_| {
                        anyhow::anyhow!("runtime closed during workflow cancellation")
                    })?;
                    let error = result.err().map(|error| error.wire_message());
                    store
                        .settle_workflow_cancellation(&target, error.as_deref())
                        .await?;
                }
                Ok::<bool, anyhow::Error>(progress)
            }
            .await
            .map_err(|error| HostError::state(error.to_string()));
            let _ = inbox.send(ServerCommand::WorkflowLaunch(
                WorkflowLaunchCommand::CancellationFinished(result),
            ));
        });
    }

    pub(super) async fn finish_workflow_cancellation(&mut self, result: HostResult<bool>) {
        self.workflow_execution.cancelling = false;
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        let dirty = std::mem::take(&mut self.workflow_execution.cancellation_dirty);
        match result {
            Ok(progress) => {
                self.broadcast_orchestration_board_change().await;
                if !self.disposed && (progress || dirty) {
                    self.wake_workflow_cancellation();
                }
            }
            Err(error) => tracing::warn!(
                "workflow cancellation needs recovery: {}",
                error.wire_message()
            ),
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn cancel_workflow_terminal(
        &mut self,
        target: &WorkflowCancellationTarget,
    ) -> HostResult<()> {
        self.runtime_store
            .require_workflow_cancellation_target(target)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        // Never use a tab-wide or workspace-wide termination if a live session
        // has drifted from the immutable launch identity.
        if self.sessions.iter().any(|(id, session)| {
            (id == &target.terminal_handle || session.tab_id == target.terminal_handle)
                && (id != &target.terminal_handle
                    || session.tab_id != target.terminal_handle
                    || session.workspace_id != target.workspace_id)
        }) {
            return Err(HostError::state("The live terminal identity changed. Inspect the retained attempt before retrying cancellation."));
        }
        self.terminate_sessions_for_tab(&target.terminal_handle)
            .await;
        self.remove_dispatch_context(&target.terminal_handle);
        Ok(())
    }
}

use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::session::Session;
use serde_json::Value;

impl ServerActor {
    pub(super) fn schedule_workflow_launch_acceptance_timeout(&self, id: &str) {
        let inbox = self.inbox.clone();
        let id = id.to_owned();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(120)).await;
            let _ = inbox.send(super::ServerCommand::WorkflowLaunch(
                super::workflow_launch_requests::WorkflowLaunchCommand::AcceptanceTimeout(id),
            ));
        });
    }

    pub(super) async fn handle_workflow_launch_acceptance_timeout(&mut self, id: &str) {
        let result = async {
            let launch = self.runtime_store.workflow_launch(id).await?;
            let dispatch = self.runtime_store.orchestration_dispatch_by_id(&launch.dispatch_id).await?;
            if dispatch.is_some_and(|dispatch| dispatch.status == alera_core::runtime::OrchestrationDispatchStatus::AwaitingAcceptance) {
                self.terminate_sessions_for_tab(&launch.terminal_handle).await;
                self.remove_dispatch_context(&launch.terminal_handle);
                self.settle_closed_workflow_terminal(&launch.terminal_handle,
                    "The worker did not accept its task before the startup deadline. Inspect this attempt and retry explicitly.").await;
            }
            Ok::<(), anyhow::Error>(())
        }.await;
        if let Err(error) = result {
            tracing::warn!("workflow acceptance timeout needs attention: {error}");
        }
    }
    pub(super) async fn attach_workflow_terminal(
        &mut self,
        client: u64,
        terminal: &str,
        workspace: &str,
        tab: &str,
    ) -> HostResult<Option<Value>> {
        let by_terminal = self
            .runtime_store
            .workflow_launch_for_terminal(terminal)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let by_tab = self
            .runtime_store
            .workflow_launch_for_terminal(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let Some(record) = by_terminal.or(by_tab) else {
            return Ok(None);
        };
        if record.terminal_handle != terminal
            || record.terminal_handle != tab
            || record.request.workspace_id != workspace
        {
            return Err(HostError::state(
                "workflow terminal identity does not match its launch",
            ));
        }
        if !self.sessions.contains_key(terminal) {
            let session = Session::restore_exited(terminal.into(), workspace.into(), tab.into(), &self.store, self.config.scrollback_bytes as usize).await
                .ok_or_else(|| HostError::state("The worker did not produce a terminal checkpoint. Inspect its launch in the Run Board."))?;
            self.sessions.insert(terminal.into(), session);
        }
        self.flush_all_output(terminal);
        let session = self
            .sessions
            .get_mut(terminal)
            .expect("workflow session was restored");
        if session.workspace_id != workspace || session.tab_id != tab {
            return Err(HostError::state("live workflow terminal identity changed"));
        }
        session.attach(client);
        Ok(Some(session.attachment_payload(
            false,
            self.config.restore_snapshot_bytes as usize,
        )))
    }
    pub(super) async fn reconcile_workflow_launches(&mut self) {
        let result = async {
            let mut after = 0;
            loop {
                let page = self.runtime_store.workflow_launch_recovery_page(after).await?;
                if page.is_empty() { break; }
                for (sequence, launch) in page {
                    after = sequence;
                    if let Some(session) = self.sessions.get(&launch.terminal_handle) {
                        if session.running() {
                            if session.workspace_id != launch.request.workspace_id || session.tab_id != launch.terminal_handle {
                                self.runtime_store.workflow_launch_attention(&launch.id, "The terminal identity changed. Inspect the retained attempt.").await?;
                            }
                            continue;
                        }
                    }
                    self.runtime_store.settle_workflow_launch_without_session(&launch.terminal_handle,
                        "The worker session did not survive the host restart. Inspect the retained worktree and retry explicitly in a new attempt.").await?;
                    self.remove_dispatch_context(&launch.terminal_handle);
                }
            }
            Ok::<(), anyhow::Error>(())
        }.await;
        if let Err(error) = result {
            tracing::warn!("workflow launch reconciliation needs attention: {error}");
        }
    }

    pub(super) async fn settle_closed_workflow_terminal(&mut self, terminal: &str, reason: &str) {
        if !self.is_workflow_terminal(terminal).await {
            return;
        }
        if let Err(error) = self
            .runtime_store
            .settle_workflow_launch_without_session(terminal, reason)
            .await
        {
            tracing::warn!("workflow launch settlement needs attention: {error}");
        }
        self.broadcast_orchestration_board_change().await;
    }

    pub(super) async fn is_workflow_terminal(&self, terminal: &str) -> bool {
        match self
            .runtime_store
            .workflow_launch_for_terminal(terminal)
            .await
        {
            Ok(record) => record.is_some(),
            Err(error) => {
                tracing::warn!("workflow terminal ownership is unavailable: {error}");
                true
            }
        }
    }
}

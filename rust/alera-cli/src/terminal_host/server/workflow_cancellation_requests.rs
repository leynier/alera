use std::time::Duration;

use alera_core::runtime::{
    RuntimeStore, WorkflowCancellationTarget, WorkflowProposalCancellation,
    WorkflowTerminalShutdownState,
};

use super::{ServerActor, WorkflowLaunchCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::ServerCommand;
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

pub(crate) enum CancellationShutdown {
    AlreadyClosed,
    Wait(WorkspaceShutdown),
}

impl ServerActor {
    pub(super) fn retain_cancellation_shutdown(
        &mut self,
        tab: String,
        shutdown: WorkspaceShutdown,
    ) {
        if let Some(mut pending) = self.workflow_execution.cancellation_shutdowns.remove(&tab) {
            pending.merge(shutdown);
            self.workflow_execution
                .cancellation_shutdowns
                .insert(tab, pending);
        } else {
            self.workflow_execution
                .cancellation_shutdowns
                .insert(tab, shutdown);
        }
    }

    pub(in crate::terminal_host::server) fn wake_workflow_cancellation(&mut self) {
        self.start_workflow_cancellation(Duration::ZERO);
    }

    fn start_workflow_cancellation(&mut self, delay: Duration) {
        if self.disposed {
            return;
        }
        if self.workflow_execution.cancelling {
            self.workflow_execution.cancellation_dirty = true;
            return;
        }
        self.workflow_execution.cancelling = true;
        self.workflow_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let directory = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        // Independent from worktree setup/integration so a slow Git or setup
        // job never delays stopping the run's already-active workers.
        tokio::spawn(async move {
            if !delay.is_zero() {
                tokio::time::sleep(delay).await;
            }
            let result = async {
                let targets = store.workflow_cancellation_page().await?;
                let proposals = store.pending_workflow_proposal_cancellations().await?;
                let progress = !targets.is_empty() || !proposals.is_empty();
                let mut settlement_error = None;
                for target in proposals {
                    let (reply, done) = tokio::sync::oneshot::channel();
                    inbox
                        .send(ServerCommand::WorkflowLaunch(
                            WorkflowLaunchCommand::CancelProposalTerminal {
                                target: target.clone(),
                                reply,
                            },
                        ))
                        .map_err(|_| {
                            anyhow::anyhow!("runtime closed before proposal cancellation")
                        })?;
                    let result = done.await.map_err(|_| {
                        anyhow::anyhow!("runtime closed during proposal cancellation")
                    })?;
                    let error = match result {
                        Ok(shutdown) => finish_shutdown(
                            &store,
                            &inbox,
                            target.tab_id.as_deref().unwrap_or_default(),
                            &target.workspace_id,
                            shutdown,
                        )
                        .await
                        .err()
                        .map(|error| error.wire_message()),
                        Err(error) => Some(error.wire_message()),
                    };
                    if let Err(error) = settle_proposal(&store, &target, error.as_deref()).await {
                        settlement_error.get_or_insert(error);
                    }
                }
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
                    let error = match result {
                        Ok(shutdown) => finish_shutdown(
                            &store,
                            &inbox,
                            &target.terminal_handle,
                            &target.workspace_id,
                            shutdown,
                        )
                        .await
                        .err()
                        .map(|error| error.wire_message()),
                        Err(error) => Some(error.wire_message()),
                    };
                    if let Err(error) = settle_run(&store, &target, error.as_deref()).await {
                        settlement_error.get_or_insert(error);
                    }
                }
                // Stop processes first; cancelled integration inspection is
                // read-only Git work on a bounded, off-actor blocking job.
                let cleanup_store = store.clone();
                let runtime = tokio::runtime::Handle::current();
                tokio::task::spawn_blocking(move || {
                    runtime.block_on(
                        crate::managed_workspace::workflow::integration::reconcile_cancelled(
                            &cleanup_store,
                            &directory,
                        ),
                    )
                })
                .await??;
                if let Some(error) = settlement_error {
                    return Err(error);
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
        self.workflow_workspace_jobs = self.workflow_workspace_jobs.saturating_sub(1);
        let dirty = std::mem::take(&mut self.workflow_execution.cancellation_dirty);
        match result {
            Ok(progress) => {
                self.broadcast_orchestration_board_change().await;
                if !self.disposed && (progress || dirty) {
                    self.wake_workflow_cancellation();
                }
            }
            Err(error) => {
                tracing::warn!(
                    "workflow cancellation needs recovery: {}",
                    error.wire_message()
                );
                self.workflow_execution.cancellation_dirty |= dirty;
                self.broadcast_orchestration_board_change().await;
                // Retry undurable failures off-actor; recorded Attention rows
                // remain excluded and require an explicit human retry.
                self.start_workflow_cancellation(Duration::from_secs(2));
            }
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn cancel_workflow_terminal(
        &mut self,
        target: &WorkflowCancellationTarget,
    ) -> HostResult<CancellationShutdown> {
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
        let shutdown = self
            .prepare_workflow_cancellation_shutdown(&target.terminal_handle, &target.workspace_id)
            .await?;
        self.remove_dispatch_context(&target.terminal_handle);
        Ok(shutdown)
    }

    pub(in crate::terminal_host::server) async fn cancel_workflow_proposal_terminal(
        &mut self,
        target: &alera_core::runtime::WorkflowProposalCancellation,
    ) -> HostResult<CancellationShutdown> {
        self.runtime_store
            .require_workflow_proposal_cancellation_target(target)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let tab = target
            .tab_id
            .as_ref()
            .ok_or_else(|| HostError::state("proposal cancellation has no terminal target"))?;
        if self.sessions.iter().any(|(id, session)| {
            (id == tab || &session.tab_id == tab)
                && (id != tab
                    || &session.tab_id != tab
                    || session.workspace_id != target.workspace_id)
        }) {
            return Err(HostError::state(
                "The proposal terminal identity changed. Inspect the retained coordinator.",
            ));
        }
        let shutdown = self
            .prepare_workflow_cancellation_shutdown(tab, &target.workspace_id)
            .await?;
        self.remove_dispatch_context(tab);
        Ok(shutdown)
    }

    async fn prepare_workflow_cancellation_shutdown(
        &mut self,
        tab: &str,
        workspace: &str,
    ) -> HostResult<CancellationShutdown> {
        let state = self
            .runtime_store
            .workflow_terminal_shutdown_state(tab, workspace)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if let Some(session) = self.sessions.get(tab) {
            if state != WorkflowTerminalShutdownState::Unstarted && session.running() {
                return Err(HostError::state(
                    "The terminal has a new session after cancellation started. Inspect its owner before retrying.",
                ));
            }
            if state == WorkflowTerminalShutdownState::Unstarted {
                let shutdown = WorkspaceShutdown::capture(std::iter::once(session)).await?;
                self.runtime_store
                    .begin_workflow_terminal_shutdown(tab, workspace)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                self.terminate_sessions_for_tab(tab).await;
                return Ok(CancellationShutdown::Wait(shutdown));
            }
        }
        if let Some(shutdown) = self.workflow_execution.cancellation_shutdowns.remove(tab) {
            return Ok(CancellationShutdown::Wait(shutdown));
        }
        if state == WorkflowTerminalShutdownState::Started {
            return Err(HostError::state(
                "The host restarted before process closure was verified. Inspect the retained terminal and its processes before cleanup.",
            ));
        }
        Ok(CancellationShutdown::AlreadyClosed)
    }
}

async fn settle_run(
    store: &RuntimeStore,
    target: &WorkflowCancellationTarget,
    error: Option<&str>,
) -> anyhow::Result<()> {
    if let Err(failure) = store.settle_workflow_cancellation(target, error).await {
        store
            .settle_workflow_cancellation(target, Some(&failure.to_string()))
            .await?;
    }
    Ok(())
}

async fn settle_proposal(
    store: &RuntimeStore,
    target: &WorkflowProposalCancellation,
    error: Option<&str>,
) -> anyhow::Result<()> {
    if let Err(failure) = store
        .settle_workflow_proposal_cancellation(target, error)
        .await
    {
        store
            .settle_workflow_proposal_cancellation(target, Some(&failure.to_string()))
            .await?;
    }
    Ok(())
}

async fn finish_shutdown(
    store: &alera_core::runtime::RuntimeStore,
    inbox: &tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    tab: &str,
    workspace: &str,
    shutdown: CancellationShutdown,
) -> HostResult<()> {
    let CancellationShutdown::Wait(mut guard) = shutdown else {
        return Ok(());
    };
    let result = async {
        guard.wait().await?;
        store
            .verify_workflow_terminal_shutdown(tab, workspace)
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }
    .await;
    if result.is_err() {
        let (reply, done) = tokio::sync::oneshot::channel();
        inbox
            .send(ServerCommand::WorkflowLaunch(
                WorkflowLaunchCommand::RetainCancellationShutdown {
                    tab: tab.to_owned(),
                    shutdown: guard,
                    reply,
                },
            ))
            .map_err(|_| HostError::state("runtime closed before process shutdown was retained"))?;
        done.await
            .map_err(|_| HostError::state("runtime closed before process shutdown was retained"))?;
    }
    result
}

#[cfg(test)]
#[path = "workflow_cancellation_recovery_tests.rs"]
mod recovery_tests;

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use alera_core::runtime::WorkflowTerminalShutdownState;
    use chrono::Utc;

    use super::{finish_shutdown, CancellationShutdown, WorkspaceShutdown};
    use crate::terminal_host::history_store::TerminalHostCheckpoint;
    use crate::terminal_host::server::actor_test_harness::test_actor;
    use crate::terminal_host::session::Session;

    #[tokio::test]
    async fn failed_shutdown_wait_retains_guard_for_explicit_retry() {
        let dir = tempfile::tempdir().unwrap();
        let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
        let store = actor.runtime_store.clone();
        store
            .begin_workflow_terminal_shutdown("tab", "owner")
            .await
            .unwrap();
        let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
        actor.inbox = inbox.clone();
        let mut guard = WorkspaceShutdown::default();
        guard.fail_next_waits(1);
        let first = tokio::spawn({
            let store = store.clone();
            let inbox = inbox.clone();
            async move {
                finish_shutdown(
                    &store,
                    &inbox,
                    "tab",
                    "owner",
                    CancellationShutdown::Wait(guard),
                )
                .await
            }
        });
        actor.handle(commands.recv().await.unwrap()).await;
        assert!(first.await.unwrap().is_err());
        assert_eq!(
            store
                .workflow_terminal_shutdown_state("tab", "owner")
                .await
                .unwrap(),
            WorkflowTerminalShutdownState::Started
        );
        actor
            .store
            .upsert(TerminalHostCheckpoint {
                session_id: "tab".into(),
                workspace_id: "owner".into(),
                tab_id: "tab".into(),
                working_directory: dir.path().to_string_lossy().into_owned(),
                running: false,
                exit_code: Some(0),
                ended_at: Some(Utc::now()),
                output_stream_bytes: 0,
                updated_at: Utc::now(),
                buffer: Vec::new(),
            })
            .await
            .unwrap();
        let restored = Session::restore_exited(
            "tab".into(),
            "owner".into(),
            "tab".into(),
            &actor.store,
            1024,
        )
        .await
        .unwrap();
        assert!(!restored.running());
        actor.sessions.insert("tab".into(), restored);
        let mut restarted = test_actor(&dir, HashMap::new(), HashMap::new()).await;
        restarted.sessions.insert(
            "tab".into(),
            Session::restore_exited(
                "tab".into(),
                "owner".into(),
                "tab".into(),
                &restarted.store,
                1024,
            )
            .await
            .unwrap(),
        );
        assert!(restarted
            .prepare_workflow_cancellation_shutdown("tab", "owner")
            .await
            .is_err());
        restarted.dispose().await;
        let retry = actor
            .prepare_workflow_cancellation_shutdown("tab", "owner")
            .await
            .unwrap();
        assert!(actor.workflow_execution.cancellation_shutdowns.is_empty());
        finish_shutdown(&store, &inbox, "tab", "owner", retry)
            .await
            .unwrap();
        assert_eq!(
            store
                .workflow_terminal_shutdown_state("tab", "owner")
                .await
                .unwrap(),
            WorkflowTerminalShutdownState::Verified
        );
        actor.dispose().await;
    }
}

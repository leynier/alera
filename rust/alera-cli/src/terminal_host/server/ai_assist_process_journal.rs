use alera_core::runtime::{RuntimeStore, Workspace, WorkspaceProcessJob, WorkspaceProcessJobPhase};

use crate::process_identity::{ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe};
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) struct AiAssistProcessOwner {
    pub store: RuntimeStore,
    pub workspace: Workspace,
    pub operation_id: String,
}

pub(super) struct AiAssistProcessJournal {
    store: RuntimeStore,
    record: WorkspaceProcessJob,
}

impl AiAssistProcessOwner {
    pub(super) async fn begin(&self) -> HostResult<AiAssistProcessJournal> {
        let boot = tokio::task::spawn_blocking(crate::relocation_setup_process::current_boot_id)
            .await
            .map_err(journal_error)?
            .map_err(journal_error)?;
        let record = self
            .store
            .begin_workspace_process_job(
                &self.workspace,
                &self.operation_id,
                std::env::consts::OS,
                boot,
            )
            .await
            .map_err(journal_error)?;
        Ok(AiAssistProcessJournal {
            store: self.store.clone(),
            record,
        })
    }
}

impl AiAssistProcessJournal {
    pub(super) async fn spawned(&mut self, pid: u32) -> HostResult<()> {
        let identity = tokio::task::spawn_blocking(move || SystemProcessIdentityProbe.lookup(pid))
            .await
            .map_err(journal_error)?;
        let marker = match identity {
            ProcessLookup::Live(identity) => Some(identity.start_marker),
            ProcessLookup::Exited | ProcessLookup::Unknown(_) => None,
        };
        self.record = self
            .store
            .record_workspace_process_spawn(&self.record, pid, marker)
            .await
            .map_err(journal_error)?;
        Ok(())
    }

    pub(super) async fn spawn_failed(&mut self) -> HostResult<()> {
        self.phase(WorkspaceProcessJobPhase::SpawnFailed).await
    }

    pub(super) async fn root_exited(&mut self) -> HostResult<()> {
        self.phase(WorkspaceProcessJobPhase::RootExited).await
    }

    // The caller retains the unreaped session root until its native guard verifies closure.
    #[cfg(unix)]
    pub(super) async fn unix_session_closed(&mut self) -> HostResult<()> {
        self.phase(WorkspaceProcessJobPhase::ClosureVerified).await
    }

    #[cfg(windows)]
    pub(super) async fn windows_job_closed(
        &mut self,
        scope: &mut crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown,
    ) -> HostResult<()> {
        scope.wait().await?;
        self.phase(WorkspaceProcessJobPhase::ClosureVerified).await
    }

    async fn phase(&mut self, phase: WorkspaceProcessJobPhase) -> HostResult<()> {
        self.record = self
            .store
            .record_workspace_process_phase(&self.record, phase)
            .await
            .map_err(journal_error)?;
        Ok(())
    }
}

fn journal_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(format!(
        "AI Assist process evidence could not be recorded: {error}"
    ))
}

#[cfg(all(test, windows))]
#[path = "ai_assist_process_journal_windows_tests.rs"]
mod windows_tests;

use std::time::Duration;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::Session;

#[cfg(unix)]
#[path = "workspace_shutdown_unix.rs"]
mod platform;
#[cfg(windows)]
#[path = "workspace_shutdown_windows.rs"]
mod platform;

const GRACE_PERIOD: Duration = Duration::from_secs(4);
const KILL_PERIOD: Duration = Duration::from_secs(2);
const POLL_INTERVAL: Duration = Duration::from_millis(50);

/// Retains process ownership before sessions disappear from the actor. Waiting
/// belongs to the mutation worker so slow shutdown cannot stall other clients.
#[derive(Default)]
pub(crate) struct WorkspaceShutdown {
    guards: Vec<platform::ShutdownGuard>,
    pub(crate) closed_tab_ids: Vec<String>,
    operation_completions: Vec<tokio::sync::oneshot::Receiver<()>>,
    unverified_operation_completion: bool,
    #[cfg(test)]
    failed_waits_remaining: usize,
}

impl WorkspaceShutdown {
    pub(crate) async fn capture<'a>(
        sessions: impl Iterator<Item = &'a Session>,
    ) -> HostResult<Self> {
        let sessions = sessions.collect::<Vec<_>>();
        if sessions.is_empty() {
            return Ok(Self::default());
        }
        Ok(Self {
            guards: vec![platform::ShutdownGuard::capture(&sessions).await?],
            closed_tab_ids: sessions
                .iter()
                .map(|session| session.tab_id.clone())
                .collect(),
            operation_completions: Vec::new(),
            unverified_operation_completion: false,
            #[cfg(test)]
            failed_waits_remaining: 0,
        })
    }

    #[cfg(unix)]
    pub(crate) async fn capture_command(pid: u32) -> HostResult<Self> {
        Ok(Self {
            guards: vec![platform::ShutdownGuard::capture_command(pid).await?],
            ..Self::default()
        })
    }

    #[cfg(unix)]
    pub(crate) async fn wait_command_root(pid: u32) -> HostResult<()> {
        while !platform::command_root_exited(pid)? {
            tokio::time::sleep(POLL_INTERVAL).await;
        }
        Ok(())
    }

    #[cfg(windows)]
    pub(crate) fn capture_command_job(
        job: &super::windows_process_job::WindowsProcessJob,
    ) -> HostResult<Self> {
        Ok(Self {
            guards: vec![platform::ShutdownGuard::capture_command_job(
                job.shutdown_handle()?,
            )?],
            ..Self::default()
        })
    }

    pub(crate) fn merge(&mut self, mut pending: Self) {
        pending.guards.append(&mut self.guards);
        self.guards = pending.guards;
        self.closed_tab_ids.append(&mut pending.closed_tab_ids);
        self.operation_completions
            .append(&mut pending.operation_completions);
        self.unverified_operation_completion |= pending.unverified_operation_completion;
        #[cfg(test)]
        {
            self.failed_waits_remaining += pending.failed_waits_remaining;
        }
    }

    pub(crate) fn wait_for_operations(
        &mut self,
        completions: Vec<tokio::sync::oneshot::Receiver<()>>,
    ) {
        self.operation_completions.extend(completions);
    }

    #[cfg(test)]
    pub(crate) fn fail_next_waits(&mut self, count: usize) {
        self.failed_waits_remaining = count;
    }

    pub(crate) async fn wait(&mut self) -> HostResult<()> {
        if self.unverified_operation_completion {
            return Err(shutdown_error(
                "background operation completion could not be verified",
            ));
        }
        #[cfg(test)]
        if self.failed_waits_remaining > 0 {
            self.failed_waits_remaining -= 1;
            return Err(shutdown_error("injected process inspection failure"));
        }
        while let Some(guard) = self.guards.last_mut() {
            guard.wait().await?;
            self.guards.pop();
        }
        // Completion releases the in-memory job only. The mutation must still
        // verify the durable process-closure evidence before removing its owner.
        let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
        while let Some(completion) = self.operation_completions.last_mut() {
            let finished = tokio::time::timeout_at(deadline, completion)
                .await
                .map_err(|_| {
                    shutdown_error("background operations have not finished; retry cleanup")
                })?;
            self.operation_completions.pop();
            if finished.is_err() {
                self.unverified_operation_completion = true;
                return Err(shutdown_error(
                    "background operation completion could not be verified",
                ));
            }
        }
        Ok(())
    }
}

fn shutdown_error(message: impl std::fmt::Display) -> HostError {
    HostError::state(format!("Workspace process shutdown failed: {message}"))
}

#[cfg(test)]
mod tests {
    use super::WorkspaceShutdown;

    #[tokio::test]
    async fn disconnected_operation_completion_stays_unverified_after_retry() {
        let (sender, receiver) = tokio::sync::oneshot::channel();
        let mut shutdown = WorkspaceShutdown::default();
        shutdown.wait_for_operations(vec![receiver]);
        drop(sender);
        assert!(shutdown.wait().await.is_err());
        let mut retry = WorkspaceShutdown::default();
        retry.merge(shutdown);
        assert!(retry.wait().await.is_err());
    }
}

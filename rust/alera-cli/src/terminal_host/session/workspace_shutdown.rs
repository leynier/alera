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
            #[cfg(test)]
            failed_waits_remaining: 0,
        })
    }

    pub(crate) fn merge(&mut self, mut pending: Self) {
        pending.guards.append(&mut self.guards);
        self.guards = pending.guards;
        self.closed_tab_ids.append(&mut pending.closed_tab_ids);
        #[cfg(test)]
        {
            self.failed_waits_remaining += pending.failed_waits_remaining;
        }
    }

    #[cfg(test)]
    pub(crate) fn fail_next_waits(&mut self, count: usize) {
        self.failed_waits_remaining = count;
    }

    pub(crate) async fn wait(&mut self) -> HostResult<()> {
        #[cfg(test)]
        if self.failed_waits_remaining > 0 {
            self.failed_waits_remaining -= 1;
            return Err(shutdown_error("injected process inspection failure"));
        }
        while let Some(guard) = self.guards.last_mut() {
            guard.wait().await?;
            self.guards.pop();
        }
        Ok(())
    }
}

fn shutdown_error(message: impl std::fmt::Display) -> HostError {
    HostError::state(format!("Workspace process shutdown failed: {message}"))
}

use std::time::Duration;

use serde_json::{json, Value};

use crate::terminal_host::control_file;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::TerminalHostConfig;
use crate::terminal_host::session::Session;

use super::{
    ServerActor, ServerCommand, DURABLE_OUTPUT_BATCH_DELAY, OUTPUT_BATCH_DELAY,
    OUTPUT_RESYNC_RETRY_DELAY,
};

#[cfg(test)]
mod tests;

impl ServerActor {
    pub(super) fn promote_persistent(&mut self) -> HostResult<Value> {
        if !self.config.persistent {
            control_file::promote_persistent(&self.control_file_path)
                .map_err(|error| HostError::state(error.to_string()))?;
            self.config.persistent = true;
            self.cancel_shutdown_timer();
        }
        Ok(json!({"persistent": true}))
    }

    pub(super) async fn apply_config(&mut self, config: TerminalHostConfig) {
        self.config = TerminalHostConfig {
            persistent: self.config.persistent,
            ..config
        };
        let max_bytes = config.scrollback_bytes as usize;
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in &session_ids {
            self.flush_all_output(session_id);
            if let Some(session) = self.sessions.get_mut(session_id) {
                session.set_max_bytes(max_bytes);
            }
        }
        // Applying the cap to what is on disk is housekeeping, and awaiting it
        // parked the single actor behind two write barriers and a trim per
        // session. The app sends `configure` at startup, so every attach after
        // it queued behind that. A write landing after this trim just leaves
        // the session briefly over the cap; the checkpoint tick trims again.
        let store = self.store.clone();
        tokio::spawn(async move {
            for session_id in session_ids {
                let _ = store.trim_session(&session_id, max_bytes).await;
            }
        });
        self.schedule_shutdown_if_idle();
    }

    pub(super) fn has_authenticated_clients(&self) -> bool {
        self.clients.values().any(|client| client.authenticated)
    }

    fn has_running_sessions(&self) -> bool {
        self.sessions.values().any(Session::running)
            || self.emulators.as_ref().is_some_and(|emulators| {
                emulators
                    .try_lock()
                    .map_or(true, |manager| manager.active_count() > 0)
            })
    }

    pub(super) fn schedule_shutdown_if_idle(&mut self) {
        if self.disposed
            || self.config.persistent
            || self.has_authenticated_clients()
            || !self.ssh_bootstrap_jobs.is_empty()
            || self.managed_workspace_jobs > 0
            || self.emulator_requests.outstanding() > 0
            || self.account_push.cloud_jobs > 0
            || !self.project_clone_jobs.is_empty()
            || self.mobile_gateway.is_some()
            || !self.coordinators.is_empty()
            || self.browser.active_jobs() > 0
            || self.account_push.active_subscriptions > 0
        {
            self.cancel_shutdown_timer();
            return;
        }
        let seconds = if self.has_running_sessions() {
            self.config.detached_session_shutdown_delay_seconds
        } else {
            self.config.empty_shutdown_delay_seconds
        };
        self.shutdown_gen += 1;
        let generation = self.shutdown_gen;
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(seconds)).await;
            let _ = inbox.send(ServerCommand::ShutdownTick { generation });
        });
    }

    pub(super) fn spawn_output_batch_timer(&self, session_id: String, generation: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(OUTPUT_BATCH_DELAY).await;
            let _ = inbox.send(ServerCommand::OutputBatchTick {
                session_id,
                generation,
            });
        });
    }

    pub(super) fn spawn_output_resync_timer(&self, session_id: String, client_id: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(OUTPUT_RESYNC_RETRY_DELAY).await;
            let _ = inbox.send(ServerCommand::OutputResyncTick {
                session_id,
                client_id,
            });
        });
    }

    pub(super) fn spawn_durable_output_batch_timer(&self, session_id: String, generation: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(DURABLE_OUTPUT_BATCH_DELAY).await;
            let _ = inbox.send(ServerCommand::DurableOutputBatchTick {
                session_id,
                generation,
            });
        });
    }

    pub(super) fn cancel_shutdown_timer(&mut self) {
        self.shutdown_gen += 1;
    }

    pub(super) async fn handle_shutdown_tick(&mut self, generation: u64) {
        if generation == self.shutdown_gen && !self.disposed && !self.has_authenticated_clients() {
            self.dispose().await;
        }
    }
}

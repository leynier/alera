use chrono::{DateTime, Utc};
use tokio::task::JoinHandle;

use crate::terminal_host::history_store::{TerminalHostCheckpoint, TerminalHostHistoryStore};
use crate::terminal_host::host_error::{HostError, HostResult};

use super::Session;

impl Session {
    pub fn arm_checkpoint_retry_timer(&mut self, generation: u64) -> bool {
        if self.checkpoint_retry_timer.is_some() {
            return false;
        }
        self.checkpoint_retry_timer = Some(generation);
        true
    }

    pub fn consume_checkpoint_retry_timer(&mut self, generation: u64) -> bool {
        if self.checkpoint_retry_timer == Some(generation) {
            self.checkpoint_retry_timer = None;
            return true;
        }
        false
    }

    /// Arm a debounced checkpoint timer if one is not already pending. Returns
    /// the generation to fire the timer with, or `None` if already armed.
    pub fn arm_checkpoint(&mut self) -> Option<u64> {
        if self.checkpoint_armed {
            return None;
        }
        self.checkpoint_armed = true;
        Some(self.checkpoint_gen)
    }

    /// Whether a fired debounce timer is still current (not superseded by an
    /// immediate checkpoint). Consumes the armed state when true.
    pub fn checkpoint_due(&mut self, generation: u64) -> bool {
        if self.checkpoint_armed && self.checkpoint_gen == generation {
            self.checkpoint_armed = false;
            true
        } else {
            false
        }
    }

    /// Invalidate any pending debounce timer (used before an immediate write).
    pub fn invalidate_checkpoint(&mut self) {
        self.checkpoint_gen = self.checkpoint_gen.wrapping_add(1);
        self.checkpoint_armed = false;
    }

    pub fn rearm_checkpoint(&mut self) -> u64 {
        self.checkpoint_armed = true;
        self.checkpoint_gen
    }

    pub fn checkpoint_generation(&self) -> u64 {
        self.checkpoint_gen
    }

    pub fn checkpoint_job_active(&self) -> bool {
        self.checkpoint_job.is_some()
    }

    pub fn checkpoint_output_blocked(&self) -> bool {
        self.checkpoint_output_blocked
    }

    pub fn begin_checkpoint_job(&mut self, job: JoinHandle<Result<(), String>>) -> bool {
        if self.checkpoint_job.is_some() {
            return false;
        }
        self.checkpoint_output_blocked = true;
        self.checkpoint_job = Some(job);
        true
    }

    pub fn finish_checkpoint_job(&mut self, _success: bool) {
        // A completed worker no longer has a storage mutation in flight. On
        // failure, the caller rearms the checkpoint after first draining any
        // output accepted while the failed snapshot was running.
        self.checkpoint_output_blocked = false;
    }

    pub async fn poll_checkpoint_job(&mut self) -> Option<Result<(), String>> {
        let is_finished = self
            .checkpoint_job
            .as_ref()
            .is_some_and(JoinHandle::is_finished);
        if !is_finished {
            return None;
        }
        let job = self
            .checkpoint_job
            .take()
            .expect("finished checkpoint job remains owned by session");
        Some(match job.await {
            Ok(result) => result,
            Err(error) => Err(format!("checkpoint worker failed: {error}")),
        })
    }

    pub fn checkpoint_snapshot(&self) -> TerminalHostCheckpoint {
        TerminalHostCheckpoint {
            session_id: self.id.clone(),
            workspace_id: self.workspace_id.clone(),
            tab_id: self.tab_id.clone(),
            working_directory: self.working_directory.clone(),
            running: self.running,
            exit_code: self.exit_code,
            ended_at: self.ended_at,
            output_stream_bytes: self.output_stream_bytes,
            updated_at: Utc::now(),
            buffer: Vec::new(),
        }
    }

    /// Persist the current session state.
    pub async fn write_checkpoint(
        &mut self,
        store: &TerminalHostHistoryStore,
        ended_at_override: Option<DateTime<Utc>>,
    ) -> HostResult<()> {
        if let Some(ended_at) = ended_at_override {
            self.ended_at = Some(ended_at);
        }
        let checkpoint = self.checkpoint_snapshot();
        store
            .upsert(checkpoint)
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        if let Some(job) = self.checkpoint_job.take() {
            job.abort();
        }
    }
}

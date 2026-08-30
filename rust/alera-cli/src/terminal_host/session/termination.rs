use chrono::Utc;

use crate::terminal_host::history_store::TerminalHostHistoryStore;

#[cfg(unix)]
use super::shell_tree_termination::kill_shell_tree;
use super::Session;

impl Session {
    /// Terminate the session: kill the shell and everything it spawned, release
    /// the PTY, and either delete or finalize the checkpoint.
    pub async fn terminate(&mut self, remove_history: bool, store: &TerminalHostHistoryStore) {
        self.terminated = true;
        self.running = false;
        #[cfg(unix)]
        // Read before clearing. The sweep needs the sealed shell to prove which
        // tree it is allowed to signal, and it has to run before the root is
        // killed: a dead root's children reparent away and stop being findable.
        let shell = self.shell.take();
        #[cfg(windows)]
        {
            self.shell = None;
        }
        #[cfg(windows)]
        {
            // KILL_ON_JOB_CLOSE terminates the shell and every associated
            // descendant, including processes that detached from the console.
            self.process_job = None;
        }
        #[cfg(unix)]
        if let Some(mut killer) = self.killer.take() {
            kill_shell_tree(shell, move || {
                // The child may have already exited between checks.
                let _ = killer.kill();
            })
            .await;
        }
        #[cfg(windows)]
        if let Some(mut killer) = self.killer.take() {
            // The job normally killed the root already. Keep the PTY's direct
            // killer as a best-effort fallback if Windows raced job teardown.
            let _ = killer.kill();
        }
        self.input_tx = None;
        self.master = None;
        self.checkpoint_armed = false;
        self.output_batch.clear();
        self.output_batch_armed = false;
        self.output_batch_gen = self.output_batch_gen.wrapping_add(1);
        self.durable_output_batch.clear();
        self.durable_output_batch_armed = false;
        self.durable_output_batch_gen = self.durable_output_batch_gen.wrapping_add(1);
        if remove_history {
            if let Err(error) = store.delete(&self.id).await {
                tracing::warn!(
                    session_id = %self.id,
                    "failed to remove terminal history: {error}"
                );
            }
        } else {
            let ended = self.ended_at.unwrap_or_else(Utc::now);
            // A dropped final checkpoint is what the user sees as a terminal
            // that came back with its scrollback truncated.
            if let Err(error) = self.write_checkpoint(store, Some(ended)).await {
                tracing::warn!(
                    session_id = %self.id,
                    "failed to write the final terminal checkpoint: {error}"
                );
            }
        }
    }
}

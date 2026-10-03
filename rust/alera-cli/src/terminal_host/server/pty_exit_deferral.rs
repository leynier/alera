//! Handling a PTY exit only once the session's accepted output is stored.

use super::*;

impl ServerActor {
    /// The PTY reader no longer waits for history between chunks, so a child
    /// can exit while its last output is still being written. Removing the
    /// tab then fails its history barrier, and nothing would retry it: the
    /// exit is recorded but the tab stays. Handling the exit once history
    /// drains keeps recording it and removing the tab a single step.
    pub(super) async fn handle_pty_exit(&mut self, session_id: String, exit_code: i32) {
        self.flush_all_output(&session_id).await;
        if self.history_settled_for_exit(&session_id) {
            self.handle_session_exit(session_id, exit_code).await;
            return;
        }
        if let Some(session) = self.sessions.get_mut(&session_id) {
            session.defer_exit(exit_code);
        }
        self.schedule_history_retry(&session_id);
    }

    /// Runs an exit deferred by [`Self::handle_pty_exit`] once nothing it
    /// waits on is in flight. Called from every history completion path.
    pub(super) async fn run_deferred_exit_if_settled(&mut self, session_id: &str) {
        let waiting = self
            .sessions
            .get(session_id)
            .is_some_and(Session::has_deferred_exit);
        if !waiting || !self.history_settled_for_exit(session_id) {
            return;
        }
        let exit_code = self
            .sessions
            .get_mut(session_id)
            .and_then(Session::take_deferred_exit);
        if let Some(exit_code) = exit_code {
            self.handle_session_exit(session_id.to_string(), exit_code)
                .await;
        }
    }

    /// Nothing accepted is still being written. A failed store does not count
    /// as pending: the exit then takes the path it always took, which logs the
    /// failure and keeps the history, rather than waiting on storage forever.
    fn history_settled_for_exit(&mut self, session_id: &str) -> bool {
        self.collect_history_writer_completions(session_id);
        let writer_pending = self
            .history_writers
            .get(session_id)
            .is_some_and(|writer| !writer.failed() && writer.pending_len() > 0);
        let checkpoint_running = self
            .sessions
            .get(session_id)
            .is_some_and(Session::checkpoint_output_blocked);
        !writer_pending && !checkpoint_running
    }
}

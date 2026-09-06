use super::{control_file, BrowserBroker, ServerActor};

impl ServerActor {
    pub(super) async fn dispose(&mut self) {
        if self.disposed {
            return;
        }
        self.disposed = true;
        for tab_id in self.agent_title_jobs.keys().cloned().collect::<Vec<_>>() {
            self.cancel_agent_title_job(&tab_id);
        }
        self.cancel_shutdown_timer();
        self.codex = None;
        self.stop_remote_relay().await;
        if let Some(handle) = self.mobile_gateway.take() {
            handle.abort();
        }
        // Closing client handles ends their connection loops.
        self.browser = BrowserBroker::default();
        self.clients.clear();
        let store = self.store.clone();
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in session_ids {
            self.terminal_pulses.disarm(&session_id);
            self.cleanup_orchestration_for_closed_session(&session_id, "terminal host shut down")
                .await;
            self.flush_all_output(&session_id);
            self.await_output_writes(&session_id).await;
            if let Some(mut session) = self.sessions.remove(&session_id) {
                session.terminate(false, &store).await;
            }
        }
        control_file::delete_control_file(&self.control_file_path);
    }
}

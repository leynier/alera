use super::{control_file, ServerActor, ServerCommand};

impl ServerActor {
    pub(super) async fn dispose(&mut self) {
        if self.disposed {
            return;
        }
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in &session_ids {
            self.flush_all_output(session_id).await;
            if !self.await_output_writes(session_id).await {
                tracing::error!(
                    session_id,
                    "terminal host shutdown retained the session because terminal history is pending"
                );
                self.schedule_history_shutdown_retry();
                return;
            }
        }
        self.voice.stop_realtime();
        self.pull_request_watches = Default::default();
        for tab_id in self.agent_title_jobs.keys().cloned().collect::<Vec<_>>() {
            self.cancel_agent_title_job(&tab_id);
        }
        self.cancel_shutdown_timer();
        self.codex = None;
        self.host_links.disconnect_all().await;
        self.stop_remote_relay().await;
        if let Some(handle) = self.mobile_gateway.take() {
            handle.abort();
        }
        // Closing client handles ends their connection loops.
        self.clients.clear();
        let store = self.store.clone();
        for session_id in session_ids {
            self.terminal_pulses.disarm(&session_id);
            self.cleanup_orchestration_for_closed_session(&session_id, "terminal host shut down")
                .await;
            if let Some(mut session) = self.sessions.remove(&session_id) {
                session.terminate(false, &store).await;
            }
            self.settle_closed_workflow_terminal(
                &session_id,
                "The host shut down before task completion. Retry in a new attempt.",
            )
            .await;
        }
        self.disposed = true;
        control_file::delete_control_file(&self.control_file_path);
    }

    fn schedule_history_shutdown_retry(&self) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
            let _ = inbox.send(ServerCommand::RequestedShutdown);
        });
    }
}

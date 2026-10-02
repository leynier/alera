use super::{ServerActor, ServerCommand};
use std::time::Duration;

const MAX_PENDING_HISTORY_REQUESTS: usize = 32;

#[cfg(test)]
#[path = "history_request_retry_tests.rs"]
mod tests;

impl ServerActor {
    pub(super) fn defer_pending_history_error(
        &mut self,
        error: &crate::terminal_host::host_error::HostError,
        client_id: u64,
        request_id: i64,
        payload: &serde_json::Value,
        line: String,
    ) -> bool {
        if !matches!(error, crate::terminal_host::host_error::HostError::State(message) if message == "Terminal history could not be persisted; the session remains open for retry.")
        {
            return false;
        }
        let Some(session_id) = payload
            .get("sessionId")
            .or_else(|| payload.get("handle"))
            .and_then(serde_json::Value::as_str)
        else {
            return false;
        };
        self.defer_history_request(client_id, request_id, session_id.to_string(), line)
    }

    pub(super) fn defer_history_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        session_id: String,
        line: String,
    ) -> bool {
        let key = (client_id, request_id);
        if line.len() > super::server_command_inbox::SERVER_COMMAND_SMALL_LINE_BYTES {
            self.release_request_history_barrier(&session_id);
            return false;
        }
        if !self.pending_history_requests.contains_key(&key)
            && self.pending_history_requests.len() >= MAX_PENDING_HISTORY_REQUESTS
        {
            self.release_request_history_barrier(&session_id);
            return false;
        }
        self.pending_history_requests.insert(key, session_id);
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            let _ = inbox
                .send_wait(ServerCommand::HistoryRequestRetry {
                    client_id,
                    request_id,
                    line,
                })
                .await;
        });
        true
    }

    pub(super) async fn handle_history_request_retry(
        &mut self,
        client_id: u64,
        request_id: i64,
        line: String,
    ) {
        let Some(session_id) = self
            .pending_history_requests
            .remove(&(client_id, request_id))
        else {
            return;
        };
        if self.clients.contains_key(&client_id) {
            // Keep the second request-dispatch future off the actor's stack.
            // Inlining both dispatch paths doubles its large future layout.
            Box::pin(self.handle_line(client_id, line)).await;
        }
        self.release_request_history_barrier(&session_id);
    }

    pub(super) fn finish_history_request(&mut self, client_id: u64, request_id: i64) {
        if let Some(session_id) = self
            .pending_history_requests
            .remove(&(client_id, request_id))
        {
            self.release_request_history_barrier(&session_id);
        }
    }

    pub(super) fn release_payload_history_barrier(&mut self, payload: &serde_json::Value) {
        if let Some(session_id) = payload
            .get("sessionId")
            .or_else(|| payload.get("handle"))
            .and_then(serde_json::Value::as_str)
        {
            self.release_request_history_barrier(session_id);
        }
    }

    fn release_request_history_barrier(&mut self, session_id: &str) {
        if self
            .pending_history_requests
            .values()
            .any(|pending| pending == session_id)
        {
            return;
        }
        if let Some(session) = self.sessions.get_mut(session_id) {
            if session.termination_requested() {
                return;
            }
            session.release_history_barrier();
        }
        self.release_pty_ack_if_unblocked(session_id);
        if !self.sessions.contains_key(session_id) {
            self.inbox.resume_pty_session(session_id);
        }
    }
}

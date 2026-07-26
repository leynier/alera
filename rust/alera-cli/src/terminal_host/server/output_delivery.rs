//! Delivering PTY output to the clients attached to a session, and putting a
//! client that fell behind back in sync.
//!
//! A client falls behind two ways: it asked to be paused because its terminal
//! went off screen, or its bounded queue filled up and frames were dropped.
//! Both are served the same way, from the delivery cursor the host keeps per
//! client, so neither costs a replay of the whole scrollback.

use super::*;

impl ServerActor {
    pub(super) fn flush_output_batch(&mut self, session_id: &str) {
        let broadcast = self.sessions.get_mut(session_id).and_then(|session| {
            let batch = session.flush_output_batch()?;
            Some((batch.data, session.output_clients()))
        });
        if let Some((data, clients)) = broadcast {
            for client_id in clients {
                self.send_terminal_output(
                    session_id,
                    client_id,
                    ClientFrame::Output {
                        session_id: session_id.to_string(),
                        data: data.clone(),
                    },
                );
            }
        }
    }

    /// Returns whether the client's queue accepted the frame. Only an accepted
    /// frame advances that client's delivery cursor, so a drop stays visible to
    /// the next resume instead of being silently skipped.
    pub(super) fn send_terminal_output(
        &mut self,
        session_id: &str,
        client_id: u64,
        frame: ClientFrame,
    ) -> bool {
        let bytes = match &frame {
            ClientFrame::Output { data, .. } => data.len(),
            _ => 0,
        };
        let result = self
            .clients
            .get(&client_id)
            .map(|client| client.handle.terminal_out.try_send(frame));
        match result {
            Some(Ok(())) => {
                if let Some(session) = self.sessions.get_mut(session_id) {
                    session.advance_delivered_output_cursor(client_id, bytes);
                }
                return true;
            }
            Some(Err(TrySendError::Full(_))) => {
                let newly_backpressured = self
                    .sessions
                    .get_mut(session_id)
                    .is_some_and(|session| session.mark_output_backpressured(client_id));
                if newly_backpressured {
                    self.spawn_output_resync_timer(session_id.to_string(), client_id);
                }
            }
            Some(Err(TrySendError::Closed(_))) | None => {
                self.disconnect_client_soon(client_id);
            }
        }
        false
    }

    pub(super) fn set_output_paused_for_client(
        &mut self,
        session_id: &str,
        client_id: u64,
        paused: bool,
    ) -> Value {
        if !paused {
            return self.resume_output_for_client(session_id, client_id);
        }
        if let Some(session) = self.sessions.get_mut(session_id) {
            session.set_output_paused(client_id, true);
        }
        json!({})
    }

    /// Resumes delivery for one client and sends only what it missed.
    ///
    /// The missed bytes go out on the terminal lane ahead of the unpause, not
    /// in the request's reply: the reply travels on the control lane and the
    /// writer drains terminal frames first, so bytes returned inline can land
    /// after output that came later. On the terminal lane the order is the
    /// lane's, and the bytes reach the client's per-session decoder like any
    /// other output, so a code point split at the pause boundary still joins up.
    pub(super) fn resume_output_for_client(&mut self, session_id: &str, client_id: u64) -> Value {
        let missed = self.sessions.get(session_id).and_then(|session| {
            let (base_cursor, end_cursor) = session.output_stream_range();
            match session.delivered_output_cursor(client_id) {
                Some(cursor) if (base_cursor..=end_cursor).contains(&cursor) => {
                    Some(session.buffer.slice_from((cursor - base_cursor) as usize))
                }
                // No recorded cursor, or the ring already dropped the gap:
                // nothing short of a full snapshot can resynchronise this
                // client, and guessing would splice unrelated bytes together.
                _ => None,
            }
        });
        let Some(data) = missed else {
            return self.resend_output_snapshot(session_id, client_id);
        };
        let accepted = data.is_empty()
            || self.send_terminal_output(
                session_id,
                client_id,
                ClientFrame::Output {
                    session_id: session_id.to_string(),
                    data,
                },
            );
        if accepted {
            if let Some(session) = self.sessions.get_mut(session_id) {
                session.set_output_paused(client_id, false);
            }
        }
        // When it was not accepted the client stays paused and keeps its
        // cursor, and the resync timer the failed send armed asks it to retry.
        json!({ "delta": true, "resumed": accepted })
    }

    fn resend_output_snapshot(&mut self, session_id: &str, client_id: u64) -> Value {
        let Some(session) = self.sessions.get_mut(session_id) else {
            return json!({});
        };
        session.set_output_paused(client_id, false);
        let (_, end_cursor) = session.output_stream_range();
        session.set_delivered_output_cursor(client_id, end_cursor);
        let mut payload = session.snapshot_payload();
        payload["delta"] = json!(false);
        payload
    }

    pub(super) fn handle_output_resync_tick(&mut self, session_id: String, client_id: u64) {
        if !self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.output_resync_pending(client_id))
        {
            return;
        }
        let frame = event("outputResyncRequired", json!({ "sessionId": session_id }));
        let result = self
            .clients
            .get(&client_id)
            .map(|client| client.handle.terminal_out.try_send(frame.clone().into()));
        match result {
            Some(Ok(())) => {
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.mark_output_resync_sent(client_id);
                }
            }
            Some(Err(TrySendError::Full(_))) => {
                self.spawn_output_resync_timer(session_id, client_id);
            }
            Some(Err(TrySendError::Closed(_))) | None => {
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.mark_output_resync_sent(client_id);
                }
                self.disconnect_client_soon(client_id);
            }
        }
    }
}

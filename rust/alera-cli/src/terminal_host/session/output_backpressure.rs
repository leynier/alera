use super::Session;

impl Session {
    pub fn set_output_paused(&mut self, client_id: u64, paused: bool) {
        self.output_resync_pending_clients.remove(&client_id);
        if paused {
            self.output_paused_clients.insert(client_id);
        } else {
            self.output_paused_clients.remove(&client_id);
        }
    }

    pub fn mark_output_backpressured(&mut self, client_id: u64) -> bool {
        self.output_paused_clients.insert(client_id);
        self.output_resync_pending_clients.insert(client_id)
    }

    pub fn output_resync_pending(&self, client_id: u64) -> bool {
        self.output_resync_pending_clients.contains(&client_id)
    }

    pub fn mark_output_resync_sent(&mut self, client_id: u64) {
        self.output_resync_pending_clients.remove(&client_id);
    }

    /// How far this client has been served, or `None` when the host never
    /// recorded it and therefore cannot prove what it missed.
    pub fn delivered_output_cursor(&self, client_id: u64) -> Option<u64> {
        self.delivered_output_cursors.get(&client_id).copied()
    }

    pub fn set_delivered_output_cursor(&mut self, client_id: u64, cursor: u64) {
        self.delivered_output_cursors.insert(client_id, cursor);
    }

    /// Records bytes a client's queue accepted. Never call this for a frame
    /// that was dropped: the gap is exactly what a later resume has to resend.
    pub fn advance_delivered_output_cursor(&mut self, client_id: u64, bytes: usize) {
        if let Some(cursor) = self.delivered_output_cursors.get_mut(&client_id) {
            *cursor = cursor.saturating_add(bytes as u64);
        }
    }

    pub fn output_clients(&self) -> Vec<u64> {
        self.clients
            .iter()
            .copied()
            .filter(|client_id| !self.output_paused_clients.contains(client_id))
            .collect()
    }
}

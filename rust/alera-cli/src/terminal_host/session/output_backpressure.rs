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

    pub fn output_clients(&self) -> Vec<u64> {
        self.clients
            .iter()
            .copied()
            .filter(|client_id| !self.output_paused_clients.contains(client_id))
            .collect()
    }
}

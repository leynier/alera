use super::*;

impl ServerActor {
    pub(super) fn require_auth(&self, client_id: u64) -> HostResult<()> {
        match self.clients.get(&client_id) {
            Some(client) if client.authenticated => Ok(()),
            _ => Err(HostError::state(
                "Terminal host client is not authenticated.",
            )),
        }
    }

    pub(super) fn require_session(&self, payload: &Value) -> HostResult<String> {
        let session_id = match payload.get("sessionId") {
            Some(Value::String(value)) => value.clone(),
            _ => return Err(HostError::format("Terminal session id is required.")),
        };
        if !self.sessions.contains_key(&session_id) {
            return Err(HostError::state(format!(
                "Terminal session is not attached: {session_id}"
            )));
        }
        Ok(session_id)
    }

    pub(super) fn client_write(&self, client_id: u64, message: Value) {
        if let Some(client) = self.clients.get(&client_id) {
            if client.handle.out.try_send(message).is_err() {
                self.disconnect_client_soon(client_id);
            }
        }
    }

    pub(super) fn broadcast(&self, client_ids: &[u64], message: Value) {
        for id in client_ids {
            if let Some(client) = self.clients.get(id) {
                if client.handle.out.try_send(message.clone()).is_err() {
                    self.disconnect_client_soon(*id);
                }
            }
        }
    }

    pub(super) fn broadcast_authenticated(&self, message: Value) {
        for (client_id, client) in &self.clients {
            if client.authenticated && client.handle.out.try_send(message.clone()).is_err() {
                self.disconnect_client_soon(*client_id);
            }
        }
    }

    pub(super) fn disconnect_client_soon(&self, client_id: u64) {
        let _ = self
            .inbox
            .send(ServerCommand::ClientDisconnected { id: client_id });
    }
}

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
            if client.handle.control_out.send(message).is_err() {
                self.disconnect_client_soon(client_id);
            }
        }
    }

    pub(super) fn broadcast(&self, client_ids: &[u64], message: Value) {
        for id in client_ids {
            if let Some(client) = self.clients.get(id) {
                if client.handle.control_out.send(message.clone()).is_err() {
                    self.disconnect_client_soon(*id);
                }
            }
        }
    }

    pub(super) fn broadcast_authenticated(&self, message: Value) {
        for (client_id, client) in &self.clients {
            if client.authenticated && client.handle.control_out.send(message.clone()).is_err() {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn control_bursts_survive_a_saturated_terminal_queue() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let (inbox, mut inbox_rx) = mpsc::unbounded_channel();
        let (control_out, mut control_out_rx) = mpsc::unbounded_channel();
        let (terminal_out, _terminal_out_rx) = mpsc::channel(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        for index in 0..CLIENT_TERMINAL_OUT_QUEUE_CAPACITY {
            terminal_out.try_send(json!({"terminal": index})).unwrap();
        }
        let actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            clients: HashMap::from([(
                1,
                ClientState {
                    handle: ClientHandle {
                        control_out,
                        terminal_out,
                    },
                    authenticated: true,
                    kind: ClientKind::Local,
                    mobile_device_id: None,
                    mobile_device_name: None,
                },
            )]),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            inbox,
            next_client_id: Arc::new(AtomicU64::new(2)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };

        for index in 0..(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY * 2) {
            actor.client_write(1, json!({"response": index}));
            actor.broadcast_authenticated(json!({"event": index}));
        }

        let mut received = Vec::new();
        while let Ok(message) = control_out_rx.try_recv() {
            received.push(message);
        }
        assert_eq!(received.len(), CLIENT_TERMINAL_OUT_QUEUE_CAPACITY * 4);
        assert!(inbox_rx.try_recv().is_err());
        assert!(actor.clients.contains_key(&1));
    }
}

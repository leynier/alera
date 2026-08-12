use super::*;
use crate::terminal_host::protocol::{CODEX_TAB_KIND, MOBILE_EMULATOR_TAB_KIND, PROTOCOL_VERSION};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum LocalClientRole {
    App,
    Cli,
}

impl ServerActor {
    pub(super) fn require_auth(&self, client_id: u64) -> HostResult<()> {
        match self.clients.get(&client_id) {
            Some(client) if client.authenticated => Ok(()),
            _ => Err(HostError::state(
                "Terminal host client is not authenticated.",
            )),
        }
    }

    pub(super) fn require_authenticated_local_request(
        &self,
        client_id: u64,
        request_type: &str,
    ) -> HostResult<()> {
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)
    }

    pub(super) fn require_session_id(&self, payload: &Value) -> HostResult<String> {
        let session_id = match payload.get("sessionId") {
            Some(Value::String(value)) => value.clone(),
            _ => return Err(HostError::format("Terminal session id is required.")),
        };
        Ok(session_id)
    }

    pub(super) fn require_session(&self, payload: &Value) -> HostResult<String> {
        let session_id = self.require_session_id(payload)?;
        if !self.sessions.contains_key(&session_id) {
            return Err(HostError::state(format!(
                "Terminal session is not attached: {session_id}"
            )));
        }
        Ok(session_id)
    }

    /// Authenticates a client and negotiates the wire format for it.
    pub(super) fn handle_hello(&mut self, client_id: u64, payload: &Value) -> HostResult<Value> {
        let version_ok = payload.get("protocolVersion") == Some(&json!(PROTOCOL_VERSION));
        let token_ok = payload.get("token").and_then(Value::as_str) == Some(self.token.as_str());
        if !version_ok || !token_ok {
            return Err(HostError::state("Terminal host authentication failed."));
        }
        let binary_frames = payload
            .get("binaryFrames")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let local_role = requested_local_role(payload);
        let supports_mobile_emulator_tab_kind = payload
            .get("supportedTabKinds")
            .and_then(Value::as_array)
            .is_some_and(|kinds| {
                kinds
                    .iter()
                    .any(|kind| kind.as_str() == Some(MOBILE_EMULATOR_TAB_KIND))
            });
        let supports_codex_tab_kind = payload
            .get("supportedTabKinds")
            .and_then(Value::as_array)
            .is_some_and(|kinds| {
                kinds
                    .iter()
                    .any(|kind| kind.as_str() == Some(CODEX_TAB_KIND))
            });
        if let Some(client) = self.clients.get_mut(&client_id) {
            client.authenticated = true;
            client.binary_frames = binary_frames;
            client.supports_mobile_emulator_tab_kind = supports_mobile_emulator_tab_kind;
            client.supports_codex_tab_kind = supports_codex_tab_kind;
            if client.kind == ClientKind::Local {
                client.local_role = local_role;
            }
        }
        self.cancel_shutdown_timer();
        if binary_frames {
            // Queued after this response on the same lane, so the writer emits
            // the response as a line and only then switches. A shared flag
            // could flip first and frame the response the client is still
            // reading as a line.
            self.upgrade_client_to_binary(client_id);
        }
        Ok(json!({
            "binaryFrames": binary_frames,
            "clientKind": match local_role {
                LocalClientRole::App => "app",
                LocalClientRole::Cli => "cli",
            }
        }))
    }

    /// Queues the in-band switch to binary frames for one client.
    pub(super) fn upgrade_client_to_binary(&self, client_id: u64) {
        if let Some(client) = self.clients.get(&client_id) {
            if client
                .handle
                .send_control(ClientFrame::UpgradeToBinary)
                .is_err()
            {
                self.disconnect_client_soon(client_id);
            }
        }
    }

    pub(super) fn client_write(&self, client_id: u64, message: Value) {
        self.try_client_write(client_id, message);
    }

    pub(super) fn try_client_write(&self, client_id: u64, message: Value) -> bool {
        if let Some(client) = self.clients.get(&client_id) {
            if client.handle.send_control(message.into()).is_err() {
                self.disconnect_client_soon(client_id);
                return false;
            }
            return true;
        }
        false
    }

    pub(super) fn restart_runtime_after_client_write(&self, client_id: u64) {
        if let Some(client) = self.clients.get(&client_id) {
            if client
                .handle
                .send_control(ClientFrame::RestartRuntimeAfterWrite {
                    inbox: self.inbox.clone(),
                })
                .is_err()
            {
                self.disconnect_client_soon(client_id);
            }
        }
    }

    pub(super) fn shutdown_runtime_after_client_write(&self, client_id: u64) {
        if let Some(client) = self.clients.get(&client_id) {
            if client
                .handle
                .send_control(ClientFrame::ShutdownRuntimeAfterWrite {
                    inbox: self.inbox.clone(),
                })
                .is_err()
            {
                self.disconnect_client_soon(client_id);
            }
        }
    }

    pub(super) fn broadcast(&self, client_ids: &[u64], message: Value) {
        for id in client_ids {
            if let Some(client) = self.clients.get(id) {
                if client.handle.send_control(message.clone().into()).is_err() {
                    self.disconnect_client_soon(*id);
                }
            }
        }
    }

    pub(super) fn broadcast_authenticated(&self, message: Value) {
        for (client_id, client) in &self.clients {
            if client.authenticated && client.handle.send_control(message.clone().into()).is_err() {
                self.disconnect_client_soon(*client_id);
            }
        }
    }

    pub(super) fn broadcast_authenticated_mobile(&self, message: Value) {
        for (client_id, client) in &self.clients {
            if client.authenticated
                && client.kind == ClientKind::Mobile
                && client.handle.send_control(message.clone().into()).is_err()
            {
                self.disconnect_client_soon(*client_id);
            }
        }
    }

    pub(super) fn disconnect_client_soon(&self, client_id: u64) {
        let _ = self
            .inbox
            .send(ServerCommand::ClientDisconnected { id: client_id });
    }

    pub(super) async fn dispose_client(&mut self, client_id: u64) {
        let Some(client) = self.clients.get(&client_id) else {
            return;
        };
        let release_emulator = client.authenticated && matches!(client.kind, ClientKind::Local);
        self.orchestration_waiters.remove_client(client_id);
        self.handle_browser_client_disconnect(client_id);
        self.cancel_queued_emulator_requests(client_id);
        self.release_mobile_driver_for_client(client_id);
        self.cancel_mobile_prompt_file_uploads(client_id);
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in session_ids {
            self.flush_all_output(&session_id);
            if let Some(session) = self.sessions.get_mut(&session_id) {
                session.detach(client_id);
            }
            self.immediate_checkpoint(&session_id).await;
        }
        self.clients.remove(&client_id);
        if release_emulator {
            self.queue_emulator_client_release(client_id, !self.has_authenticated_clients());
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn dispose_mobile_clients(&mut self) {
        let client_ids = self
            .clients
            .iter()
            .filter_map(|(id, client)| (client.kind == ClientKind::Mobile).then_some(*id))
            .collect::<Vec<_>>();
        for client_id in client_ids {
            self.dispose_client(client_id).await;
        }
    }

    pub(super) async fn dispose_mobile_clients_for_device(&mut self, device_id: &str) {
        let client_ids = self
            .clients
            .iter()
            .filter_map(|(id, client)| {
                (client.kind == ClientKind::Mobile
                    && client.mobile_device_id.as_deref() == Some(device_id))
                .then_some(*id)
            })
            .collect::<Vec<_>>();
        for client_id in client_ids {
            self.dispose_client(client_id).await;
        }
    }
}

fn requested_local_role(payload: &Value) -> LocalClientRole {
    match payload.get("clientKind").and_then(Value::as_str) {
        Some("app") => LocalClientRole::App,
        _ => LocalClientRole::Cli,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_roles_are_additive_and_absent_means_cli() {
        assert_eq!(requested_local_role(&json!({})), LocalClientRole::Cli);
        assert_eq!(
            requested_local_role(&json!({"clientKind": "cli"})),
            LocalClientRole::Cli
        );
        assert_eq!(
            requested_local_role(&json!({"clientKind": "app"})),
            LocalClientRole::App
        );
        assert_eq!(
            requested_local_role(&json!({"clientKind": "legacy"})),
            LocalClientRole::Cli
        );
    }

    #[tokio::test]
    async fn control_bursts_survive_a_saturated_terminal_queue() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let account_push = super::account_push_state::AccountPushState::new(
            dir.path().to_path_buf(),
            runtime_store.clone(),
        )
        .await
        .unwrap();
        let (inbox, mut inbox_rx) = mpsc::unbounded_channel();
        let (control_out, mut control_out_rx) = mpsc::unbounded_channel();
        let (terminal_out, _terminal_out_rx) =
            mpsc::channel::<ClientFrame>(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        for index in 0..CLIENT_TERMINAL_OUT_QUEUE_CAPACITY {
            terminal_out
                .try_send(json!({"terminal": index}).into())
                .unwrap();
        }
        let actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            automation_wake: Arc::new(Notify::new()),
            automations_active: false,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            emulator_requests: Default::default(),
            agent_quota_cache: None,
            account_push,
            clients: HashMap::from([(
                1,
                ClientState {
                    handle: ClientHandle::new(control_out, terminal_out),
                    authenticated: true,
                    binary_frames: false,
                    supports_mobile_emulator_tab_kind: false,
                    supports_codex_tab_kind: false,
                    kind: ClientKind::Local,
                    local_role: LocalClientRole::Cli,
                    mobile_device_id: None,
                    mobile_device_name: None,
                    cloud_device_id: None,
                },
            )]),
            mobile_prompt_file_uploads: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            resources: ResourceMonitorState::default(),
            browser: BrowserBroker::default(),
            emulators: None,
            codex: None,
            codex_presence: HashMap::new(),
            codex_presence_scheduled: false,
            codex_pending_messages: HashMap::new(),
            codex_flush_scheduled: HashSet::new(),
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

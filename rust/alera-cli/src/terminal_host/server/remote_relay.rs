use chrono::Utc;
use serde_json::json;
use tokio::sync::oneshot;

use crate::terminal_host::client::ClientHandle;

use crate::terminal_host::protocol::event;
use crate::terminal_host::relay_runtime;

use super::{client_delivery, ClientKind, ClientState, ServerActor, ServerCommand};

impl ServerActor {
    pub(super) async fn handle_relay_command(&mut self, command: ServerCommand) {
        match command {
            ServerCommand::RelayActivity { generation, at } => {
                if generation == self.account_push.relay_generation {
                    self.account_push.relay_status["lastActivityAt"] = json!(at);
                }
            }
            ServerCommand::RelayStatus {
                generation,
                payload,
            } => {
                if generation == self.account_push.relay_generation {
                    self.account_push.relay_status = payload.clone();
                    self.broadcast_authenticated(event("mobileRelayChanged", payload));
                }
            }
            ServerCommand::RelayClientConnected {
                id,
                handle,
                client_id,
            } => {
                self.connect_relay_client(id, handle, client_id);
            }
            ServerCommand::RelayClientLine {
                id,
                line,
                accepted,
                expires_at,
            } => {
                self.handle_relay_line(id, line, accepted, expires_at).await;
            }
            _ => unreachable!("only relay commands are dispatched here"),
        }
    }

    pub(super) fn connect_relay_client(
        &mut self,
        id: u64,
        handle: ClientHandle,
        client_id: String,
    ) {
        self.account_push
            .relay_presence
            .insert(id, (Utc::now(), Utc::now()));
        self.clients.insert(
            id,
            ClientState {
                handle,
                authenticated: false,
                binary_frames: false,
                kind: ClientKind::Mobile,
                local_role: client_delivery::LocalClientRole::Cli,
                mobile_device_id: None,
                mobile_device_name: Some("Remote Mobile".to_string()),
                cloud_device_id: Some(client_id.clone()),
                relay_client_id: Some(client_id),
            },
        );
    }

    pub(super) async fn handle_relay_line(
        &mut self,
        id: u64,
        line: String,
        accepted: oneshot::Sender<()>,
        expires_at: i64,
    ) {
        if let Some((_, activity)) = self.account_push.relay_presence.get_mut(&id) {
            *activity = Utc::now();
        }
        if expires_at > Utc::now().timestamp() {
            self.handle_line(id, line).await;
        }
        let _ = accepted.send(());
    }

    pub(super) async fn restart_remote_relay(&mut self) {
        self.stop_remote_relay().await;
        let settings = match self.runtime_store.mobile_access_settings().await {
            Ok(settings) => settings,
            Err(error) => {
                tracing::warn!("could not read remote mobile access settings: {error}");
                return;
            }
        };
        if !settings.remote_access_enabled {
            return;
        }
        match self.account_push.service.local_account().await {
            Ok(Some(_)) => {}
            Ok(None) => return,
            Err(error) => {
                tracing::warn!("could not read the local account for remote relay: {error}");
                return;
            }
        }
        let (task, stop) = relay_runtime::spawn(
            self.account_push.service.clone(),
            self.account_push.service.runtime_id().to_owned(),
            self.inbox.clone(),
            self.next_client_id.clone(),
            self.account_push.relay_generation,
        );
        self.account_push.relay_task = Some(task);
        self.account_push.relay_stop = Some(stop);
        self.cancel_shutdown_timer();
        self.broadcast_authenticated(event("mobileRelayChanged", json!({ "enabled": true })));
    }

    pub(super) async fn stop_remote_relay(&mut self) {
        self.account_push.relay_generation += 1;
        self.account_push.relay_status = json!({ "state": "disabled" });
        self.account_push.relay_presence.clear();
        if let Some(stop) = self.account_push.relay_stop.take() {
            let _ = stop.send(());
        }
        if let Some(task) = self.account_push.relay_task.take() {
            task.abort();
            let _ = task.await;
        }
        self.dispose_relay_clients().await;
        self.broadcast_authenticated(event("mobileRelayChanged", json!({ "enabled": false })));
    }

    async fn dispose_relay_clients(&mut self) {
        let client_ids = self
            .clients
            .iter()
            .filter_map(|(id, client)| client.relay_client_id.as_ref().map(|_| *id))
            .collect::<Vec<_>>();
        for client_id in client_ids {
            self.dispose_client(client_id).await;
        }
    }
}

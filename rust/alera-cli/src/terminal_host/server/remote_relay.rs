use serde_json::json;

use crate::terminal_host::protocol::event;
use crate::terminal_host::relay_runtime;

use super::ServerActor;

impl ServerActor {
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
        );
        self.account_push.relay_task = Some(task);
        self.account_push.relay_stop = Some(stop);
        self.cancel_shutdown_timer();
        self.broadcast_authenticated(event("mobileRelayChanged", json!({ "enabled": true })));
    }

    pub(super) async fn stop_remote_relay(&mut self) {
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

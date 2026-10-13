use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use alera_core::runtime::{chat_orchestration_request_digest, AgentChatRecord, RuntimeStore};
use async_trait::async_trait;
use serde_json::{json, Value};
use tokio::sync::Mutex;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_remote::{RemoteChatTransport, INTERNAL_CHAT_REQUEST};
use crate::terminal_host::server::agent_chat_runtime::events::NullSink;
use crate::terminal_host::server::agent_chat_runtime::{AgentChatRuntime, InstanceDirectory};
use crate::terminal_host::server::chat_orchestration_remote::handle_internal_runtime;

use super::mock_provider::MockProviderFactory;
use super::ChatCredentialLaunchHook;

#[derive(Clone)]
struct Satellite {
    store: RuntimeStore,
    runtime: AgentChatRuntime,
}

pub(super) struct SatelliteTransport {
    hub_store: RuntimeStore,
    directory: PathBuf,
    factory: Arc<MockProviderFactory>,
    satellites: Mutex<HashMap<String, Satellite>>,
}

impl SatelliteTransport {
    pub fn new(
        hub_store: RuntimeStore,
        directory: PathBuf,
        factory: Arc<MockProviderFactory>,
    ) -> Arc<Self> {
        Arc::new(Self {
            hub_store,
            directory,
            factory,
            satellites: Mutex::new(HashMap::new()),
        })
    }

    async fn satellite(&self, workspace_id: &str) -> HostResult<Satellite> {
        let mut workspace = self
            .hub_store
            .find_workspace(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("Unknown fixture workspace."))?;
        assert_ne!(workspace.host_id, "local");
        let host_id = workspace.host_id.clone();
        let mut satellites = self.satellites.lock().await;
        let satellite = if let Some(satellite) = satellites.get(&host_id) {
            satellite.clone()
        } else {
            let key =
                chat_orchestration_request_digest("test-satellite", &json!({"hostId": host_id}));
            let path = self.directory.join(format!("satellite-{key}"));
            let store = RuntimeStore::open(&path).await.unwrap();
            let runtime = AgentChatRuntime::new(
                store.clone(),
                self.factory.clone(),
                Arc::new(store.clone()),
                Box::new(NullSink),
                Arc::new(InstanceDirectory::default()),
            )
            .with_flush_delay(Duration::ZERO);
            runtime
                .register_launch_hook(ChatCredentialLaunchHook::new(store.clone(), path).unwrap());
            let satellite = Satellite { store, runtime };
            satellites.insert(host_id, satellite.clone());
            satellite
        };
        drop(satellites);
        let project = self
            .hub_store
            .find_project(&workspace.project_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .unwrap();
        satellite
            .store
            .upsert_project(project)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        workspace.host_id = "local".into();
        satellite
            .store
            .upsert_workspace(workspace)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(satellite)
    }

    pub async fn record(&self, workspace_id: &str, chat_id: &str) -> AgentChatRecord {
        self.satellite(workspace_id)
            .await
            .unwrap()
            .store
            .agent_chat(chat_id)
            .await
            .unwrap()
            .unwrap()
    }

    pub async fn shutdown(&self) {
        let satellites: Vec<_> = self.satellites.lock().await.values().cloned().collect();
        for satellite in satellites {
            satellite.runtime.shutdown().await;
            satellite.store.pool().close().await;
        }
    }
}

#[async_trait]
impl RemoteChatTransport for SatelliteTransport {
    async fn request(&self, workspace_id: &str, verb: &str, payload: Value) -> HostResult<Value> {
        let satellite = self.satellite(workspace_id).await?;
        match verb {
            INTERNAL_CHAT_REQUEST => handle_internal_runtime(&satellite.runtime, &payload).await,
            "tab.list" => Ok(serde_json::to_value(
                satellite
                    .store
                    .list_workspace_tabs(workspace_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?,
            )
            .unwrap()),
            "agentChat.providers" => satellite.runtime.providers(Some(workspace_id), false).await,
            other => Err(HostError::format(format!(
                "Unsupported satellite fixture verb {other}."
            ))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::server::chat_orchestration::test_support::add_workspace;

    async fn transport() -> (tempfile::TempDir, RuntimeStore, Arc<SatelliteTransport>) {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        add_workspace(&store, "remote", "project", "ssh-test").await;
        let transport = SatelliteTransport::new(
            store.clone(),
            directory.path().to_owned(),
            Arc::new(MockProviderFactory::default()),
        );
        (directory, store, transport)
    }

    #[tokio::test]
    async fn closed_satellite_pool_returns_a_transport_error_instead_of_panicking() {
        let (_directory, store, transport) = transport().await;
        assert_eq!(
            transport
                .request("remote", "tab.list", json!({}))
                .await
                .unwrap(),
            json!([]),
        );
        transport.shutdown().await;
        let error = transport
            .request("remote", "tab.list", json!({}))
            .await
            .unwrap_err();
        assert!(matches!(&error, HostError::State(_)), "{error:?}");
        assert!(error.wire_message().contains("closed pool"));
        store.pool().close().await;
    }

    #[tokio::test]
    async fn closed_hub_pool_returns_a_transport_error_instead_of_panicking() {
        let (_directory, store, transport) = transport().await;
        assert_eq!(
            transport
                .request("remote", "tab.list", json!({}))
                .await
                .unwrap(),
            json!([]),
        );
        transport.shutdown().await;
        store.pool().close().await;
        let error = transport
            .request("remote", "tab.list", json!({}))
            .await
            .unwrap_err();
        assert!(matches!(&error, HostError::State(_)), "{error:?}");
        assert!(error.wire_message().contains("closed pool"));
    }

    #[tokio::test]
    async fn missing_workspace_still_returns_the_original_fixture_error() {
        let (_directory, store, transport) = transport().await;
        let error = transport
            .request("missing", "tab.list", json!({}))
            .await
            .unwrap_err();
        assert_eq!(error.wire_message(), "Unknown fixture workspace.");
        transport.shutdown().await;
        store.pool().close().await;
    }
}

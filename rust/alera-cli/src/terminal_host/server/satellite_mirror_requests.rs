//! `hub.mirror.*` verbs: what a hub sends a satellite over the host link so
//! the satellite knows the workspaces it runs work for.
//!
//! The payload is the same `{project, workspace, repositoryPath?}` document
//! the legacy `alera project owner-terminal --metadata-base64` command carried,
//! so the identity rules in `remote_workspace_owner::register` apply unchanged:
//! the satellite adopts the hub's project, workspace and instance ids, points
//! the project at its local checkout and refuses to replace a record whose
//! identity differs. The verb is idempotent.

use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

impl ServerActor {
    pub(super) fn try_start_satellite_mirror_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !request_type.starts_with("hub.mirror.") {
            return Ok(false);
        }
        self.require_authenticated_local_request(client_id, request_type)?;
        match request_type {
            "hub.mirror.workspace" => {
                let registration = serde_json::from_value::<
                    crate::remote_workspace_owner::RemoteWorkspaceOwnerRegistration,
                >(payload.clone())
                .map_err(|error| {
                    HostError::format(format!("Invalid workspace mirror payload: {error}"))
                })?;
                let store = self.runtime_store.clone();
                self.spawn_deferred_request(client_id, request_id, async move {
                    let workspace = crate::remote_workspace_owner::register(&store, registration)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    serde_json::to_value(workspace)
                        .map_err(|error| HostError::state(error.to_string()))
                });
                Ok(true)
            }
            _ => Err(HostError::state(format!(
                "Unknown terminal host request: {request_type}"
            ))),
        }
    }

    /// Answers a request from a spawned task through
    /// [`super::ServerCommand::HostLinkRequestFinished`], which writes the
    /// response to the client once the future settles.
    pub(super) fn spawn_deferred_request<F>(&self, client_id: u64, request_id: i64, task: F)
    where
        F: std::future::Future<Output = HostResult<Value>> + Send + 'static,
    {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = task.await;
            let _ = inbox.send(super::ServerCommand::HostLinkRequestFinished {
                client_id,
                request_id,
                result,
            });
        });
    }
}

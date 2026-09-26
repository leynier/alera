use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::protocol::{error_response, ok_response};
use serde_json::Value;

impl ServerActor {
    pub(super) fn start_project_checkout_registration(
        &mut self,
        client_id: u64,
        request_id: i64,
        request: crate::remote_project_checkout::RegisterProjectCheckoutRequest,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = super::requests::json_result(
                crate::remote_project_checkout::register(
                    &store,
                    request,
                    &crate::ssh_remote::LiveSshRemoteHost,
                )
                .await,
            );
            let _ = inbox.send(ServerCommand::ProjectCheckoutRegistered {
                client_id,
                request_id,
                result,
            });
        });
    }

    /// A project that lives only on another host. The same job accounting and
    /// finish path as a checkout registration: both may clone, and both end by
    /// announcing that the project list changed.
    pub(super) fn start_remote_project_registration(
        &mut self,
        client_id: u64,
        request_id: i64,
        request: crate::remote_project_checkout::RegisterRemoteProjectRequest,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = crate::remote_project_checkout::register_remote_project(
                &store,
                request,
                &crate::ssh_remote::LiveSshRemoteHost,
            )
            .await
            .map_err(|error| crate::terminal_host::host_error::HostError::state(error.to_string()));
            let _ = inbox.send(ServerCommand::ProjectCheckoutRegistered {
                client_id,
                request_id,
                result,
            });
        });
    }

    pub(super) fn handle_project_checkout_registered(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        match result {
            Ok(value) => {
                self.broadcast_project_state_changed();
                self.client_write(client_id, ok_response(request_id, value));
            }
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
        self.schedule_shutdown_if_idle();
    }
}

pub(super) async fn list_project_branches(
    store: &alera_core::runtime::RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let project_id = super::requests::require_string_key(payload, "projectId")?;
    let host_id = super::requests::optional_string_key(payload, "hostId");
    let host_id = crate::ssh_remote::normalized_host_id(host_id.as_deref());
    crate::project_branch_catalog::list(
        store,
        &project_id,
        &host_id,
        &crate::ssh_remote::LiveSshRemoteHost,
    )
    .await
    .map_err(|error| crate::terminal_host::host_error::HostError::state(error.to_string()))
}

pub(super) async fn list_checkout_catalog(
    store: &alera_core::runtime::RuntimeStore,
    project_id: &str,
) -> HostResult<Value> {
    let checkouts = store
        .list_project_checkouts(project_id)
        .await
        .map_err(|error| crate::terminal_host::host_error::HostError::state(error.to_string()))?;
    let mut result = Vec::with_capacity(checkouts.len());
    for checkout in checkouts {
        let target = store
            .find_ssh_target(&checkout.host_id)
            .await
            .map_err(|error| {
                crate::terminal_host::host_error::HostError::state(error.to_string())
            })?;
        let mut value = serde_json::to_value(&checkout).map_err(|error| {
            crate::terminal_host::host_error::HostError::state(error.to_string())
        })?;
        if let Some(target) = target {
            value["hostName"] = Value::String(target.alias);
        }
        result.push(value);
    }
    Ok(Value::Array(result))
}

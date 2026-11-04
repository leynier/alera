//! Opaque setup requests from a human desktop, executed by the selected owner.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde_json::{json, Value};

use super::agent_chat_provider_settings::setup::{ProviderSetupContext, SETUP_WORKSPACE_ID};
use super::requests::require_string_key;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{event, ok_response};

pub(crate) const INTERNAL_SETUP_REQUEST: &str = "hub.providerSetup";
pub(crate) const REMOTE_SETUP_CAPABILITY: &str = "agentChatRemoteProviderSetupV1";
pub(crate) const SETUP_SESSION_PREFIX: &str = "__alera_provider_setup__:";
const FORCE_CLOSE_OPERATION: &str = "closeRemovedHost";

#[path = "remote_provider_setup_cleanup.rs"]
mod cleanup;
#[path = "remote_provider_setup_routes.rs"]
mod routes;
pub(crate) use cleanup::{close_removed_host_setups, forward_setup_request};
pub(crate) use routes::{RemoteSetupSessions, SetupCleanup};

#[cfg(all(test, unix))]
#[path = "remote_provider_setup_lifecycle_tests.rs"]
mod lifecycle_tests;
#[cfg(test)]
#[path = "remote_provider_setup_tests.rs"]
mod tests;

fn setup_operation_allowed(operation: &str) -> bool {
    matches!(
        operation,
        "createOrAttach"
            | "terminal.restart"
            | "write"
            | "resize"
            | "setOutputPaused"
            | "detach"
            | "terminate"
            | "terminal.reclaim"
            | "terminal.pulse.status"
    )
}

fn not_allowed() -> HostError {
    HostError::conflict(
        "notAllowed",
        "Provider setup requires an authenticated desktop and its exact setup terminal.",
        json!({}),
    )
}

impl ServerActor {
    pub(super) fn forwarded_provider_setup_payload(
        &self,
        host_id: &str,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_provider_setup_client(client_id)?;
        // A reverse channel must never borrow the hub desktop's authority.
        if self.is_hub_link_client(client_id) {
            return Err(not_allowed());
        }
        let lease_id = self
            .host_links
            .provider_setup_sessions
            .admit(host_id, client_id, payload)?;
        Ok(json!({
            "type": payload["type"],
            "providerSetup": payload["providerSetup"],
            "payload": payload["payload"],
            "desktopClientId": client_id,
            "desktopLeaseId": lease_id,
        }))
    }

    pub(super) async fn try_handle_remote_provider_setup(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        envelope: &Value,
    ) -> HostResult<bool> {
        if request_type != INTERNAL_SETUP_REQUEST {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        if !self.is_hub_link_client(client_id)
            || self.chat_orchestration_binding(client_id).is_some()
            || envelope["desktopClientId"]
                .as_u64()
                .is_none_or(|id| id == 0)
        {
            return Err(not_allowed());
        }
        let operation = require_string_key(envelope, "type")?;
        let force_close = operation == FORCE_CLOSE_OPERATION;
        if !setup_operation_allowed(&operation) && !force_close {
            return Err(not_allowed());
        }
        let desktop_id = envelope["desktopClientId"]
            .as_u64()
            .expect("checked desktop identity");
        let lease_id = require_string_key(envelope, "desktopLeaseId")?;
        if uuid::Uuid::parse_str(&lease_id).is_err() {
            return Err(not_allowed());
        }
        let selection = ProviderSetupContext::from_json(&envelope["providerSetup"])?;
        let mut payload = envelope["payload"].clone();
        let session_id = require_string_key(&payload, "sessionId")?;
        if !session_id.starts_with(SETUP_SESSION_PREFIX) {
            return Err(not_allowed());
        }
        if self.sessions.get(&session_id).is_some_and(|session| {
            session.workspace_id != SETUP_WORKSPACE_ID
                || session.provider_setup.as_ref() != Some(&selection)
        }) {
            return Err(not_allowed());
        }
        if operation != "createOrAttach"
            && !matches!(operation.as_str(), "terminate" | "detach")
            && !force_close
            && !self.sessions.contains_key(&session_id)
        {
            return Err(HostError::state(format!(
                "Terminal session is not attached: {session_id}"
            )));
        }
        let prior_leases = self
            .sessions
            .get(&session_id)
            .map(|session| session.provider_setup_desktop_leases.clone())
            .unwrap_or_default();
        if matches!(operation.as_str(), "terminate" | "detach") || force_close {
            if let Some(session) = self.sessions.get_mut(&session_id) {
                if force_close {
                    session.provider_setup_desktop_leases.clear();
                } else if session.provider_setup_desktop_leases.get(&lease_id) == Some(&desktop_id)
                {
                    session.provider_setup_desktop_leases.remove(&lease_id);
                } else {
                    self.client_write(client_id, ok_response(request_id, json!({})));
                    return Ok(true);
                }
                if session.provider_setup_desktop_leases.is_empty() {
                    if let Err(error) = self.terminate_session_request(session_id.clone()).await {
                        if let Some(session) = self.sessions.get_mut(&session_id) {
                            session.provider_setup_desktop_leases = prior_leases;
                        }
                        return Err(error);
                    }
                }
            }
            self.client_write(client_id, ok_response(request_id, json!({})));
            return Ok(true);
        }
        if operation != "createOrAttach" && prior_leases.get(&lease_id) != Some(&desktop_id) {
            return Err(not_allowed());
        }
        if matches!(operation.as_str(), "createOrAttach" | "terminal.restart") {
            if payload["workspaceId"] != SETUP_WORKSPACE_ID
                || payload["launch"]["providerSetup"] != json!(selection)
                || payload["attachmentMode"] == "observe"
                || payload["headless"] == true
            {
                return Err(not_allowed());
            }
            let environment =
                alera_core::login_shell_environment::login_shell_variables_with_process_overrides()
                    .await;
            let home = ["HOME", "USERPROFILE"]
                .into_iter()
                .filter_map(|name| environment.get(name))
                .find(|value| !value.trim().is_empty())
                .ok_or_else(|| {
                    HostError::state("The provider setup host home directory is unavailable.")
                })?;
            payload["workingDirectory"] = json!(home);
            let mut launch = super::terminal_launch_defaults::default_terminal_launch(home, true)
                .await
                .launch;
            // Desktop shell paths and environment are never applicable to the owner.
            launch.environment.clear();
            launch.provider_setup = Some(selection.clone());
            payload["launch"] = launch.to_json();
        } else if self
            .sessions
            .get(&session_id)
            .is_none_or(|session| !session.clients.contains(&client_id))
        {
            // Definitive non-delivery permits the desktop to attach before retrying input.
            return Err(HostError::state(format!(
                "Terminal session is not attached: {session_id}"
            )));
        }
        if operation == "write"
            && self
                .queue_terminal_input_with_setup_authority(client_id, request_id, &payload, true)?
        {
            return Ok(true);
        }
        let result = match operation.as_str() {
            "createOrAttach" => {
                self.create_or_attach_with_setup_authority(client_id, &payload, true)
                    .await?
            }
            "terminal.restart" => {
                self.restart_terminal_with_setup_authority(client_id, &payload, true)
                    .await?
            }
            _ => {
                Box::pin(self.handle_authenticated_request(client_id, &operation, &payload, true))
                    .await?
            }
        };
        if matches!(operation.as_str(), "createOrAttach" | "terminal.restart") {
            let session = self
                .sessions
                .get_mut(&session_id)
                .expect("attached setup session");
            session.provider_setup_desktop_leases.extend(prior_leases);
            session
                .provider_setup_desktop_leases
                .insert(lease_id, desktop_id);
        }
        self.client_write(client_id, ok_response(request_id, result));
        Ok(true)
    }

    pub(super) fn relay_provider_setup_event(
        &self,
        host_id: &str,
        name: &str,
        payload: &Value,
    ) -> bool {
        let Some(session_id) = payload["sessionId"].as_str() else {
            return false;
        };
        let Some(clients) = self
            .host_links
            .provider_setup_sessions
            .clients(host_id, session_id)
        else {
            // Late setup output must stay private after its route is retired.
            return session_id.starts_with(SETUP_SESSION_PREFIX);
        };
        let frame = event(
            super::host_link_requests::HOST_LINK_EVENT,
            json!({"hostId":host_id,"event":name,"payload":payload}),
        );
        for client_id in clients {
            if self.require_provider_setup_client(client_id).is_ok() {
                self.client_write(client_id, frame.clone());
            }
        }
        true
    }
}

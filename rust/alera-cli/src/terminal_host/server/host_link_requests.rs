//! `hostLink.*` verbs and the actor-side handling of link events.
//!
//! Connecting a link awaits an ssh handshake, so every verb that may connect
//! runs in a spawned task and answers through
//! [`super::ServerCommand::HostLinkRequestFinished`]; only `hostLink.status` is
//! answered inline. `hostLink.mirrorWorkspace` registers a remote workspace on
//! its satellite (see [`super::host_link_routing`]).

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, event, ok_response};

use super::requests::require_string_key;
use super::ServerActor;

pub(crate) const HOST_LINK_CHANGED_EVENT: &str = "hostLinkChanged";
pub(crate) const HOST_LINK_EVENT: &str = "hostLinkEvent";

impl ServerActor {
    pub(super) fn try_start_host_link_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !request_type.starts_with("hostLink.") {
            return Ok(false);
        }
        self.require_authenticated_local_request(client_id, request_type)?;
        match request_type {
            "hostLink.status" => {
                self.client_write(
                    client_id,
                    ok_response(request_id, self.host_links.snapshot()),
                );
                Ok(true)
            }
            "hostLink.connect" => {
                let host_id = require_remote_host_id(payload)?;
                let links = self.host_links.clone();
                self.spawn_deferred_request(client_id, request_id, async move {
                    links.link(&host_id).await?;
                    Ok(link_state_payload(&links, &host_id))
                });
                Ok(true)
            }
            "hostLink.disconnect" => {
                let host_id = require_remote_host_id(payload)?;
                let links = self.host_links.clone();
                self.spawn_deferred_request(client_id, request_id, async move {
                    links.disconnect(&host_id).await;
                    Ok(link_state_payload(&links, &host_id))
                });
                Ok(true)
            }
            "hostLink.mirrorWorkspace" => {
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let store = self.runtime_store.clone();
                let links = self.host_links.clone();
                self.spawn_deferred_request(client_id, request_id, async move {
                    let (_, workspace) =
                        super::host_link_routing::mirror_workspace(&store, &links, &workspace_id)
                            .await?;
                    Ok(workspace)
                });
                Ok(true)
            }
            "hostLink.request" => {
                let host_id = require_remote_host_id(payload)?;
                let forwarded_type = require_string_key(payload, "type")?;
                if forwarded_type.starts_with("hostLink.") || forwarded_type == "hello" {
                    return Err(HostError::state(format!(
                        "{forwarded_type} cannot be forwarded over a host link."
                    )));
                }
                let forwarded_payload =
                    payload.get("payload").cloned().unwrap_or_else(|| json!({}));
                let deadline = payload
                    .get("timeoutMs")
                    .and_then(Value::as_u64)
                    .map(std::time::Duration::from_millis)
                    .unwrap_or(crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT);
                let links = self.host_links.clone();
                self.spawn_deferred_request(client_id, request_id, async move {
                    let link = links.link(&host_id).await?;
                    link.request_with_timeout(&forwarded_type, forwarded_payload, deadline)
                        .await
                });
                Ok(true)
            }
            _ => Err(HostError::state(format!(
                "Unknown terminal host request: {request_type}"
            ))),
        }
    }

    pub(super) fn finish_host_link_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        if self.require_auth(client_id).is_err() {
            return;
        }
        match result {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
    }

    pub(super) fn handle_host_link_state_changed(&mut self, host_id: String) {
        let payload = link_state_payload(&self.host_links, &host_id);
        // Whatever changed while the link was down is read once it is back.
        if payload.get("state").and_then(Value::as_str) == Some("attached") {
            self.push_agent_hook_settings_to_satellite(&host_id);
            self.start_remote_agent_presence_sync(&host_id);
        }
        self.broadcast_authenticated_local(event(HOST_LINK_CHANGED_EVENT, payload));
    }

    pub(super) fn handle_host_link_closed(&mut self, host_id: String, error: String) {
        tracing::warn!(target: "host_link", host_id, "host link closed: {error}");
        self.host_links.note_closed(&host_id, &error);
        self.handle_host_link_state_changed(host_id);
    }

    /// Satellite events are re-published wrapped with their host id. Terminal
    /// output never arrives here in this phase because the hub attaches to no
    /// satellite session yet; the proxy that will owns its own routing.
    pub(super) fn handle_host_link_event(&mut self, host_id: String, frame: Value) {
        let Some(name) = frame.get("event").and_then(Value::as_str) else {
            return;
        };
        let payload = frame.get("payload").cloned().unwrap_or(Value::Null);
        self.relay_host_link_event(&host_id, name, &payload);
        self.broadcast_authenticated_local(event(
            HOST_LINK_EVENT,
            json!({ "hostId": host_id, "event": name, "payload": payload }),
        ));
    }
}

fn require_remote_host_id(payload: &Value) -> HostResult<String> {
    let host_id = require_string_key(payload, "hostId")?;
    if !crate::ssh_remote::is_remote_host_id(Some(&host_id)) {
        return Err(HostError::state(
            "hostId must name a remote SSH host; the local runtime has no host link.",
        ));
    }
    Ok(host_id)
}

pub(crate) fn link_state_payload(
    links: &crate::terminal_host::host_link_registry::HostLinkRegistry,
    host_id: &str,
) -> Value {
    let mut value = serde_json::to_value(links.state(host_id)).unwrap_or(Value::Null);
    if let Some(object) = value.as_object_mut() {
        object.insert("hostId".into(), json!(host_id));
    }
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_link_verbs_reject_the_local_host() {
        let error = require_remote_host_id(&json!({"hostId": "local"})).unwrap_err();
        assert!(error.wire_message().contains("remote SSH host"));
        assert!(require_remote_host_id(&json!({})).is_err());
        assert_eq!(
            require_remote_host_id(&json!({"hostId": "lab"})).unwrap(),
            "lab"
        );
    }
}

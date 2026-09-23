//! The reverse channel: a client of a satellite asks the hub.
//!
//! The `alera` CLI inside a remote terminal reaches the satellite, whose store
//! only holds mirrored copies of the workspaces it serves. Hub-owned state has
//! one source of truth, so a satellite forwards the question up the host link:
//! a verb from its own CLI becomes a `hub.request {requestId, type, payload}`
//! event to the hub, and the hub answers with `hub.respond`. The link is the
//! transport both ways; there is no second connection.
//!
//! Forwarding is transparent once this runtime has mirrored a hub workspace
//! (`satelliteOfHub`): a request from a local client that is not the hub's
//! own link, for a verb in [`super::hub_reverse_policy`], goes to the hub
//! instead of acting on the copies. `hub.forward {type, payload}` remains as
//! the explicit form the CLI listings use. Requests from the hub link itself
//! (mirrors, `git.*`, `workspace.files.*`) are the hub's work for this host
//! and stay here.
//!
//! On the hub, a forwarded verb is answered by sending it to the hub itself as
//! an ordinary local client ([`super::hub_self_client`]), with the origin host
//! stamped on the payload. What may be asked is decided by the policy table on
//! both ends, because a host reached over ssh is less trusted than the desktop.

use std::collections::{HashMap, HashSet};
use std::time::Duration;

use serde_json::{json, Value};
use uuid::Uuid;

use super::hub_reverse_policy::{
    apply_origin, forwards_to_hub, hub_answers, listing_answer, listing_request, refusal,
    reply_deadline, stays_with_owner, ForwardingContext,
};
use super::hub_self_client::HubSelfClientPool;
use super::requests::require_string_key;
use super::{ClientKind, ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link::response_result;
use crate::terminal_host::host_link_registry::HostLinkRegistry;
use crate::terminal_host::protocol::{error_response, event, ok_response};

pub(super) const HUB_REQUEST_EVENT: &str = "hub.request";
/// The satellite gives up a little after the hub's own deadline, so the hub's
/// more specific failure normally arrives first.
const SATELLITE_EXPIRY_GRACE: Duration = Duration::from_secs(15);
const NO_HUB_MESSAGE: &str = "No Alera desktop is linked to this host right now, so its projects and workspaces cannot be read or changed from here. Open Alera on your desktop and connect this host, then retry.";

/// State for both ends of the channel: on a satellite, which clients are hub
/// links and which forwarded questions await an answer; on a hub, the
/// connections it answers them on.
#[derive(Default)]
pub(super) struct HubReverseState {
    hub_clients: HashSet<u64>,
    pending: HashMap<String, PendingReverseRequest>,
    /// Read from the store the first time a question needs it. A negative
    /// answer is only kept while no hub is linked, because the mirror that
    /// turns this runtime into a satellite arrives over that link.
    satellite: Option<bool>,
    self_clients: HubSelfClientPool,
}

struct PendingReverseRequest {
    asker_client_id: u64,
    asker_request_id: i64,
    hub_client_id: u64,
}

impl ServerActor {
    /// `Ok(None)` means the request is not part of the reverse channel.
    pub(super) fn try_handle_hub_reverse_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<ReverseOutcome>> {
        if !matches!(
            request_type,
            "hub.link.register" | "hub.link.status" | "hub.forward" | "hub.respond"
        ) {
            return Ok(None);
        }
        self.require_authenticated_local_request(client_id, request_type)?;
        match request_type {
            "hub.link.register" => {
                self.hub_reverse.hub_clients.insert(client_id);
                self.forget_negative_satellite_flag();
                Ok(Some(ReverseOutcome::Answer(json!({"registered": true}))))
            }
            "hub.link.status" => Ok(Some(ReverseOutcome::Answer(
                json!({"linked": !self.hub_reverse.hub_clients.is_empty()}),
            ))),
            "hub.forward" => {
                let forwarded_type = require_string_key(payload, "type")?;
                if !hub_answers(&forwarded_type) {
                    return Err(refusal(&forwarded_type));
                }
                let forwarded_payload =
                    payload.get("payload").cloned().unwrap_or_else(|| json!({}));
                self.forward_question(client_id, request_id, &forwarded_type, forwarded_payload)?;
                Ok(Some(ReverseOutcome::Deferred))
            }
            _ => {
                if !self.hub_reverse.hub_clients.contains(&client_id) {
                    return Err(HostError::state(
                        "Only a hub link may answer a forwarded request.",
                    ));
                }
                let reverse_id = require_string_key(payload, "requestId")?;
                if let Some(pending) = self.hub_reverse.pending.remove(&reverse_id) {
                    let response = match response_result(payload) {
                        Ok(value) => ok_response(pending.asker_request_id, value),
                        Err(error) => error_response(pending.asker_request_id, &error),
                    };
                    self.client_write(pending.asker_client_id, response);
                }
                Ok(Some(ReverseOutcome::Answer(json!({}))))
            }
        }
    }

    /// Transparent forwarding on a satellite. `Ok(false)` leaves the request
    /// to the local handlers; `Ok(true)` means the hub will answer it.
    pub(super) async fn try_forward_to_hub(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if request_type == "hub.mirror.workspace"
            && self.hub_reverse.hub_clients.contains(&client_id)
        {
            self.forget_negative_satellite_flag();
            return Ok(false);
        }
        let Some(client) = self.clients.get(&client_id) else {
            return Ok(false);
        };
        let context = ForwardingContext {
            // Decided last, below: most requests fail the cheap checks and
            // the flag costs a store read the first time.
            satellite: true,
            authenticated: client.authenticated,
            local_client: client.kind == ClientKind::Local,
            hub_link: self.hub_reverse.hub_clients.contains(&client_id),
        };
        let guard_is_local = payload
            .get("guardId")
            .and_then(Value::as_str)
            .is_some_and(|guard_id| self.checkout_buffer_guards.contains_key(guard_id));
        if !forwards_to_hub(context, request_type)
            || stays_with_owner(request_type, payload, guard_is_local)
            || !self.is_satellite_runtime().await
        {
            return Ok(false);
        }
        self.forward_question(client_id, request_id, request_type, payload.clone())?;
        Ok(true)
    }

    async fn is_satellite_runtime(&mut self) -> bool {
        if let Some(satellite) = self.hub_reverse.satellite {
            return satellite;
        }
        let satellite = crate::hub_federation::is_satellite(&self.runtime_store).await;
        if satellite || self.hub_reverse.hub_clients.is_empty() {
            self.hub_reverse.satellite = Some(satellite);
        }
        satellite
    }

    fn forget_negative_satellite_flag(&mut self) {
        self.hub_reverse.satellite = self.hub_reverse.satellite.filter(|&satellite| satellite);
    }

    fn forward_question(
        &mut self,
        client_id: u64,
        request_id: i64,
        forwarded_type: &str,
        forwarded_payload: Value,
    ) -> HostResult<()> {
        let Some(hub_client_id) = self.hub_reverse.hub_clients.iter().next().copied() else {
            return Err(HostError::state(NO_HUB_MESSAGE));
        };
        let reverse_id = Uuid::new_v4().to_string();
        let deadline = reply_deadline(forwarded_type, &forwarded_payload) + SATELLITE_EXPIRY_GRACE;
        self.hub_reverse.pending.insert(
            reverse_id.clone(),
            PendingReverseRequest {
                asker_client_id: client_id,
                asker_request_id: request_id,
                hub_client_id,
            },
        );
        self.client_write(
            hub_client_id,
            event(
                HUB_REQUEST_EVENT,
                json!({
                    "requestId": reverse_id,
                    "type": forwarded_type,
                    "payload": forwarded_payload,
                }),
            ),
        );
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(deadline).await;
            let _ = inbox.send(ServerCommand::HubReverseRequestExpired { reverse_id });
        });
        Ok(())
    }

    pub(super) fn expire_hub_reverse_request(&mut self, reverse_id: &str) {
        if let Some(pending) = self.hub_reverse.pending.remove(reverse_id) {
            self.client_write(
                pending.asker_client_id,
                error_response(
                    pending.asker_request_id,
                    &HostError::state("The Alera desktop did not answer in time."),
                ),
            );
        }
    }

    /// A hub link that goes away takes its unanswered questions with it.
    pub(super) fn forget_hub_reverse_client(&mut self, client_id: u64) {
        self.hub_reverse
            .pending
            .retain(|_, pending| pending.asker_client_id != client_id);
        if !self.hub_reverse.hub_clients.remove(&client_id) {
            return;
        }
        let orphaned: Vec<String> = self
            .hub_reverse
            .pending
            .iter()
            .filter(|(_, pending)| pending.hub_client_id == client_id)
            .map(|(id, _)| id.clone())
            .collect();
        for reverse_id in orphaned {
            if let Some(pending) = self.hub_reverse.pending.remove(&reverse_id) {
                self.client_write(
                    pending.asker_client_id,
                    error_response(pending.asker_request_id, &HostError::state(NO_HUB_MESSAGE)),
                );
            }
        }
    }

    /// Hub side: a satellite forwarded a question. Answered on a spawned task,
    /// because both the self-request and the reply travel outside the actor.
    pub(super) fn start_hub_reverse_answer(&self, host_id: &str, request: &Value) {
        let Some(reverse_id) = request.get("requestId").and_then(Value::as_str) else {
            return;
        };
        let request_type = request
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let payload = request.get("payload").cloned().unwrap_or_else(|| json!({}));
        let reverse_id = reverse_id.to_string();
        let host_id = host_id.to_string();
        let runtime_dir = self.runtime_dir.clone();
        let pool = self.hub_reverse.self_clients.clone();
        let links = self.host_links.clone();
        tokio::spawn(async move {
            let result =
                answer_reverse_request(&pool, &runtime_dir, &host_id, &request_type, payload).await;
            respond(&links, &host_id, &reverse_id, result).await;
        });
    }
}

#[derive(Debug)]
pub(super) enum ReverseOutcome {
    Answer(Value),
    Deferred,
}

/// The hub answers by asking itself. The origin host is stamped on the payload
/// first, and the CLI listings keep the `{items, originHostId}` shape.
async fn answer_reverse_request(
    pool: &HubSelfClientPool,
    runtime_dir: &std::path::Path,
    origin_host_id: &str,
    request_type: &str,
    payload: Value,
) -> HostResult<Value> {
    if !hub_answers(request_type) {
        return Err(refusal(request_type));
    }
    let payload = apply_origin(request_type, payload, origin_host_id);
    let deadline = reply_deadline(request_type, &payload);
    let (hub_type, hub_payload) = listing_request(request_type, &payload);
    let answer = pool
        .request(
            runtime_dir,
            origin_host_id,
            &hub_type,
            hub_payload,
            deadline,
        )
        .await?;
    Ok(listing_answer(
        request_type,
        &payload,
        origin_host_id,
        answer,
    ))
}

/// The reply keeps the error shape of a normal response (`FormatException:`
/// prefix, `errorCode`, `errorDetails`), so the satellite can rebuild it.
async fn respond(
    links: &HostLinkRegistry,
    host_id: &str,
    reverse_id: &str,
    result: HostResult<Value>,
) {
    let mut payload = match result {
        Ok(value) => json!({"ok": true, "payload": value}),
        Err(error) => {
            let mut frame = error.wire_response(0);
            if let Some(object) = frame.as_object_mut() {
                object.remove("id");
            }
            frame
        }
    };
    payload["requestId"] = json!(reverse_id);
    if let Ok(link) = links.link(host_id).await {
        let _ = link
            .request_with_timeout(
                "hub.respond",
                payload,
                crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
            )
            .await;
    }
}

#[cfg(test)]
#[path = "hub_reverse_requests_tests.rs"]
mod tests;

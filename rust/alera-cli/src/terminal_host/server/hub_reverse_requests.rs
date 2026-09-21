//! The reverse channel: a client of a satellite asks the hub a question.
//!
//! The `alera` CLI inside a remote terminal reaches the satellite, whose store
//! only holds mirrored copies of the workspaces it serves. Hub-owned state has
//! one source of truth, so instead of answering from those copies the satellite
//! forwards the question up the host link: `hub.forward {type, payload}` from
//! the CLI becomes a `hub.request {requestId, type, payload}` event to the hub,
//! and the hub answers with `hub.respond`. The link is the transport both ways;
//! there is no second connection.
//!
//! What a remote host may ask is decided on the hub, by
//! `answer_reverse_request`, and it is read-only on purpose: a host the hub
//! reaches over ssh is less trusted than the hub, and forwarding mutations or
//! terminal verbs would let a compromised server drive the user's desktop.

use std::collections::{HashMap, HashSet};
use std::time::Duration;

use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};
use uuid::Uuid;

use super::requests::{optional_string_key, require_string_key};
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;
use crate::terminal_host::protocol::{error_response, event, ok_response};

pub(super) const HUB_REQUEST_EVENT: &str = "hub.request";
const REVERSE_REQUEST_TIMEOUT: Duration = Duration::from_secs(60);
const NO_HUB_MESSAGE: &str = "No Alera desktop is linked to this host right now, so its projects and workspaces cannot be read from here. Open Alera on your desktop and connect this host, then retry.";

/// Satellite-side state: which clients are hub links, and which forwarded
/// questions are waiting for their answer.
#[derive(Default)]
pub(super) struct HubReverseState {
    hub_clients: HashSet<u64>,
    pending: HashMap<String, PendingReverseRequest>,
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
                Ok(Some(ReverseOutcome::Answer(json!({"registered": true}))))
            }
            "hub.link.status" => Ok(Some(ReverseOutcome::Answer(
                json!({"linked": !self.hub_reverse.hub_clients.is_empty()}),
            ))),
            "hub.forward" => {
                let forwarded_type = require_string_key(payload, "type")?;
                let Some(hub_client_id) = self.hub_reverse.hub_clients.iter().next().copied()
                else {
                    return Err(HostError::state(NO_HUB_MESSAGE));
                };
                let reverse_id = Uuid::new_v4().to_string();
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
                            "payload": payload.get("payload").cloned().unwrap_or_else(|| json!({})),
                        }),
                    ),
                );
                let inbox = self.inbox.clone();
                tokio::spawn(async move {
                    tokio::time::sleep(REVERSE_REQUEST_TIMEOUT).await;
                    let _ = inbox.send(ServerCommand::HubReverseRequestExpired { reverse_id });
                });
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
                    let response = if payload.get("ok").and_then(Value::as_bool) == Some(true) {
                        ok_response(
                            pending.asker_request_id,
                            payload.get("payload").cloned().unwrap_or(Value::Null),
                        )
                    } else {
                        error_response(
                            pending.asker_request_id,
                            &HostError::state(
                                optional_string_key(payload, "error")
                                    .unwrap_or_else(|| "The hub refused the request.".to_string()),
                            ),
                        )
                    };
                    self.client_write(pending.asker_client_id, response);
                }
                Ok(Some(ReverseOutcome::Answer(json!({}))))
            }
        }
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
    /// because both the store read and the reply travel outside the actor.
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
        let store = self.runtime_store.clone();
        let links = self.host_links.clone();
        tokio::spawn(async move {
            let result = answer_reverse_request(&store, &host_id, &request_type, &payload).await;
            respond(&links, &host_id, &reverse_id, result).await;
        });
    }
}

#[derive(Debug)]
pub(super) enum ReverseOutcome {
    Answer(Value),
    Deferred,
}

async fn respond(
    links: &HostLinkRegistry,
    host_id: &str,
    reverse_id: &str,
    result: HostResult<Value>,
) {
    let payload = match result {
        Ok(value) => json!({"requestId": reverse_id, "ok": true, "payload": value}),
        Err(error) => json!({"requestId": reverse_id, "ok": false, "error": error.wire_message()}),
    };
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

/// Everything a remote host may ask the hub. Read-only: see the module note.
/// `originHostId` on each answer lets the CLI default `--host-id` to where it
/// is running.
pub(super) async fn answer_reverse_request(
    store: &RuntimeStore,
    origin_host_id: &str,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    let state = |error: anyhow::Error| HostError::state(error.to_string());
    match request_type {
        "project.list" => {
            let mut projects = json!(store.list_projects().await.map_err(state)?);
            crate::project_hosts::decorate_projects(store, &mut projects).await;
            Ok(json!({"items": projects, "originHostId": origin_host_id}))
        }
        "workspace.list" => {
            let mut workspaces = match optional_string_key(payload, "projectId") {
                Some(project_id) => store.list_workspaces(&project_id).await.map_err(state)?,
                None => store.list_all_workspaces().await.map_err(state)?,
            };
            if let Some(host_id) = optional_string_key(payload, "hostId") {
                let host_id = if host_id == "origin" {
                    origin_host_id.to_string()
                } else {
                    crate::ssh_remote::normalized_host_id(Some(&host_id))
                };
                workspaces.retain(|workspace| workspace.host_id == host_id);
            }
            Ok(json!({"items": workspaces, "originHostId": origin_host_id}))
        }
        "project.hosts.list" => {
            let project_id = require_string_key(payload, "projectId")?;
            super::project_host_requests::project_hosts(store, &project_id).await
        }
        _ => Err(HostError::state(format!(
            "A remote host cannot ask the Alera desktop for {request_type}. Run this command on the desktop instead."
        ))),
    }
}

#[cfg(test)]
#[path = "hub_reverse_requests_tests.rs"]
mod tests;

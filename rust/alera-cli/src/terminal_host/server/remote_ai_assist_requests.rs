//! AI Assist generation for a workspace whose checkout lives on another host.
//!
//! The agent CLI has to run where the checkout is: it reads the repository,
//! and it signs in with that host's credentials, which never cross hosts. The
//! hub therefore forwards the same `aiText.*` verb to the satellite instead of
//! running a second implementation. What the satellite cannot know is how the
//! user configured AI Assist, because settings are hub-owned, so the forwarded
//! payload carries the hub's effective settings (`aiAssistSettings`). That
//! field can name a custom command, so a runtime only honors it from a local
//! client, which is what the host link is on the satellite.

use std::time::Duration;

use alera_core::runtime::{RuntimeAiAssistSettings, RuntimeStore, Workspace};
use serde_json::{json, Value};

use super::{ClientKind, ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

pub(super) const AI_ASSIST_SETTINGS_KEY: &str = "aiAssistSettings";

/// The satellite needs time to report its own timeout before the link gives
/// up on the request.
const FORWARDING_MARGIN: Duration = Duration::from_secs(30);

/// Verbs keyed by `workspaceId` that generate from the checkout.
fn is_workspace_generation_verb(request_type: &str) -> bool {
    matches!(
        request_type,
        "aiText.commitMessage.generate" | "aiText.pullRequestDetails.generate"
    )
}

fn remote_operation_key(operation_id: &str) -> String {
    format!("aiAssist:{operation_id}")
}

/// The settings a generation should run with: the hub's when it sent them,
/// this runtime's own otherwise.
pub(super) async fn effective_ai_assist_settings(
    store: &RuntimeStore,
    hub_settings: Option<RuntimeAiAssistSettings>,
) -> HostResult<RuntimeAiAssistSettings> {
    match hub_settings {
        Some(settings) => Ok(settings),
        None => store
            .effective_ai_assist_settings()
            .await
            .map_err(|error| HostError::state(error.to_string())),
    }
}

pub(super) fn hub_ai_assist_settings(
    payload: &Value,
) -> HostResult<Option<RuntimeAiAssistSettings>> {
    match payload.get(AI_ASSIST_SETTINGS_KEY) {
        None | Some(Value::Null) => Ok(None),
        Some(settings) => serde_json::from_value(settings.clone())
            .map(Some)
            .map_err(|error| {
                HostError::format(format!("Invalid {AI_ASSIST_SETTINGS_KEY}: {error}"))
            }),
    }
}

impl ServerActor {
    /// Settings travel from a hub to its satellite and from nowhere else: a
    /// paired phone naming a custom command would be remote code execution.
    pub(super) fn refuse_hub_only_payload_fields(
        &self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<()> {
        if payload.get(AI_ASSIST_SETTINGS_KEY).is_none() {
            return Ok(());
        }
        let local = self
            .clients
            .get(&client_id)
            .is_some_and(|client| client.kind == ClientKind::Local);
        if local {
            return Ok(());
        }
        Err(HostError::state(format!(
            "{AI_ASSIST_SETTINGS_KEY} is only accepted from a local client."
        )))
    }

    /// Forwards a workspace-keyed generation when the workspace is remote.
    /// `Ok(false)` leaves the request to the local implementation.
    pub(super) async fn try_start_remote_ai_assist(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !is_workspace_generation_verb(request_type) {
            return Ok(false);
        }
        let Some(workspace_id) = payload.get("workspaceId").and_then(Value::as_str) else {
            return Ok(false);
        };
        let Some(workspace) = self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(false);
        };
        if !crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)) {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        self.start_remote_ai_assist(client_id, request_id, request_type, &workspace, payload);
        Ok(true)
    }

    /// Runs one generation on the workspace's host and answers the client the
    /// same way a local generation does.
    pub(super) fn start_remote_ai_assist(
        &self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        workspace: &Workspace,
        payload: &Value,
    ) {
        let store = self.runtime_store.clone();
        let links = self.host_links.clone();
        let inbox = self.inbox.clone();
        let request_type = request_type.to_string();
        let workspace = workspace.clone();
        let payload = payload.clone();
        tokio::spawn(async move {
            let result =
                forward_generation(&store, &links, &request_type, &workspace, payload).await;
            let _ = inbox.send(ServerCommand::AiAssistFinished {
                client_id,
                request_id,
                result,
            });
        });
    }

    /// Cancels a generation that is running on a satellite. The answer does
    /// not wait for the link: the cancel is a synchronous actor verb.
    pub(super) fn cancel_remote_ai_assist(&self, operation_id: &str) -> bool {
        let Some(host_id) = self
            .host_links
            .forget_remote_session(&remote_operation_key(operation_id))
        else {
            return false;
        };
        let links = self.host_links.clone();
        let payload = json!({ "operationId": operation_id });
        tokio::spawn(async move {
            if let Ok(link) = links.link(&host_id).await {
                let _ = link
                    .request_with_timeout(
                        "aiText.cancel",
                        payload,
                        crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
                    )
                    .await;
            }
        });
        true
    }
}

async fn forward_generation(
    store: &RuntimeStore,
    links: &HostLinkRegistry,
    request_type: &str,
    workspace: &Workspace,
    payload: Value,
) -> HostResult<Value> {
    let settings = store
        .effective_ai_assist_settings()
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    if !settings.enabled {
        return Err(HostError::state("AI Assist is disabled."));
    }
    let timeout = Duration::from_secs(settings.timeout_seconds) + FORWARDING_MARGIN;
    let forwarded = forwarded_payload(&workspace.id, &settings, payload)?;
    let operation_key = forwarded
        .get("operationId")
        .and_then(Value::as_str)
        .map(remote_operation_key);
    let (link, _) = super::host_link_routing::mirror_workspace(store, links, &workspace.id).await?;
    if let Some(key) = &operation_key {
        links.note_remote_session(key, &workspace.host_id);
    }
    let result = link
        .request_with_timeout(request_type, forwarded, timeout)
        .await;
    if let Some(key) = &operation_key {
        links.forget_remote_session(key);
    }
    result
}

/// The satellite knows the workspace (it was mirrored) but none of the hub's
/// tabs, so the request names the workspace and drops the tab.
fn forwarded_payload(
    workspace_id: &str,
    settings: &RuntimeAiAssistSettings,
    mut payload: Value,
) -> HostResult<Value> {
    let Some(fields) = payload.as_object_mut() else {
        return Err(HostError::format("AI Assist payload must be an object."));
    };
    fields.remove("tabId");
    fields.insert("workspaceId".to_string(), json!(workspace_id));
    fields.insert(
        AI_ASSIST_SETTINGS_KEY.to_string(),
        serde_json::to_value(settings).map_err(|error| HostError::state(error.to_string()))?,
    );
    Ok(payload)
}

#[cfg(test)]
#[path = "remote_ai_assist_requests_tests.rs"]
mod tests;

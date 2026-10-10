//! `aiText.pullRequestDetails.generate` with `waitMs`: the runtime owns the
//! generation as a job keyed by who asked and by the caller's `operationId`,
//! answers `running` when the wait ends first, and lets a later request with
//! the same key attach to the job or read its result. Without `waitMs` the
//! verb keeps its original one-shot behavior, which the apps rely on.
//!
//! The key includes the caller's origin, workspace and base branch, because
//! an MCP client chooses its own retry keys: two clients that pick the same
//! key never share a job, and one client reusing a key for another range
//! gets a new generation rather than the wrong text.

use std::time::Duration;

use alera_core::runtime::{RuntimeAiAssistSettings, RuntimeStore};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

use super::ai_assist_operation_registry::active_generations;
use super::ai_assist_pull_request_details::{details_value, generate_pull_request_details};
use super::ai_assist_pull_request_details_jobs::{
    attach_or_start, pull_request_details_jobs, Outcome, RESULT_TTL,
};
use super::client_delivery::LocalClientRole;
use super::host_service_requests::required_non_blank;
use super::remote_ai_assist_requests::{forward_generation, hub_ai_assist_settings};
use super::{ClientKind, ServerActor, ServerCommand};

const VERB: &str = "aiText.pullRequestDetails.generate";
const WAIT_KEY: &str = "waitMs";
/// A single request never waits longer than a result is kept.
const MAX_WAIT: Duration = RESULT_TTL;
const OPERATION_ID_MAX_CHARS: usize = 256;

/// Whether this request asked for a resumable generation.
pub(super) fn is_resumable_pull_request_details(request_type: &str, payload: &Value) -> bool {
    request_type == VERB && payload.get(WAIT_KEY).is_some_and(|wait| !wait.is_null())
}

fn requested_wait(payload: &Value) -> HostResult<Duration> {
    payload
        .get(WAIT_KEY)
        .and_then(Value::as_u64)
        .map(|millis| Duration::from_millis(millis).min(MAX_WAIT))
        .ok_or_else(|| HostError::format(format!("{WAIT_KEY} must be a non-negative integer.")))
}

impl ServerActor {
    pub(super) fn start_resumable_pull_request_details(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let wait = requested_wait(payload)?;
        let operation_id = required_non_blank(payload, "operationId")?;
        if operation_id.chars().count() > OPERATION_ID_MAX_CHARS {
            return Err(HostError::format(format!(
                "operationId must be at most {OPERATION_ID_MAX_CHARS} characters."
            )));
        }
        let workspace_id = required_non_blank(payload, "workspaceId")?;
        let base_branch = required_non_blank(payload, "baseBranch")?;
        let hub_settings = hub_ai_assist_settings(payload)?;
        let scope = self.pull_request_details_scope(client_id, payload)?;
        let key = json!([scope, workspace_id, base_branch, operation_id]).to_string();
        let job = DetailsJob {
            store: self.runtime_store.clone(),
            links: self.host_links.clone(),
            workspace_id,
            base_branch,
            hub_settings,
        };
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result =
                attach_or_start(pull_request_details_jobs(), &key, wait, move || job.run())
                    .await
                    .map(|details| resumable_answer(details, &operation_id));
            let _ = inbox
                .send_wait(ServerCommand::AiAssistFinished {
                    client_id,
                    request_id,
                    result,
                })
                .await;
        });
        Ok(())
    }

    /// Who asked. Only a local connection, the CLI process an MCP tool runs,
    /// may name the MCP client it acts for; a phone is its paired device.
    fn pull_request_details_scope(&self, client_id: u64, payload: &Value) -> HostResult<Value> {
        let client = self.clients.get(&client_id);
        let local = client.is_some_and(|client| client.kind == ClientKind::Local);
        let mcp_origin = payload
            .get("origin")
            .filter(|origin| origin.get("transport").is_some());
        if let (true, Some(origin)) = (local, mcp_origin) {
            let origin = super::inbox_requests::external_origin(origin)?;
            return Ok(json!([
                "mcp",
                origin["transport"],
                origin["clientId"],
                origin["grantId"]
            ]));
        }
        Ok(match client {
            Some(client) if client.kind == ClientKind::Mobile => {
                json!(["mobile", client.mobile_device_id])
            }
            Some(client) if client.local_role == LocalClientRole::App => json!(["desktop"]),
            _ => json!(["cli"]),
        })
    }
}

/// The details with `status: completed`, or `status: running` while the job
/// is still generating. Both name the caller's `operationId` to resume with.
pub(super) fn resumable_answer(details: Option<Value>, operation_id: &str) -> Value {
    let mut answer = match details {
        Some(Value::Object(fields)) => Value::Object(fields),
        Some(_) => json!({}),
        None => return json!({ "status": "running", "operationId": operation_id }),
    };
    answer["status"] = json!("completed");
    answer["operationId"] = json!(operation_id);
    answer
}

/// One generation, run where the workspace's checkout lives.
struct DetailsJob {
    store: RuntimeStore,
    links: HostLinkRegistry,
    workspace_id: String,
    base_branch: String,
    hub_settings: Option<RuntimeAiAssistSettings>,
}

impl DetailsJob {
    async fn run(self) -> Outcome {
        let workspace = self
            .store
            .find_workspace(&self.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("Workspace not found: {}", self.workspace_id))
            })?;
        // The job's own id, never the caller's key: retry keys are chosen by
        // clients and must not collide with another generation's cancel id.
        let generation_id = format!("pull-request-details-{}", uuid::Uuid::new_v4());
        if crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)) {
            let payload = json!({
                "operationId": generation_id,
                "workspaceId": workspace.id,
                "baseBranch": self.base_branch,
            });
            return forward_generation(&self.store, &self.links, VERB, &workspace, payload).await;
        }
        let (registration, cancel_rx) = active_generations().register(generation_id, None)?;
        let result = generate_pull_request_details(
            &self.store,
            &self.workspace_id,
            &self.base_branch,
            self.hub_settings,
            cancel_rx,
        )
        .await;
        drop(registration);
        result.map(|(details, agent_label)| details_value(&details, &agent_label))
    }
}

#[cfg(test)]
#[path = "ai_assist_pull_request_details_resume_tests.rs"]
mod tests;

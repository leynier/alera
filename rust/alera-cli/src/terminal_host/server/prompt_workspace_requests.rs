//! `workspace.promptStart.*`: New Workspace from Prompt as a runtime operation.
//!
//! `start` records the operation and returns at once; the run continues in the
//! background and every client follows it with `get`, `list`, or the
//! `promptWorkspaceOperationsChanged` event. A start with a `requestId` already
//! used returns that operation, so a retried call never creates a second
//! workspace. `retryLaunch` relaunches the agent of an operation whose
//! workspace exists, with the same idempotency key as the first launch.

use serde_json::{json, Value};
use tokio::sync::oneshot;
use uuid::Uuid;

use super::prompt_workspace_operation::{
    PromptWorkspaceOperation, PromptWorkspaceRequest, SectionPolicy, FAILED, MAX_PROMPT_CHARS,
    RUNNING,
};
use super::prompt_workspace_pipeline::PromptWorkspaceRun;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

const EVENT: &str = "promptWorkspaceOperationsChanged";
const DEFAULT_LIST_LIMIT: i64 = 20;
const MAX_REQUEST_ID_CHARS: usize = 128;

impl ServerActor {
    pub(super) async fn prompt_workspace_start_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let prompt = payload
            .get("prompt")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|prompt| !prompt.is_empty())
            .ok_or_else(|| HostError::format("prompt is required"))?
            .to_owned();
        if prompt.chars().count() > MAX_PROMPT_CHARS {
            return Err(HostError::format("prompt is too long"));
        }
        let mut request: PromptWorkspaceRequest = serde_json::from_value(json!({
            "projectId": text(payload, "projectId"),
            "profile": text(payload, "profile"),
            "mode": payload.get("mode").cloned().unwrap_or(json!("auto")),
            "sourceBranch": text(payload, "sourceBranch"),
            "hostId": text(payload, "hostId"),
            "parentWorkspaceId": text(payload, "parentWorkspaceId"),
            "issueUrl": text(payload, "issueUrl"),
        }))
        .map_err(|error| HostError::format(format!("invalid request: {error}")))?;
        request.section = SectionPolicy::parse(payload.get("section"))?;
        let request_id = text(payload, "requestId");
        if request_id
            .as_ref()
            .is_some_and(|key| key.chars().count() > MAX_REQUEST_ID_CHARS)
        {
            return Err(HostError::format("requestId is too long"));
        }
        let origin = self.prompt_workspace_origin(client_id, payload)?;
        let request_key = scoped_request_key(request_id.as_deref(), origin.as_ref());
        let operation = PromptWorkspaceOperation::new(
            Uuid::new_v4().to_string(),
            request_id.clone(),
            prompt,
            request,
            origin,
        );
        let record = self
            .runtime_store
            .insert_prompt_workspace_operation(
                &operation.id,
                request_key.as_deref(),
                RUNNING,
                &operation.to_value(),
            )
            .await
            .map_err(store_error)?;
        if record.id != operation.id {
            return public(&record.data);
        }
        self.spawn_prompt_workspace_run(operation.clone(), false);
        Ok(operation.public_value())
    }

    pub(super) async fn prompt_workspace_get_request(&self, payload: &Value) -> HostResult<Value> {
        let id = required(payload, "id")?;
        let record = self
            .runtime_store
            .find_prompt_workspace_operation(&id)
            .await
            .map_err(store_error)?
            .ok_or_else(|| {
                HostError::state(format!("Prompt workspace operation not found: {id}"))
            })?;
        public(&record.data)
    }

    pub(super) async fn prompt_workspace_list_request(&self, payload: &Value) -> HostResult<Value> {
        let limit = payload
            .get("limit")
            .and_then(Value::as_i64)
            .unwrap_or(DEFAULT_LIST_LIMIT);
        let records = self
            .runtime_store
            .list_prompt_workspace_operations(limit)
            .await
            .map_err(store_error)?;
        let items = records
            .iter()
            .map(|record| public(&record.data))
            .collect::<HostResult<Vec<_>>>()?;
        Ok(json!({ "kind": "promptWorkspaceOperations", "items": items }))
    }

    pub(super) fn prompt_workspace_cancel_request(&mut self, payload: &Value) -> HostResult<Value> {
        let id = required(payload, "id")?;
        let cancelling = match self.prompt_workspace_operations.remove(&id) {
            Some(cancel) => cancel.send(()).is_ok(),
            None => false,
        };
        Ok(json!({ "id": id, "cancelling": cancelling }))
    }

    pub(super) async fn prompt_workspace_retry_launch_request(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let id = required(payload, "id")?;
        if self.prompt_workspace_operations.contains_key(&id) {
            return Err(HostError::state("This operation is still running."));
        }
        let record = self
            .runtime_store
            .find_prompt_workspace_operation(&id)
            .await
            .map_err(store_error)?
            .ok_or_else(|| {
                HostError::state(format!("Prompt workspace operation not found: {id}"))
            })?;
        let mut operation: PromptWorkspaceOperation =
            serde_json::from_value(record.data).map_err(store_error)?;
        if !operation.can_retry_launch() || operation.prompt.is_none() {
            return Err(HostError::state(
                "Only an operation whose workspace exists and whose agent did not launch can retry its launch.",
            ));
        }
        operation.status = RUNNING.to_owned();
        operation.error = None;
        self.runtime_store
            .update_prompt_workspace_operation(&operation.id, RUNNING, &operation.to_value())
            .await
            .map_err(store_error)?;
        self.spawn_prompt_workspace_run(operation.clone(), true);
        Ok(operation.public_value())
    }

    fn spawn_prompt_workspace_run(
        &mut self,
        operation: PromptWorkspaceOperation,
        launch_only: bool,
    ) {
        let (cancel_tx, cancel_rx) = oneshot::channel();
        self.prompt_workspace_operations
            .insert(operation.id.clone(), cancel_tx);
        self.cancel_shutdown_timer();
        let id = operation.id.clone();
        let run = PromptWorkspaceRun::new(
            self.runtime_store.clone(),
            self.inbox.clone(),
            self.runtime_dir.clone(),
            operation,
            cancel_rx,
        );
        tokio::spawn(run.run(launch_only));
        self.broadcast_authenticated(event(EVENT, json!({ "id": id })));
    }

    /// A runtime restart stops every run; their records say so, and those
    /// whose workspace exists can still retry the launch.
    pub(super) async fn reconcile_interrupted_prompt_workspaces(&mut self) {
        let records = match self
            .runtime_store
            .list_running_prompt_workspace_operations()
            .await
        {
            Ok(records) => records,
            Err(error) => {
                tracing::warn!("prompt workspace recovery unavailable: {error}");
                return;
            }
        };
        for record in records {
            let Ok(mut operation) = serde_json::from_value::<PromptWorkspaceOperation>(record.data)
            else {
                continue;
            };
            let retryable = operation.workspace_id().is_some();
            operation.fail(
                "interrupted",
                "The runtime restarted during this operation.",
                retryable,
            );
            let _ = self
                .runtime_store
                .update_prompt_workspace_operation(&operation.id, FAILED, &operation.to_value())
                .await;
        }
        let _ = self.runtime_store.prune_prompt_workspace_operations().await;
    }

    pub(super) fn handle_prompt_workspace_operation_changed(&self, operation_id: String) {
        self.broadcast_authenticated(event(EVENT, json!({ "id": operation_id })));
    }

    pub(super) fn handle_prompt_workspace_operation_finished(&mut self, operation_id: String) {
        self.prompt_workspace_operations.remove(&operation_id);
        self.broadcast_authenticated(event(EVENT, json!({ "id": operation_id })));
        self.schedule_shutdown_if_idle();
    }
}

impl ServerActor {
    /// Who started an operation. The connection decides the surface; only a
    /// local connection, the CLI process an MCP tool runs, may name the MCP
    /// client it acts for, so a phone or the hub cannot claim to be one.
    fn prompt_workspace_origin(
        &self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let local = self
            .clients
            .get(&client_id)
            .is_some_and(|client| client.kind == super::ClientKind::Local);
        match payload.get("origin").filter(|origin| !origin.is_null()) {
            Some(origin) if local => super::inbox_requests::external_origin(origin).map(Some),
            _ => Ok(Some(self.inbox_origin(client_id))),
        }
    }
}

/// The stored retry key. Keys an MCP client chose are kept apart per client,
/// so two clients that happen to pick the same key never share an operation.
fn scoped_request_key(request_id: Option<&str>, origin: Option<&Value>) -> Option<String> {
    let request_id = request_id?;
    let client = origin
        .and_then(|origin| origin.get("clientId"))
        .and_then(Value::as_str);
    Some(match client {
        Some(client) => format!("mcp:{client}:{request_id}"),
        None => request_id.to_owned(),
    })
}

fn text(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

fn required(payload: &Value, key: &str) -> HostResult<String> {
    text(payload, key).ok_or_else(|| HostError::format(format!("{key} is required")))
}

fn public(data: &Value) -> HostResult<Value> {
    let operation: PromptWorkspaceOperation =
        serde_json::from_value(data.clone()).map_err(store_error)?;
    Ok(operation.public_value())
}

fn store_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::scoped_request_key;

    #[test]
    fn retry_keys_are_kept_apart_per_mcp_client() {
        let codex = json!({"surface": "mcp", "transport": "local", "clientId": "codex"});
        let chatgpt = json!({"surface": "mcp", "transport": "remote", "clientId": "chatgpt"});
        let phone = json!({"surface": "mobile", "deviceId": "d-1"});
        assert_eq!(
            scoped_request_key(Some("key-0001"), Some(&codex)).as_deref(),
            Some("mcp:codex:key-0001")
        );
        assert_ne!(
            scoped_request_key(Some("key-0001"), Some(&codex)),
            scoped_request_key(Some("key-0001"), Some(&chatgpt))
        );
        assert_eq!(
            scoped_request_key(Some("key-0001"), Some(&phone)).as_deref(),
            Some("key-0001")
        );
        assert_eq!(scoped_request_key(None, Some(&codex)), None);
    }
}

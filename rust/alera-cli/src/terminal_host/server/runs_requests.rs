//! The `runs.*` and `recipes.*` client surface. Reads run off the actor on a
//! bounded queue; mutations go through the run store with the actor taken
//! from the connection. Mobile clients reach every `runs.*` verb plus
//! `recipes.catalog` and `recipes.recipe` (see `mobile_gateway_surface.rs`).

use std::sync::{Arc, OnceLock};
use std::time::Duration;

use alera_core::runtime::{
    OrchestrationBoardQuery, OrchestrationRunSnapshotQuery, OrchestrationTaskInspectionQuery,
    RunActor, RunActorKind, RunGateFilter, RunGateKind, RunTimelineQuery, RuntimeStore,
    WorkflowCleanupQuery, WorkflowIntegrationQuery,
};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::Semaphore;

use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::client_delivery::LocalClientRole;
use super::orchestration_gate_requests::gate_error;
use super::{ClientKind, ServerActor};

static READ_SLOTS: OnceLock<Arc<Semaphore>> = OnceLock::new();
static READ_QUEUE: OnceLock<Arc<Semaphore>> = OnceLock::new();

/// Payloads are small objects; plan and recipe documents use their own verbs.
const RUNS_PAYLOAD_MAX_BYTES: usize = 64 * 1024;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PlanQuery {
    run_id: String,
    revision: Option<i64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct GatesQuery {
    run_id: String,
    task_id: Option<String>,
    kind: Option<String>,
    status: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct GateQuery {
    gate_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SourceQuery {
    workspace_id: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct IdQuery {
    id: String,
}

enum RunsRead {
    Board(OrchestrationBoardQuery),
    Snapshot(OrchestrationRunSnapshotQuery),
    Task(OrchestrationTaskInspectionQuery),
    Timeline(RunTimelineQuery),
    Source(SourceQuery),
    Plan(PlanQuery),
    Gates(GatesQuery),
    Gate(GateQuery),
    Resources(WorkflowCleanupQuery),
    Cleanups(WorkflowCleanupQuery),
    PreviewCleanup(Value),
    Cleanup(IdQuery),
    Integrations(WorkflowIntegrationQuery),
    Integration(IdQuery),
}

impl ServerActor {
    /// Routes `runs.*` and `recipes.*`. Returns false for any other verb.
    pub(super) async fn try_start_runs_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !(request_type.starts_with("runs.") || request_type.starts_with("recipes.")) {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        if request_type.starts_with("recipes.") {
            self.start_recipe_request(client_id, request_id, request_type, payload)?;
            return Ok(true);
        }
        if serde_json::to_vec(payload).map_or(true, |bytes| bytes.len() > RUNS_PAYLOAD_MAX_BYTES) {
            return Err(HostError::format("runs request exceeds the byte limit"));
        }
        let read = match request_type {
            "runs.board" => Some(RunsRead::Board(parse(payload)?)),
            "runs.snapshot" => Some(RunsRead::Snapshot(parse(payload)?)),
            "runs.task" => Some(RunsRead::Task(parse(payload)?)),
            "runs.timeline" => Some(RunsRead::Timeline(parse(payload)?)),
            "runs.source" => Some(RunsRead::Source(parse(payload)?)),
            "runs.plan" => Some(RunsRead::Plan(parse(payload)?)),
            "runs.gates" => Some(RunsRead::Gates(parse(payload)?)),
            "runs.gate" => Some(RunsRead::Gate(parse(payload)?)),
            "runs.resources" => Some(RunsRead::Resources(parse(payload)?)),
            "runs.cleanups" => Some(RunsRead::Cleanups(parse(payload)?)),
            "runs.previewCleanup" => Some(RunsRead::PreviewCleanup(payload.clone())),
            "runs.cleanup" => Some(RunsRead::Cleanup(parse(payload)?)),
            "runs.integrations" => Some(RunsRead::Integrations(parse(payload)?)),
            "runs.integration" => Some(RunsRead::Integration(parse(payload)?)),
            _ => None,
        };
        if let Some(read) = read {
            self.start_runs_read(client_id, request_id, read)?;
            return Ok(true);
        }
        let actor = self.run_actor(client_id, payload)?;
        match request_type {
            "runs.create" => {
                self.start_run_create(client_id, request_id, payload, actor)?;
            }
            "runs.resolveGate" => {
                let value = self.runs_resolve_gate(payload, &actor).await?;
                self.client_write(client_id, ok_response(request_id, value));
            }
            "runs.control" => {
                require_key(payload, "expectedSequence")?;
                let value = self.runs_control(payload, &actor).await?;
                self.client_write(client_id, ok_response(request_id, value));
            }
            "runs.retryCancellation" => {
                let value = self.runs_retry_cancellation(payload, &actor).await?;
                self.client_write(client_id, ok_response(request_id, value));
            }
            "runs.retryTask" | "runs.retryIntegration" => {
                self.start_run_retry(client_id, request_id, request_type, payload)
                    .await?;
            }
            "runs.applyCleanup" => {
                if payload.get("confirm").and_then(Value::as_bool) != Some(true) {
                    return Err(HostError::format(
                        "applyCleanup requires confirm: true after reviewing the preview",
                    ));
                }
                let confirmed = cleanup_confirmation(payload)?;
                self.start_workflow_cleanup_request(client_id, request_id, &confirmed)?;
            }
            "runs.retryCleanup" => {
                let confirmed = cleanup_confirmation(payload)?;
                self.start_workflow_cleanup_retry(client_id, request_id, &confirmed)?;
            }
            "runs.abandonCleanup" => {
                let confirmed = cleanup_confirmation(payload)?;
                self.start_workflow_cleanup_abandonment(client_id, request_id, &confirmed)?;
            }
            other => return Err(HostError::format(format!("Unknown runs request: {other}"))),
        }
        Ok(true)
    }

    /// Who is acting, decided by the connection: the desktop app, a CLI
    /// process (or the MCP client it names, like inbox questions), or a
    /// paired phone.
    pub(super) fn run_actor(&self, client_id: u64, payload: &Value) -> HostResult<RunActor> {
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| HostError::state("Terminal host client is not authenticated."))?;
        Ok(match client.kind {
            ClientKind::Mobile => RunActor::new(
                RunActorKind::Mobile,
                Some(
                    client
                        .mobile_device_id
                        .clone()
                        .ok_or_else(|| HostError::state("mobile device identity is missing"))?,
                ),
            ),
            ClientKind::Local if client.local_role == LocalClientRole::App => {
                RunActor::new(RunActorKind::Desktop, None)
            }
            ClientKind::Local => match payload.get("externalOrigin").filter(|v| !v.is_null()) {
                Some(origin) => {
                    let name = origin
                        .get("clientName")
                        .or_else(|| origin.get("clientId"))
                        .and_then(Value::as_str)
                        .map(|name| name.chars().take(128).collect::<String>())
                        .filter(|name| !name.trim().is_empty())
                        .ok_or_else(|| {
                            HostError::format("externalOrigin needs a clientName or clientId")
                        })?;
                    RunActor::new(RunActorKind::Mcp, Some(name))
                }
                None => RunActor::new(RunActorKind::Cli, None),
            },
        })
    }

    fn start_runs_read(&self, client_id: u64, request_id: i64, read: RunsRead) -> HostResult<()> {
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| HostError::state("client closed"))?;
        let permit = READ_QUEUE
            .get_or_init(|| Arc::new(Semaphore::new(16)))
            .clone()
            .try_acquire_owned()
            .map_err(|_| HostError::state("runs are busy; retry shortly"))?;
        let store = self.runtime_store.clone();
        let client = client.handle.clone();
        // SQLite uses its worker threads; serialization also stays outside the
        // actor. Bound both concurrent reads and disconnected request lifetime.
        tokio::spawn(async move {
            let _permit = permit;
            let result = tokio::time::timeout(Duration::from_secs(25), async move {
                let _active = READ_SLOTS
                    .get_or_init(|| Arc::new(Semaphore::new(4)))
                    .clone()
                    .acquire_owned()
                    .await
                    .map_err(|_| HostError::state("runs are unavailable"))?;
                read.execute(store).await
            })
            .await
            .unwrap_or_else(|_| Err(HostError::state("runs read timed out")));
            reply(&client, request_id, result);
        });
        Ok(())
    }
}

impl RunsRead {
    async fn execute(self, store: RuntimeStore) -> HostResult<Value> {
        let value = match self {
            Self::Board(query) => to_value(store.orchestration_board_snapshot(&query).await),
            Self::Snapshot(query) => to_value(store.orchestration_run_snapshot(&query).await),
            Self::Task(query) => to_value(store.orchestration_task_inspection(&query).await),
            Self::Timeline(query) => to_value(store.run_timeline(&query).await),
            Self::Source(query) => {
                to_value(store.workflow_source_snapshot(&query.workspace_id).await)
            }
            Self::Plan(query) => store
                .run_plan_view(&query.run_id, query.revision)
                .await
                .map(|plan| json!({ "runId": query.run_id, "plan": plan }))
                .map_err(gate_error),
            Self::Gates(query) => {
                let kind = query
                    .kind
                    .as_deref()
                    .map(|raw| {
                        RunGateKind::parse(raw)
                            .ok_or_else(|| HostError::format(format!("unknown gate kind: {raw}")))
                    })
                    .transpose()?;
                store
                    .run_gates(&RunGateFilter {
                        run_id: query.run_id.clone(),
                        task_id: query.task_id,
                        kind,
                        status: query.status,
                    })
                    .await
                    .map(|items| json!({ "runId": query.run_id, "items": items }))
                    .map_err(gate_error)
            }
            Self::Gate(query) => to_value(store.run_gate_detail(&query.gate_id).await),
            Self::Resources(query) => to_value(store.workflow_cleanup_resources(&query).await),
            Self::Cleanups(query) => to_value(store.workflow_cleanups(&query).await),
            Self::PreviewCleanup(payload) => {
                let selection = serde_json::from_value(payload)
                    .map_err(|_| HostError::format("invalid cleanup selection"))?;
                let runtime = tokio::runtime::Handle::current();
                tokio::task::spawn_blocking(move || {
                    runtime.block_on(crate::managed_workspace::run::cleanup_preview::preview(
                        &store, selection,
                    ))
                })
                .await
                .map_err(|error| HostError::state(error.to_string()))
                .and_then(to_value)
            }
            Self::Cleanup(query) => to_value(store.workflow_cleanup_status(&query.id).await),
            Self::Integrations(query) => {
                to_value(store.workflow_integration_summaries(&query).await)
            }
            Self::Integration(query) => to_value(store.workflow_integration(&query.id).await),
        };
        value
    }
}

fn to_value<T: serde::Serialize>(result: anyhow::Result<T>) -> HostResult<Value> {
    let value = result.map_err(gate_error)?;
    serde_json::to_value(value).map_err(|error| HostError::state(error.to_string()))
}

pub(super) fn parse<T: serde::de::DeserializeOwned>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone())
        .map_err(|error| HostError::format(format!("invalid runs request: {error}")))
}

fn require_key(payload: &Value, key: &str) -> HostResult<()> {
    if payload.get(key).is_none_or(Value::is_null) {
        return Err(HostError::format(format!("{key} is required.")));
    }
    Ok(())
}

/// Cleanup mutations confirm a preview by its id and digest.
fn cleanup_confirmation(payload: &Value) -> HostResult<Value> {
    let field = |key: &str| {
        payload
            .get(key)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty() && value.len() <= 160)
            .ok_or_else(|| HostError::format(format!("cleanup requires the preview {key}")))
    };
    Ok(json!({ "id": field("id")?, "digest": field("digest")? }))
}

fn reply(client: &ClientHandle, id: i64, result: HostResult<Value>) {
    let response = match result {
        Ok(value) => ok_response(id, value),
        Err(error) => error_response(id, &error),
    };
    let _ = client.send_control(ClientFrame::Json(response));
}

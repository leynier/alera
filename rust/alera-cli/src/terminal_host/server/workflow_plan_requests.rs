use std::sync::{Arc, OnceLock};
use std::time::Duration;

use alera_core::runtime::{AgentProfile, PrepareWorkflowPlan, WORKFLOW_PLAN_MAX_BYTES};
use alera_core::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, APPROVAL_MESSAGE_MAX_BYTES,
};
use serde::Deserialize;
use serde_json::Value;
use tokio::sync::Semaphore;

use crate::terminal_host::client::ClientFrame;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::protocol::{error_response, ok_response};

use super::{ClientKind, ServerActor, ServerCommand};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Document {
    document: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PlanQuery {
    run_id: String,
    revision: Option<i64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ChallengeQuery {
    run_id: String,
    revision: i64,
    scope: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DecisionQuery {
    statement: WorkflowApprovalStatement,
    proof: Vec<u8>,
}

enum PlanRequest {
    Prepare(String),
    Get(PlanQuery),
    Challenge(ChallengeQuery),
    Decide(String),
}

impl ServerActor {
    pub(super) fn start_workflow_plan_request(
        &self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<()> {
        self.require_auth(client_id)?;
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| HostError::state("client closed"))?;
        if client.kind != ClientKind::Local {
            return Err(HostError::state(
                "workflow plans require a local desktop host connection",
            ));
        }
        let request = match request_type {
            "workflows.preparePlan" => {
                PlanRequest::Prepare(document(payload, WORKFLOW_PLAN_MAX_BYTES)?)
            }
            "workflows.plan" => PlanRequest::Get(parse(payload)?),
            "workflows.approvalChallenge" => PlanRequest::Challenge(parse(payload)?),
            "workflows.decide" => {
                PlanRequest::Decide(document(payload, APPROVAL_MESSAGE_MAX_BYTES + 256)?)
            }
            _ => return Err(HostError::format("unknown workflow plan request")),
        };
        static QUEUE: OnceLock<Arc<Semaphore>> = OnceLock::new();
        static BOOT: OnceLock<String> = OnceLock::new();
        let permit = QUEUE
            .get_or_init(|| Arc::new(Semaphore::new(8)))
            .clone()
            .try_acquire_owned()
            .map_err(|_| HostError::state("workflow plans are busy; retry shortly"))?;
        let audience = format!(
            "{}:{client_id}",
            BOOT.get_or_init(|| uuid::Uuid::new_v4().to_string())
        );
        let store = self.runtime_store.clone();
        let runtime_dir = self.runtime_dir.clone();
        let client = client.handle.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let _permit = permit;
            let result = tokio::time::timeout(Duration::from_secs(25), async {
                match request {
                    PlanRequest::Prepare(document) => {
                        let request: PrepareWorkflowPlan = serde_json::from_str(&document)
                            .map_err(|_| HostError::format("invalid workflow plan document"))?;
                        serde_json::to_value(
                            store
                                .prepare_workflow_plan(request, validate_profile)
                                .await
                                .map_err(state)?,
                        )
                        .map_err(state)
                    }
                    PlanRequest::Get(query) => serde_json::to_value(
                        store
                            .workflow_plan_revision(&query.run_id, query.revision)
                            .await
                            .map_err(state)?,
                    )
                    .map_err(state),
                    PlanRequest::Challenge(query) => serde_json::to_value(
                        store
                            .workflow_approval_challenge(
                                &query.run_id,
                                query.revision,
                                &query.scope,
                                &audience,
                            )
                            .await
                            .map_err(state)?,
                    )
                    .map_err(state),
                    PlanRequest::Decide(document) => {
                        let input: DecisionQuery = serde_json::from_str(&document)
                            .map_err(|_| HostError::format("invalid workflow decision"))?;
                        if input.proof.len() != 32 {
                            return Err(HostError::state("desktop workflow authorization failed"));
                        }
                        let verified = tokio::task::spawn_blocking(move || {
                            DesktopWorkflowCredential::load_or_create(&runtime_dir)?
                                .verify(input.statement, &input.proof)
                        })
                        .await
                        .map_err(state)?
                        .map_err(|_| HostError::state("desktop workflow authorization failed"))?;
                        serde_json::to_value(
                            store
                                .decide_workflow(verified, &audience)
                                .await
                                .map_err(state)?,
                        )
                        .map_err(state)
                    }
                }
            })
            .await
            .unwrap_or_else(|_| {
                Err(HostError::state(
                    "workflow request timed out; refresh or retry with the same request id",
                ))
            });
            // A timed-out client can still have committed; always reconcile
            // aggregate events against the durable revision, not request success.
            let _ = inbox.send(ServerCommand::WorkflowPlanChanged);
            let response = match result {
                Ok(value) => ok_response(request_id, value),
                Err(error) => error_response(request_id, &error),
            };
            let _ = client.send_control(ClientFrame::Json(response));
        });
        Ok(())
    }
}

fn document(payload: &Value, limit: usize) -> HostResult<String> {
    let raw = payload
        .get("document")
        .and_then(Value::as_str)
        .ok_or_else(|| HostError::format("workflow request requires a document"))?;
    if raw.len() > limit {
        return Err(HostError::format(
            "workflow document exceeds the byte limit",
        ));
    }
    let request: Document = parse(payload)?;
    Ok(request.document)
}

fn parse<T: serde::de::DeserializeOwned>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone())
        .map_err(|_| HostError::format("invalid workflow request"))
}

fn state(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

fn validate_profile(profile: &AgentProfile) -> anyhow::Result<()> {
    if adapter_for(&profile.agent_type).is_none() {
        anyhow::bail!("unsupported workflow agent profile");
    }
    super::orchestration_profile_spawn::launch_for_profile(profile)
        .map_err(|_| anyhow::anyhow!("invalid workflow profile launch configuration"))?;
    Ok(())
}

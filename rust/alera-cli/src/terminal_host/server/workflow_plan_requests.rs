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

#[path = "workflow_coordinator_requests.rs"]
mod coordinator;

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

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ProposalQuery {
    id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ProposalCreation {
    request: PrepareWorkflowPlan,
    expected_source: alera_core::runtime::WorkflowSourceWorkspace,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SourceQuery {
    workspace_id: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ProposalSubmission {
    id: String,
    tasks: Vec<alera_core::runtime::WorkflowPlanTask>,
}

enum PlanRequest {
    Execution(PlanQuery),
    ControlExecution(String),
    CreateCorrection(String),
    Proposals(alera_core::runtime::WorkflowProposalQuery),
    Source(SourceQuery),
    CreateProposal(String),
    Proposal(ProposalQuery),
    ProposalStatus(ProposalQuery),
    CancelProposal(ProposalQuery),
    SubmitProposal(String),
    Prepare(String),
    Get(PlanQuery),
    Challenge(ChallengeQuery),
    Review(ChallengeQuery),
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
            "workflows.execution" => PlanRequest::Execution(parse(payload)?),
            "workflows.controlExecution" => PlanRequest::ControlExecution(document(payload, 4096)?),
            "workflows.createCorrection" => PlanRequest::CreateCorrection(document(payload, 8192)?),
            "workflows.proposals" => PlanRequest::Proposals(parse(payload)?),
            "workflows.source" => PlanRequest::Source(parse(payload)?),
            "workflows.createProposal" => {
                PlanRequest::CreateProposal(document(payload, WORKFLOW_PLAN_MAX_BYTES)?)
            }
            "workflows.proposal" => PlanRequest::Proposal(parse(payload)?),
            "workflows.proposalStatus" => PlanRequest::ProposalStatus(parse(payload)?),
            "workflows.cancelProposal" => PlanRequest::CancelProposal(parse(payload)?),
            "workflows.submitProposal" => {
                PlanRequest::SubmitProposal(document(payload, WORKFLOW_PLAN_MAX_BYTES)?)
            }
            "workflows.preparePlan" => {
                PlanRequest::Prepare(document(payload, WORKFLOW_PLAN_MAX_BYTES)?)
            }
            "workflows.plan" => PlanRequest::Get(parse(payload)?),
            "workflows.approvalChallenge" => PlanRequest::Challenge(parse(payload)?),
            "workflows.review" => PlanRequest::Review(parse(payload)?),
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
                    PlanRequest::CancelProposal(query) => serde_json::to_value(store.cancel_workflow_proposal(&query.id).await.map_err(state)?).map_err(state),
                    PlanRequest::Execution(query) => {
                        let runtime=tokio::runtime::Handle::current();
                        tokio::task::spawn_blocking(move || runtime.block_on(async {
                            serde_json::to_value(store.workflow_run_controls(&query.run_id,query.revision).await?).map_err(anyhow::Error::from)
                        })).await.map_err(state)?.map_err(state)
                    }
                    PlanRequest::ControlExecution(document) => {
                        let request = serde_json::from_str(&document)
                            .map_err(|_| HostError::format("invalid workflow execution command"))?;
                        Ok(serde_json::json!({"execution":store.control_workflow_execution(&request).await.map_err(state)?}))
                    }
                    PlanRequest::CreateCorrection(document) => {
                        let runtime=tokio::runtime::Handle::current();
                        tokio::task::spawn_blocking(move || runtime.block_on(async {
                            let request=serde_json::from_str(&document).map_err(|_|HostError::format("invalid workflow correction document"))?;
                            serde_json::to_value(store.create_workflow_correction(request,validate_profile).await.map_err(state)?).map_err(state)
                        })).await.map_err(state)?
                    }
                    PlanRequest::Proposals(query) => {
                        serde_json::to_value(store.workflow_proposals(query).await.map_err(state)?)
                            .map_err(state)
                    }
                    PlanRequest::Source(query) => serde_json::to_value(
                        store
                            .workflow_source_snapshot(&query.workspace_id)
                            .await
                            .map_err(state)?,
                    )
                    .map_err(state),
                    PlanRequest::CreateProposal(document) => {
                        let input: ProposalCreation = serde_json::from_str(&document)
                            .map_err(|_| HostError::format("invalid workflow proposal document"))?;
                        serde_json::to_value(
                            store
                                .create_workflow_proposal_at_source(
                                    input.request,
                                    validate_profile,
                                    Some(input.expected_source),
                                )
                                .await
                                .map_err(state)?,
                        )
                        .map_err(state)
                    }
                    PlanRequest::Proposal(query) => serde_json::to_value(
                        store.workflow_proposal(&query.id).await.map_err(state)?,
                    )
                    .map_err(state),
                    PlanRequest::ProposalStatus(query) => serde_json::to_value(
                        store
                            .workflow_proposal_status(&query.id)
                            .await
                            .map_err(state)?,
                    )
                    .map_err(state),
                    PlanRequest::SubmitProposal(document) => {
                        let request: ProposalSubmission = serde_json::from_str(&document)
                            .map_err(|_| HostError::format("invalid workflow proposal tasks"))?;
                        serde_json::to_value(
                            store
                                .submit_workflow_proposal(&request.id, request.tasks)
                                .await
                                .map_err(state)?,
                        )
                        .map_err(state)
                    }
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
                    PlanRequest::Review(query) => serde_json::to_value(
                        store
                            .workflow_review(&query.run_id, query.revision, &query.scope, &audience)
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
    if payload.as_object().is_none_or(|fields| {
        fields.len() > 3
            || fields.iter().any(|(key, value)| {
                key.len() > 32
                    || match value {
                        Value::String(text) => {
                            text.len()
                                > if key == "document" {
                                    WORKFLOW_PLAN_MAX_BYTES
                                } else {
                                    160
                                }
                        }
                        Value::Null | Value::Number(_) => false,
                        _ => true,
                    }
            })
    }) {
        return Err(HostError::format("invalid or oversized workflow request"));
    }
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

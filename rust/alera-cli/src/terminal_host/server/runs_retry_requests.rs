//! `runs.retryTask` and `runs.retryIntegration`: retries of an isolated
//! run's attempt or integration that needs attention, run off the actor like
//! the other managed-worktree jobs.

use alera_core::runtime::{IntegrateWorkflowResult, PrepareWorkflowWorkspace};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::orchestration_gate_requests::gate_error;
use super::runs_lifecycle_requests::request_payload;
use super::runs_requests::parse;
use super::{ServerActor, ServerCommand};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RetryRequest {
    request_id: String,
    run_id: String,
    task_id: String,
}

enum RetryJob {
    Attempt(PrepareWorkflowWorkspace),
    Integration(IntegrateWorkflowResult),
}

impl ServerActor {
    /// `runs.retryTask` prepares a fresh attempt for a task whose attempt
    /// needs attention; `runs.retryIntegration` retries an integration that
    /// needs attention. Both require the run to be paused.
    pub(super) async fn start_run_retry(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<()> {
        let request: RetryRequest = parse(&request_payload(payload))?;
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(&request.run_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("run not found: {}", request.run_id)))?;
        if run.isolation != "isolated" {
            return Err(HostError::conflict(
                "run_not_isolated",
                "only isolated runs retry attempts and integrations",
                json!({}),
            ));
        }
        let revision = run
            .plan_revision
            .ok_or_else(|| HostError::state("the run has no plan"))?;
        let inspection = self
            .runtime_store
            .orchestration_task_inspection(&alera_core::runtime::OrchestrationTaskInspectionQuery {
                run_id: request.run_id.clone(),
                task_id: request.task_id.clone(),
                cursor: None,
                limit: Some(1),
            })
            .await
            .map_err(gate_error)?;
        let attempt = inspection
            .attempt
            .ok_or_else(|| HostError::state("the task has no isolated attempt"))?;
        let job = if verb == "runs.retryTask" {
            if !attempt.can_retry {
                return Err(HostError::conflict(
                    "run_retry_unavailable",
                    "pause the run and retry only an attempt that needs attention",
                    json!({}),
                ));
            }
            RetryJob::Attempt(PrepareWorkflowWorkspace {
                request_id: request.request_id,
                run_id: request.run_id,
                revision,
                task_id: Some(request.task_id),
                retry_of: Some(attempt.execution_workspace_id),
            })
        } else {
            if !attempt.can_retry_integration {
                return Err(HostError::conflict(
                    "run_retry_unavailable",
                    "pause the run and retry only an integration that needs attention",
                    json!({}),
                ));
            }
            let integration = self
                .runtime_store
                .workflow_integration(
                    attempt
                        .integration_id
                        .as_deref()
                        .ok_or_else(|| HostError::state("the task has no integration"))?,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            RetryJob::Integration(IntegrateWorkflowResult {
                request_id: attempt
                    .integration_request_id
                    .ok_or_else(|| HostError::state("the integration has no request id"))?,
                run_id: integration.request.run_id,
                revision: integration.request.revision,
                task_id: integration.request.task_id,
                workspace_id: integration.request.source.id,
            })
        };
        self.workflow_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let runtime_dir = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        let runtime = tokio::runtime::Handle::current();
        tokio::spawn(async move {
            let result = tokio::task::spawn_blocking(move || {
                runtime.block_on(async {
                    match job {
                        RetryJob::Attempt(request) => serde_json::to_value(
                            crate::managed_workspace::run::prepare(&store, &runtime_dir, request)
                                .await?,
                        )
                        .map_err(anyhow::Error::from),
                        RetryJob::Integration(request) => serde_json::to_value(
                            crate::managed_workspace::run::integration::integrate(
                                &store,
                                &runtime_dir,
                                request,
                            )
                            .await?,
                        )
                        .map_err(anyhow::Error::from),
                    }
                })
            })
            .await
            .map_err(|error| HostError::state(error.to_string()))
            .and_then(|result| result.map_err(|error| HostError::state(error.to_string())));
            let _ = inbox
                .send_wait(ServerCommand::WorkflowWorkspaceFinished {
                    client_id,
                    request_id,
                    result,
                    mutated: true,
                })
                .await;
        });
        Ok(())
    }
}

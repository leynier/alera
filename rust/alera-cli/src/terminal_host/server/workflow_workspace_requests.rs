use std::sync::{Arc, OnceLock};

use alera_core::runtime::{
    IntegrateWorkflowResult, LaunchWorkflowTask, PrepareWorkflowWorkspace,
    WorkflowIntegrationQuery, WorkflowLaunchQuery, WorkflowWorkspaceQuery,
};
use serde_json::Value;
use tokio::sync::Semaphore;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::{ClientKind, ServerActor, ServerCommand};

#[cfg(test)]
mod tests;

enum Request {
    Launch(LaunchWorkflowTask),
    Launches(WorkflowLaunchQuery),
    Prepare(PrepareWorkflowWorkspace),
    List(WorkflowWorkspaceQuery),
    Integrate(IntegrateWorkflowResult),
    Integrations(WorkflowIntegrationQuery),
    Integration(String),
}

impl ServerActor {
    pub(super) fn start_workflow_workspace_recovery(&mut self) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let directory = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        let runtime = tokio::runtime::Handle::current();
        tokio::spawn(async move {
            let result = tokio::task::spawn_blocking(move || {
                runtime.block_on(async {
                    crate::managed_workspace::workflow::integration::reconcile(&store, &directory)
                        .await?;
                    crate::managed_workspace::workflow::recovery::reconcile(&store, &directory)
                        .await
                })
            })
            .await;
            if !matches!(&result, Ok(Ok(()))) {
                tracing::warn!("workflow workspace recovery needs attention: {result:?}");
            }
            let _ = inbox.send(ServerCommand::WorkflowWorkspaceRecoveryFinished);
        });
    }

    pub(super) fn start_workflow_workspace_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<()> {
        self.require_auth(client_id)?;
        if self
            .clients
            .get(&client_id)
            .is_none_or(|client| client.kind != ClientKind::Local)
        {
            return Err(HostError::state(
                "workflow workspaces require a local host connection",
            ));
        }
        // Reject nested/oversized values before cloning on the actor.
        if payload.as_object().is_none_or(|map| {
            map.len() > 5
                || map.iter().any(|(key, value)| {
                    key.len() > 32
                        || match value {
                            Value::Null | Value::Number(_) => false,
                            Value::String(value) => value.len() > 160,
                            _ => true,
                        }
                })
        }) {
            return Err(HostError::format("invalid workflow workspace request"));
        }
        let request = match verb {
            "workflows.launches" => Request::Launches(
                serde_json::from_value(payload.clone())
                    .map_err(|_| HostError::format("invalid workflow launch query"))?,
            ),
            "workflows.launchTask" => Request::Launch(
                serde_json::from_value(payload.clone())
                    .map_err(|_| HostError::format("invalid workflow launch request"))?,
            ),
            "workflows.prepareWorkspace" => Request::Prepare(
                serde_json::from_value(payload.clone())
                    .map_err(|_| HostError::format("invalid workflow workspace preparation"))?,
            ),
            "workflows.workspaces" => Request::List(
                serde_json::from_value(payload.clone())
                    .map_err(|_| HostError::format("invalid workflow workspace query"))?,
            ),
            "workflows.integrateResult" => Request::Integrate(
                serde_json::from_value(payload.clone())
                    .map_err(|_| HostError::format("invalid workflow integration request"))?,
            ),
            "workflows.integrations" => Request::Integrations(
                serde_json::from_value(payload.clone())
                    .map_err(|_| HostError::format("invalid workflow integration query"))?,
            ),
            "workflows.integration" => {
                if payload.as_object().is_none_or(|map| map.len() != 1) {
                    return Err(HostError::format("integration lookup requires only its id"));
                }
                Request::Integration(
                    payload
                        .get("id")
                        .and_then(Value::as_str)
                        .filter(|id| !id.is_empty())
                        .ok_or_else(|| HostError::format("integration id is required"))?
                        .to_owned(),
                )
            }
            _ => return Err(HostError::format("unknown workflow workspace request")),
        };
        static PREPARATIONS: OnceLock<Arc<Semaphore>> = OnceLock::new();
        static READS: OnceLock<Arc<Semaphore>> = OnceLock::new();
        static INTEGRATIONS: OnceLock<Arc<Semaphore>> = OnceLock::new();
        static LAUNCHES: OnceLock<Arc<Semaphore>> = OnceLock::new();
        // Long project setup commands must not occupy the inspection lane.
        let queue = match &request {
            Request::Launch(_) => &LAUNCHES,
            Request::Prepare(_) => &PREPARATIONS,
            Request::List(_)
            | Request::Integrations(_)
            | Request::Integration(_)
            | Request::Launches(_) => &READS,
            Request::Integrate(_) => &INTEGRATIONS,
        };
        let permit = queue
            .get_or_init(|| Arc::new(Semaphore::new(8)))
            .clone()
            .try_acquire_owned()
            .map_err(|_| HostError::state("workflow workspaces are busy; retry shortly"))?;
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let runtime_dir = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        let runtime = tokio::runtime::Handle::current();
        let mutated = matches!(request, Request::Prepare(_) | Request::Integrate(_));
        tokio::spawn(async move {
            let _permit = permit;
            if let Request::Launch(request) = request {
                let result = tokio::task::spawn_blocking(move || {
                    runtime.block_on(crate::managed_workspace::workflow::launch::prepare(
                        &store,
                        &runtime_dir,
                        request,
                    ))
                })
                .await
                .map_err(|error| HostError::state(error.to_string()))
                .and_then(|result| {
                    result
                        .map(Box::new)
                        .map_err(|error| HostError::state(error.to_string()))
                });
                let _ = inbox.send(ServerCommand::WorkflowLaunch(
                    super::workflow_launch_requests::WorkflowLaunchCommand::Prepared {
                        client_id,
                        request_id,
                        result,
                    },
                ));
                return;
            }
            // Disconnect/timeouts only lose the response. The operation retains
            // its resource lock and durable receipt until it reaches a safe state.
            let result = tokio::task::spawn_blocking(move || {
                runtime.block_on(async {
                    match request {
                        Request::Launches(query) => {
                            serde_json::to_value(store.workflow_launch_summaries(&query).await?)
                                .map_err(anyhow::Error::from)
                        }
                        Request::Launch(_) => unreachable!("launches use their prepared callback"),
                        Request::Prepare(request) => serde_json::to_value(
                            crate::managed_workspace::workflow::prepare(
                                &store,
                                &runtime_dir,
                                request,
                            )
                            .await?,
                        )
                        .map_err(anyhow::Error::from),
                        Request::List(query) => {
                            serde_json::to_value(store.workflow_workspaces(&query).await?)
                                .map_err(anyhow::Error::from)
                        }
                        Request::Integrate(request) => serde_json::to_value(
                            crate::managed_workspace::workflow::integration::integrate(
                                &store,
                                &runtime_dir,
                                request,
                            )
                            .await?,
                        )
                        .map_err(anyhow::Error::from),
                        Request::Integrations(query) => serde_json::to_value(
                            store.workflow_integration_summaries(&query).await?,
                        )
                        .map_err(anyhow::Error::from),
                        Request::Integration(id) => {
                            serde_json::to_value(store.workflow_integration(&id).await?)
                                .map_err(anyhow::Error::from)
                        }
                    }
                })
            })
            .await
            .map_err(|error| HostError::state(error.to_string()))
            .and_then(|result| result.map_err(|error| HostError::state(error.to_string())));
            let _ = inbox.send(ServerCommand::WorkflowWorkspaceFinished {
                client_id,
                request_id,
                result,
                mutated,
            });
        });
        Ok(())
    }

    pub(super) async fn handle_workflow_workspace_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
        mutated: bool,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        match result {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
        if mutated {
            self.broadcast_workspaces_changed(None);
            self.broadcast_orchestration_board_change().await;
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn handle_workflow_workspace_recovery_finished(&mut self) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        self.broadcast_workspaces_changed(None);
        self.broadcast_orchestration_board_change().await;
        self.schedule_shutdown_if_idle();
    }
}

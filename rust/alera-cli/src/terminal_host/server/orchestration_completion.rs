use std::sync::{Arc, OnceLock};

use alera_core::runtime::{OrchestrationDispatchContext, OrchestrationDispatchStatus};
use serde_json::{json, Value};
use tokio::sync::Semaphore;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::orchestration_validation::state_error;
use super::{ServerActor, ServerCommand};

struct WorkflowCompletionCheck {
    repo_path: String,
    path: String,
    base_sha: String,
    workspace_id: String,
}

enum CompletionPreparation {
    Legacy,
    KnownSha(String),
    Verify(WorkflowCompletionCheck),
}

pub(crate) struct OrchestrationCompletionFinished {
    pub client_id: u64,
    pub request_id: i64,
    pub dispatch_id: String,
    pub assignee: String,
    pub result: String,
    pub completion_sha: HostResult<String>,
}

impl ServerActor {
    pub(super) async fn complete_or_defer_dispatch_result(
        &mut self,
        client_id: u64,
        request_id: i64,
        dispatch: &OrchestrationDispatchContext,
        assignee: &str,
        result: String,
    ) -> HostResult<Option<Value>> {
        match self.workflow_completion_preparation(dispatch).await? {
            CompletionPreparation::Legacy => {
                let completed = self
                    .runtime_store
                    .complete_orchestration_dispatch(&dispatch.id, assignee, &result)
                    .await
                    .map_err(state_error)?;
                self.apply_terminal_completion_policy(assignee, &completed.terminal_policy)
                    .await?;
                Ok(Some(completion_response(&completed)))
            }
            CompletionPreparation::KnownSha(sha) => {
                let completed = self
                    .runtime_store
                    .complete_workflow_orchestration_dispatch(&dispatch.id, assignee, &result, &sha)
                    .await
                    .map_err(state_error)?;
                self.apply_terminal_completion_policy(assignee, &completed.terminal_policy)
                    .await?;
                Ok(Some(completion_response(&completed)))
            }
            CompletionPreparation::Verify(check) => {
                self.start_workflow_completion_check(
                    client_id,
                    request_id,
                    dispatch.id.clone(),
                    assignee.to_owned(),
                    result,
                    check,
                )?;
                Ok(None)
            }
        }
    }

    async fn workflow_completion_preparation(
        &self,
        dispatch: &OrchestrationDispatchContext,
    ) -> HostResult<CompletionPreparation> {
        if let Some(sha) = dispatch.completion_sha.clone() {
            return Ok(CompletionPreparation::KnownSha(sha));
        }
        let Some(terminal) = dispatch.assignee_handle.as_deref() else {
            return Ok(CompletionPreparation::Legacy);
        };
        let Some(launch) = self
            .runtime_store
            .workflow_launch_for_terminal(terminal)
            .await
            .map_err(state_error)?
        else {
            return Ok(CompletionPreparation::Legacy);
        };
        if launch.dispatch_id != dispatch.id {
            return Err(HostError::state(
                "workflow completion dispatch identity changed",
            ));
        }
        let workspace = self
            .runtime_store
            .workflow_workspace(&launch.request.workspace_id)
            .await
            .map_err(state_error)?;
        if workspace.dispatch_id.as_deref() != Some(dispatch.id.as_str()) {
            return Err(HostError::state(
                "workflow completion workspace identity changed",
            ));
        }
        Ok(CompletionPreparation::Verify(WorkflowCompletionCheck {
            repo_path: workspace.identity.repo_path,
            path: workspace.identity.workspace.path,
            base_sha: workspace.identity.base_sha,
            workspace_id: workspace.identity.workspace.id,
        }))
    }

    fn start_workflow_completion_check(
        &self,
        client_id: u64,
        request_id: i64,
        dispatch_id: String,
        assignee: String,
        result: String,
        check: WorkflowCompletionCheck,
    ) -> HostResult<()> {
        static COMPLETIONS: OnceLock<Arc<Semaphore>> = OnceLock::new();
        let permit = COMPLETIONS
            .get_or_init(|| Arc::new(Semaphore::new(8)))
            .clone()
            .try_acquire_owned()
            .map_err(|_| HostError::state("workflow completions are busy; retry shortly"))?;
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let _permit = permit;
            let completion_sha = tokio::task::spawn_blocking(move || verify_completion(check))
                .await
                .map_err(|error| HostError::state(error.to_string()))
                .and_then(|result| result);
            let _ = inbox.send(ServerCommand::OrchestrationCompletionFinished(
                OrchestrationCompletionFinished {
                    client_id,
                    request_id,
                    dispatch_id,
                    assignee,
                    result,
                    completion_sha,
                },
            ));
        });
        Ok(())
    }

    pub(super) async fn handle_orchestration_completion_finished(
        &mut self,
        completion: OrchestrationCompletionFinished,
    ) {
        let result = match completion.completion_sha {
            Err(error) => Err(error),
            Ok(sha) => match self
                .runtime_store
                .orchestration_dispatch_by_id(&completion.dispatch_id)
                .await
                .map_err(state_error)
            {
                Err(error) => Err(error),
                Ok(None) => Err(HostError::state(
                    "workflow completion dispatch no longer exists",
                )),
                Ok(Some(dispatch))
                    if dispatch.status != OrchestrationDispatchStatus::Dispatched
                        && dispatch.status != OrchestrationDispatchStatus::Completed =>
                {
                    Err(HostError::state(
                        "workflow completion dispatch is no longer active",
                    ))
                }
                Ok(Some(_)) => self
                    .runtime_store
                    .complete_workflow_orchestration_dispatch(
                        &completion.dispatch_id,
                        &completion.assignee,
                        &completion.result,
                        &sha,
                    )
                    .await
                    .map_err(state_error),
            },
        };
        match result {
            Ok(completed) => {
                let response = match self
                    .apply_terminal_completion_policy(
                        &completion.assignee,
                        &completed.terminal_policy,
                    )
                    .await
                {
                    Ok(()) => ok_response(completion.request_id, completion_response(&completed)),
                    Err(error) => error_response(completion.request_id, &error),
                };
                self.client_write(completion.client_id, response);
            }
            Err(error) => self.client_write(
                completion.client_id,
                error_response(completion.request_id, &error),
            ),
        }
        self.broadcast_orchestration_board_change().await;
    }
}

fn verify_completion(check: WorkflowCompletionCheck) -> HostResult<String> {
    let sha = alera_core::git::verify_workflow_worktree_tip(
        &check.repo_path,
        &check.path,
        &check.base_sha,
        &check.workspace_id,
    )
    .map_err(|error| HostError::state(error.to_string()))?;
    if !alera_core::git::is_worktree_clean(&check.path)
        .map_err(|error| HostError::state(error.to_string()))?
    {
        return Err(HostError::state(
            "commit or discard pending changes before completing the workflow task",
        ));
    }
    Ok(sha)
}

fn completion_response(completed: &OrchestrationDispatchContext) -> Value {
    json!({
        "delivered": true,
        "lifecycleAccepted": true,
        "taskId": completed.task_id,
        "dispatchId": completed.id,
        "taskStatus": "completed",
        "dispatchStatus": completed.status.as_str(),
    })
}

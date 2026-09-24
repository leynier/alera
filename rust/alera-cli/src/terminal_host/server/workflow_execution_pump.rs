use std::{collections::HashMap, path::PathBuf};

use alera_core::runtime::{RuntimeStore, WorkflowExecutionState, WorkflowExecutionStep};
use tokio::sync::mpsc::UnboundedSender;

use super::{ServerActor, WorkflowLaunchCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::ServerCommand;

#[cfg(test)]
#[path = "workflow_execution_pump_tests.rs"]
mod tests;

#[derive(Default)]
pub(in crate::terminal_host) struct ExecutionPump {
    pub(in crate::terminal_host::server) ready: bool,
    pub(in crate::terminal_host::server) cancelling: bool,
    pub(in crate::terminal_host::server) cancellation_dirty: bool,
    pub(in crate::terminal_host::server) cancellation_shutdowns:
        HashMap<String, crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown>,
    busy: bool,
    dirty: bool,
    cursor: Option<String>,
}

impl ExecutionPump {
    fn settle_page(&mut self, cursor: Option<String>, again: bool) -> bool {
        self.busy = false;
        self.cursor = cursor;
        let dirty = self.cursor.is_none() && std::mem::take(&mut self.dirty);
        again || dirty
    }
}

pub(crate) struct ExecutionPass {
    cursor: Option<String>,
    again: bool,
    changed: bool,
    error: Option<String>,
}

impl ServerActor {
    pub(in crate::terminal_host::server) fn wake_workflow_execution(&mut self) {
        if self.disposed || !self.workflow_execution.ready {
            return;
        }
        self.wake_workflow_cancellation();
        if self.workflow_execution.busy {
            self.workflow_execution.dirty = true;
            return;
        }
        self.workflow_execution.busy = true;
        self.workflow_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let directory = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        let cursor = self.workflow_execution.cursor.take();
        let runtime = tokio::runtime::Handle::current();
        tokio::spawn(async move {
            let destination = inbox.clone();
            let result = tokio::task::spawn_blocking(move || {
                runtime.block_on(pass(store, directory, destination, cursor))
            })
            .await;
            let pass = match result {
                Ok(Ok(pass)) => pass,
                Ok(Err(error)) => ExecutionPass {
                    cursor: None,
                    again: false,
                    changed: false,
                    error: Some(error.to_string()),
                },
                Err(error) => ExecutionPass {
                    cursor: None,
                    again: false,
                    changed: false,
                    error: Some(error.to_string()),
                },
            };
            let _ = inbox.send(ServerCommand::WorkflowLaunch(
                WorkflowLaunchCommand::ExecutionFinished(pass),
            ));
        });
    }

    pub(in crate::terminal_host::server) async fn finish_workflow_execution_pass(
        &mut self,
        pass: ExecutionPass,
    ) {
        self.workflow_workspace_jobs = self.workflow_workspace_jobs.saturating_sub(1);
        let should_wake = self.workflow_execution.settle_page(pass.cursor, pass.again);
        if let Some(error) = pass.error {
            tracing::warn!("workflow execution pass stopped: {error}");
        }
        if pass.changed {
            self.broadcast_workspaces_changed(None);
        }
        self.broadcast_orchestration_board_change().await;
        if should_wake {
            self.wake_workflow_execution();
        }
        self.schedule_shutdown_if_idle();
    }
}

async fn pass(
    store: RuntimeStore,
    directory: PathBuf,
    inbox: UnboundedSender<ServerCommand>,
    cursor: Option<String>,
) -> anyhow::Result<ExecutionPass> {
    let runs = store.workflow_execution_page(cursor.as_deref()).await?;
    for run in &runs {
        let step = store
            .workflow_execution_step(&run.run_id, run.revision)
            .await;
        let result = match step {
            Ok(WorkflowExecutionStep::Waiting) => continue,
            Ok(WorkflowExecutionStep::Complete) => store
                .complete_workflow_execution(&run.run_id, run.revision, run.sequence)
                .await
                .map(|_| ()),
            Ok(WorkflowExecutionStep::Attention { reason }) => Err(anyhow::anyhow!(reason)),
            Ok(step) => execute(&store, &directory, &inbox, run, step).await,
            Err(error) => Err(error),
        };
        if let Err(error) = result {
            store
                .pause_workflow_execution_for_attention(
                    &run.run_id,
                    run.revision,
                    run.sequence,
                    &error.to_string(),
                )
                .await?;
        }
        return Ok(ExecutionPass {
            cursor: Some(run.run_id.clone()),
            again: true,
            changed: true,
            error: None,
        });
    }
    // A fresh cycle scans from the beginning only after a durable change or
    // progress. Waiting for a gate/completion does not create a polling loop.
    Ok(ExecutionPass {
        cursor: if runs.len() == 25 {
            runs.last().map(|run| run.run_id.clone())
        } else {
            None
        },
        again: runs.len() == 25,
        changed: false,
        error: None,
    })
}

async fn execute(
    store: &RuntimeStore,
    directory: &std::path::Path,
    inbox: &UnboundedSender<ServerCommand>,
    run: &WorkflowExecutionState,
    step: WorkflowExecutionStep,
) -> anyhow::Result<()> {
    let current = store.workflow_execution(&run.run_id).await?;
    if current.is_none_or(|current| {
        current.revision != run.revision
            || current.sequence != run.sequence
            || current.status != "running"
    }) {
        return Ok(());
    }
    match step {
        WorkflowExecutionStep::PrepareWorkspace(request) => {
            crate::managed_workspace::workflow::prepare(store, directory, request).await?;
        }
        WorkflowExecutionStep::IntegrateResult(request) => {
            crate::managed_workspace::workflow::integration::integrate(store, directory, request)
                .await?;
        }
        WorkflowExecutionStep::LaunchTask(request) => {
            let result =
                crate::managed_workspace::workflow::launch::prepare(store, directory, request)
                    .await
                    .map(Box::new)
                    .map_err(|error| HostError::state(error.to_string()));
            let (reply, done) = tokio::sync::oneshot::channel::<HostResult<serde_json::Value>>();
            inbox
                .send(ServerCommand::WorkflowLaunch(
                    WorkflowLaunchCommand::ExecutionPrepared { reply, result },
                ))
                .map_err(|_| anyhow::anyhow!("runtime closed before workflow launch"))?;
            done.await
                .map_err(|_| anyhow::anyhow!("runtime closed during workflow launch"))?
                .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
        }
        _ => {}
    }
    Ok(())
}

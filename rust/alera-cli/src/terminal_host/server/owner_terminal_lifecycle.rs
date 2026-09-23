use alera_core::runtime::{
    TerminalLifecycleAction, TerminalLifecycleOperation, Workspace, LOCAL_HOST_ID,
};
use serde::Deserialize;
use serde_json::{json, Value};

use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, event, ok_response};
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

pub(super) const OPERATION: &str = "terminal.ownerLifecycle";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Request {
    operation_id: String,
    workspace: Workspace,
    tab_id: String,
    session_id: String,
    action: TerminalLifecycleAction,
}

impl Request {
    fn matches(&self, operation: &TerminalLifecycleOperation) -> bool {
        self.operation_id == operation.id
            && self.tab_id == operation.tab_id
            && self.session_id == operation.session_id
            && self.action == operation.action
            && same_checkout(&self.workspace, &operation.workspace)
    }
}

fn same_checkout(left: &Workspace, right: &Workspace) -> bool {
    left.id == right.id
        && left.instance_id == right.instance_id
        && left.project_id == right.project_id
        && left.host_id == right.host_id
        && left.path == right.path
        && left.kind == right.kind
}

impl ServerActor {
    pub(super) async fn start_owner_terminal_lifecycle(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        self.require_authenticated_local_request(client_id, OPERATION)?;
        let request: Request = serde_json::from_value(payload.clone())
            .map_err(|error| HostError::format(error.to_string()))?;
        if request.workspace.host_id != LOCAL_HOST_ID
            || uuid::Uuid::parse_str(&request.operation_id).is_err()
        {
            return Err(HostError::state(
                "An owner-local task and stable terminal operation UUID are required",
            ));
        }
        if let Some(saved) = self
            .runtime_store
            .terminal_lifecycle_operation(&request.operation_id)
            .await
            .map_err(state_error)?
        {
            if !request.matches(&saved) {
                return Err(HostError::state(
                    "The terminal operation belongs to another task, tab or action",
                ));
            }
            if !saved.closure_verified {
                if let Some(shutdown) = self.pending_terminal_lifecycle_shutdowns.remove(&saved.id)
                {
                    self.wait_owner_terminal_lifecycle(client_id, request_id, saved, shutdown);
                    return Ok(());
                }
                return Err(HostError::state(
                    "The terminal operation is pending; process closure remains unverified",
                ));
            }
            self.client_write(
                client_id,
                ok_response(
                    request_id,
                    json!({"operation":saved,"processClosureVerified":true}),
                ),
            );
            return Ok(());
        }
        let workspace = self
            .runtime_store
            .find_workspace(&request.workspace.id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| {
                HostError::state("The owner task is missing; terminal closure is unverified")
            })?;
        if !same_checkout(&workspace, &request.workspace) {
            return Err(HostError::state(
                "The owner task identity or checkout changed",
            ));
        }
        if !self.sessions.contains_key(&request.session_id) {
            let operation = TerminalLifecycleOperation {
                id: request.operation_id,
                workspace,
                tab_id: request.tab_id,
                session_id: request.session_id,
                session_generation: 1,
                initiator_epoch: Some(
                    match request.action {
                        TerminalLifecycleAction::Close => "never-started-close",
                        TerminalLifecycleAction::Restart => "never-started-restart",
                    }
                    .into(),
                ),
                action: request.action,
                closure_verified: false,
            };
            self.runtime_store
                .begin_never_started_terminal_operation(&operation)
                .await
                .map_err(state_error)?;
            let completed = self
                .runtime_store
                .complete_terminal_lifecycle_operation(&operation)
                .await
                .map_err(state_error)?;
            self.client_write(
                client_id,
                ok_response(
                    request_id,
                    json!({"operation":completed,"processClosureVerified":true}),
                ),
            );
            return Ok(());
        }
        let session = self.sessions.get(&request.session_id).ok_or_else(|| {
            HostError::state("The owner session is unavailable; terminal closure is unverified")
        })?;
        if session.workspace_id != workspace.id || session.tab_id != request.tab_id {
            return Err(HostError::state(
                "The owner terminal belongs to another task or tab",
            ));
        }
        let natural = self
            .runtime_store
            .terminal_lifecycle_for_generation(
                &request.session_id,
                session.instance_id(),
                Some(super::owner_terminal_natural_exit::natural_exit_epoch()),
                TerminalLifecycleAction::Restart,
            )
            .await
            .map_err(state_error)?;
        let shutdown = if natural.as_ref().is_some_and(|receipt| {
            receipt.closure_verified && same_checkout(&receipt.workspace, &workspace)
        }) {
            WorkspaceShutdown::default()
        } else if !session.running() {
            return Err(HostError::state(
                "Natural terminal exit has no verified process closure evidence",
            ));
        } else {
            WorkspaceShutdown::capture(std::iter::once(session)).await?
        };
        let operation = TerminalLifecycleOperation {
            id: request.operation_id,
            workspace,
            tab_id: request.tab_id,
            session_id: request.session_id.clone(),
            session_generation: session.instance_id(),
            initiator_epoch: None,
            action: request.action,
            closure_verified: false,
        };
        self.runtime_store
            .begin_terminal_lifecycle_operation(&operation)
            .await
            .map_err(state_error)?;
        self.disarm_terminal_pulse(&request.session_id);
        self.cleanup_orchestration_for_closed_session(
            &request.session_id,
            "terminal owner received an explicit lifecycle action",
        )
        .await;
        self.flush_all_output(&request.session_id);
        self.await_output_writes(&request.session_id).await;
        if let Some(mut session) = self.sessions.remove(&request.session_id) {
            let clients = session.clients.iter().copied().collect::<Vec<_>>();
            session.terminate(true, &self.store).await;
            for client in clients {
                self.client_write(
                    client,
                    event(
                        "terminalSessionRemoved",
                        json!({"sessionId":request.session_id}),
                    ),
                );
            }
        }
        self.wait_owner_terminal_lifecycle(client_id, request_id, operation, shutdown);
        Ok(())
    }

    pub(super) fn wait_owner_terminal_lifecycle(
        &mut self,
        client_id: u64,
        request_id: i64,
        operation: TerminalLifecycleOperation,
        mut shutdown: WorkspaceShutdown,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = async {
                shutdown.wait().await?;
                let completed = store
                    .complete_terminal_lifecycle_operation(&operation)
                    .await
                    .map_err(state_error)?;
                Ok(json!({"operation":completed,"processClosureVerified":true}))
            }
            .await;
            let _ = inbox.send(ServerCommand::OwnerTerminalLifecycleFinished {
                client_id,
                request_id,
                operation_id: operation.id,
                shutdown,
                result,
            });
        });
    }

    pub(super) async fn finish_owner_terminal_lifecycle(
        &mut self,
        client_id: u64,
        request_id: i64,
        operation_id: String,
        shutdown: WorkspaceShutdown,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        if result.is_err() {
            self.pending_terminal_lifecycle_shutdowns
                .insert(operation_id, shutdown);
        }
        if self
            .require_authenticated_local_request(client_id, OPERATION)
            .is_ok()
            && self
                .require_shared_checkout_support(client_id, OPERATION)
                .is_ok()
        {
            match result {
                Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
                Err(error) => self.client_write(client_id, error_response(request_id, &error)),
            }
        }
        self.schedule_shutdown_if_idle();
    }
}

fn state_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

#[cfg(test)]
#[path = "owner_terminal_lifecycle_tests.rs"]
mod tests;

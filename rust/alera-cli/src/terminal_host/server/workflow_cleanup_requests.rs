use super::{ClientKind, ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::Value;

enum CleanupOperation {
    Apply,
    Retry,
    Abandon,
}

impl ServerActor {
    pub(super) fn start_workflow_cleanup_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        self.start_workflow_cleanup_operation(
            client_id,
            request_id,
            payload,
            CleanupOperation::Apply,
        )
    }

    pub(super) fn start_workflow_cleanup_retry(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        self.start_workflow_cleanup_operation(
            client_id,
            request_id,
            payload,
            CleanupOperation::Retry,
        )
    }

    pub(super) fn start_workflow_cleanup_abandonment(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        self.start_workflow_cleanup_operation(
            client_id,
            request_id,
            payload,
            CleanupOperation::Abandon,
        )
    }

    fn start_workflow_cleanup_operation(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
        operation: CleanupOperation,
    ) -> HostResult<()> {
        self.require_auth(client_id)?;
        if self
            .clients
            .get(&client_id)
            .is_none_or(|client| client.kind != ClientKind::Local)
        {
            return Err(HostError::state(
                "workflow cleanup requires a local host connection",
            ));
        }
        let map = payload
            .as_object()
            .filter(|map| map.len() == 2)
            .ok_or_else(|| HostError::format("cleanup requires only its preview id and digest"))?;
        let field = |key| {
            map.get(key)
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 160)
                .ok_or_else(|| HostError::format("invalid cleanup confirmation"))
        };
        let id = field("id")?.to_owned();
        let digest = field("digest")?.to_owned();
        uuid::Uuid::parse_str(&id).map_err(|_| HostError::format("invalid cleanup preview id"))?;
        let permit = super::workflow_cleanup_execution::cleanup_queue()
            .try_acquire_owned()
            .map_err(|_| HostError::state("cleanup is busy; retry shortly"))?;
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let directory = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        let runtime = tokio::runtime::Handle::current();
        tokio::spawn(async move {
            let events = inbox.clone();
            let result = tokio::task::spawn_blocking(move || {
                let _permit = permit;
                runtime.block_on(async {
                    match operation {
                        CleanupOperation::Abandon => {
                            super::workflow_cleanup_execution::abandon(
                                &store, &directory, &events, &id, &digest,
                            )
                            .await
                        }
                        operation => {
                            super::workflow_cleanup_execution::execute(
                                &store,
                                &directory,
                                &events,
                                &id,
                                &digest,
                                matches!(operation, CleanupOperation::Retry),
                            )
                            .await
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
                mutated: true,
            });
        });
        Ok(())
    }
}

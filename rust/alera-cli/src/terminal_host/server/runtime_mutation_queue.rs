use std::collections::{HashMap, VecDeque};

use crate::terminal_host::host_error::HostError;
use crate::terminal_host::protocol::error_response;
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

use super::runtime_mutations::{
    run_runtime_mutation, RuntimeMutationFinished, RuntimeMutationOutcome, RuntimeMutationRequest,
};
use super::{ServerActor, ServerCommand};

const MAX_MUTATIONS: usize = 256;

struct QueuedMutation {
    client_id: u64,
    request_id: i64,
    mutation: RuntimeMutationRequest,
}

#[derive(Default)]
pub(super) struct RuntimeMutationQueue {
    active: bool,
    #[cfg(test)]
    parked: bool,
    pending: VecDeque<QueuedMutation>,
    in_flight: usize,
    file_writes: usize,
    pub(super) pending_workspace_shutdowns: HashMap<String, WorkspaceShutdown>,
}

impl RuntimeMutationQueue {
    pub(super) fn outstanding(&self) -> usize {
        usize::from(self.active) + self.pending.len() + self.file_writes
    }

    pub(super) fn has_runtime_mutations(&self) -> bool {
        self.in_flight > 0
    }
}

impl ServerActor {
    pub(super) fn begin_workspace_file_write(&mut self) {
        self.cancel_shutdown_timer();
        self.mutation_queue.file_writes += 1;
        self.mutation_queue.in_flight += 1;
    }

    pub(super) fn complete_workspace_file_write(&mut self) {
        self.mutation_queue.file_writes = self.mutation_queue.file_writes.saturating_sub(1);
        self.mutation_queue.in_flight = self.mutation_queue.in_flight.saturating_sub(1);
        self.start_next_runtime_mutation();
        self.schedule_shutdown_if_idle();
    }

    pub(super) fn start_runtime_mutation(
        &mut self,
        client_id: u64,
        request_id: i64,
        mutation: RuntimeMutationRequest,
    ) {
        if self.mutation_queue.outstanding() >= MAX_MUTATIONS {
            self.finish_checkout_buffer_guard(client_id, request_id, false);
            let error = HostError::state(
                "A runtime mutation is already in progress. Wait for it to finish and retry.",
            );
            self.client_write(client_id, error_response(request_id, &error));
            return;
        }
        self.cancel_shutdown_timer();
        self.mutation_queue.in_flight += 1;
        self.mutation_queue.pending.push_back(QueuedMutation {
            client_id,
            request_id,
            mutation,
        });
        self.start_next_runtime_mutation();
    }

    pub(super) fn complete_runtime_mutation(&mut self) {
        self.mutation_queue.in_flight = self.mutation_queue.in_flight.saturating_sub(1);
        self.mutation_queue.active = false;
        self.start_next_runtime_mutation();
        self.schedule_shutdown_if_idle();
    }

    pub(super) fn cancel_queued_runtime_mutations(&mut self, client_id: u64) {
        let before = self.mutation_queue.pending.len();
        self.mutation_queue
            .pending
            .retain(|queued| queued.client_id != client_id);
        let removed = before - self.mutation_queue.pending.len();
        self.mutation_queue.in_flight = self.mutation_queue.in_flight.saturating_sub(removed);
    }

    #[cfg(test)]
    #[allow(dead_code)]
    pub(super) fn park_runtime_mutations(&mut self) {
        self.mutation_queue.parked = true;
    }

    #[cfg(test)]
    #[allow(dead_code)]
    pub(super) fn unpark_runtime_mutations(&mut self) {
        self.mutation_queue.parked = false;
        self.start_next_runtime_mutation();
    }

    fn start_next_runtime_mutation(&mut self) {
        if self.mutation_queue.active || self.mutation_queue.file_writes > 0 {
            return;
        }
        #[cfg(test)]
        if self.mutation_queue.parked {
            return;
        }
        loop {
            let Some(request) = self.mutation_queue.pending.pop_front() else {
                return;
            };
            if !self.clients.contains_key(&request.client_id) {
                self.mutation_queue.in_flight = self.mutation_queue.in_flight.saturating_sub(1);
                continue;
            }
            self.mutation_queue.active = true;
            self.spawn_runtime_mutation(request);
            return;
        }
    }

    fn spawn_runtime_mutation(&self, mut request: QueuedMutation) {
        let runtime_store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let mut prepared = match &request.mutation {
                RuntimeMutationRequest::RemoveManagedWorkspace { .. }
                | RuntimeMutationRequest::RemoveSharedWorkspace { .. }
                | RuntimeMutationRequest::HandOnWorkspace { .. }
                | RuntimeMutationRequest::HandOffWorkspace { .. }
                | RuntimeMutationRequest::RemoveWorkspace { .. }
                | RuntimeMutationRequest::RemoveProject { .. }
                | RuntimeMutationRequest::RemoveProjectWorkspaces { .. } => {
                    let (completion, receiver) = tokio::sync::oneshot::channel();
                    let _ = inbox.send(ServerCommand::PrepareRuntimeMutation {
                        request: request.mutation.clone(),
                        completion,
                    });
                    receiver.await.unwrap_or_else(|_| {
                        Err(HostError::state("Runtime stopped before workspace cleanup"))
                    })
                }
                _ => Ok(WorkspaceShutdown::default()),
            };
            if prepared.is_ok() {
                let remote = async {
                    let RuntimeMutationRequest::RemoveSharedWorkspace {
                        request: removal,
                        automation_cleanup,
                        buffer_guard,
                        remote_retirement,
                        ..
                    } = &mut request.mutation
                    else {
                        return Ok(false);
                    };
                    if !buffer_guard.is_remote() {
                        return Ok(false);
                    }
                    let workspace = runtime_store
                        .find_workspace(&removal.id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?
                        .ok_or_else(|| {
                            HostError::state("Workspace disappeared before remote retirement")
                        })?;
                    buffer_guard.verify_workspace(&workspace)?;
                    let proof = if let Some(run) = automation_cleanup {
                        crate::remote_shared_retirement::retire_automation(
                            &runtime_store,
                            &workspace,
                            run,
                            &crate::ssh_remote::LiveSshRemoteHost,
                        )
                        .await
                    } else {
                        crate::remote_shared_retirement::retire(
                            &runtime_store,
                            &workspace,
                            &crate::ssh_remote::LiveSshRemoteHost,
                        )
                        .await
                    }
                    .map_err(|error| HostError::state(error.to_string()))?;
                    buffer_guard.verify()?;
                    *remote_retirement = Some(proof);
                    Ok::<_, HostError>(true)
                }
                .await;
                match remote {
                    Ok(true) => {
                        let (completion, receiver) = tokio::sync::oneshot::channel();
                        let _ = inbox.send(ServerCommand::PrepareRuntimeMutation {
                            request: request.mutation.clone(),
                            completion,
                        });
                        prepared = receiver.await.unwrap_or_else(|_| Err(HostError::state("Runtime stopped after remote retirement; retry to recover the owner receipt")));
                    }
                    Ok(false) => {}
                    Err(error) => prepared = Err(error),
                }
            }
            let mut stopped_workspace_tab_ids = Vec::new();
            let mut pending_workspace_shutdown = None;
            let prepared = match prepared {
                Ok(mut shutdown) => {
                    stopped_workspace_tab_ids = std::mem::take(&mut shutdown.closed_tab_ids);
                    let result = shutdown.wait().await;
                    if result.is_err() {
                        let shutdown_workspace_id = match &request.mutation {
                            RuntimeMutationRequest::RemoveManagedWorkspace { request }
                            | RuntimeMutationRequest::RemoveSharedWorkspace { request, .. } => {
                                Some(request.id.clone())
                            }
                            RuntimeMutationRequest::HandOnWorkspace { request, .. } => {
                                Some(request.id.clone())
                            }
                            _ => None,
                        };
                        if let Some(workspace_id) = shutdown_workspace_id {
                            pending_workspace_shutdown = Some(Box::new((workspace_id, shutdown)));
                        }
                    }
                    result
                }
                Err(error) => Err(error),
            };
            let mut outcome = match prepared {
                Ok(()) => run_runtime_mutation(runtime_store, request.mutation).await,
                Err(error) => RuntimeMutationOutcome {
                    result: Err(error),
                    ended_pointer_tab_ids: Vec::new(),
                    closed_session_tab_ids: Vec::new(),
                    committed_tab_ids: Vec::new(),
                    effect_on_error: None,
                    stopped_workspace_tab_ids: Vec::new(),
                    pending_workspace_shutdown: None,
                },
            };
            outcome.stopped_workspace_tab_ids = stopped_workspace_tab_ids;
            outcome.pending_workspace_shutdown = pending_workspace_shutdown;
            let _ = inbox.send(ServerCommand::RuntimeMutationFinished(
                RuntimeMutationFinished {
                    client_id: request.client_id,
                    request_id: request.request_id,
                    outcome,
                },
            ));
        });
    }
}

#[cfg(test)]
mod file_write_tests {
    use super::super::actor_test_harness::test_actor;
    use super::*;

    #[tokio::test]
    async fn file_writes_hold_queued_lifecycle_mutations_until_completion() {
        let root = tempfile::tempdir().unwrap();
        let mut actor = test_actor(&root, HashMap::new(), HashMap::new()).await;
        actor.begin_workspace_file_write();
        assert!(actor.mutation_queue.has_runtime_mutations());
        assert_eq!(actor.mutation_queue.outstanding(), 1);
        actor.start_runtime_mutation(
            99,
            1,
            RuntimeMutationRequest::RemoveWorkspace {
                workspace_id: "retired-client-task".into(),
                cascade_tabs: true,
            },
        );
        assert_eq!(actor.mutation_queue.pending.len(), 1);
        assert!(!actor.mutation_queue.active);
        actor.handle_mobile_workspace_file_finished(
            99,
            2,
            "mobile.workspaceSearch.replace",
            Ok(serde_json::json!({})),
        );
        assert!(actor.mutation_queue.pending.is_empty());
        assert!(!actor.mutation_queue.has_runtime_mutations());
    }
}

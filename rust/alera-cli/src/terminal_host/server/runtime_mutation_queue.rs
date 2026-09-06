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
    pub(super) pending_workspace_shutdowns: HashMap<String, WorkspaceShutdown>,
}

impl RuntimeMutationQueue {
    pub(super) fn outstanding(&self) -> usize {
        usize::from(self.active) + self.pending.len()
    }

    pub(super) fn has_runtime_mutations(&self) -> bool {
        self.in_flight > 0
    }
}

impl ServerActor {
    pub(super) fn start_runtime_mutation(
        &mut self,
        client_id: u64,
        request_id: i64,
        mutation: RuntimeMutationRequest,
    ) {
        if self.mutation_queue.outstanding() >= MAX_MUTATIONS {
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
        if self.mutation_queue.active {
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

    fn spawn_runtime_mutation(&self, request: QueuedMutation) {
        let runtime_store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let prepared = match &request.mutation {
                RuntimeMutationRequest::RemoveManagedWorkspace { .. }
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
            let mut stopped_workspace_tab_ids = Vec::new();
            let mut pending_workspace_shutdown = None;
            let prepared = match prepared {
                Ok(mut shutdown) => {
                    stopped_workspace_tab_ids = std::mem::take(&mut shutdown.closed_tab_ids);
                    let result = shutdown.wait().await;
                    if result.is_err() {
                        if let RuntimeMutationRequest::RemoveManagedWorkspace { request } =
                            &request.mutation
                        {
                            pending_workspace_shutdown =
                                Some(Box::new((request.id.clone(), shutdown)));
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

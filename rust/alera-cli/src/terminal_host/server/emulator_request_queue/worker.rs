use super::*;
use crate::terminal_host::server::emulator_requests::run_emulator_request;
use crate::terminal_host::server::runtime_mutations::{
    run_runtime_mutation, RuntimeMutationFinished, RuntimeMutationOutcome,
};

impl ServerActor {
    pub(super) fn spawn_emulator_request(&self, request: QueuedEmulatorRequest) {
        let manager = self.emulators.clone();
        let runtime_store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            match request.operation {
                QueuedOperation::Emulator {
                    request_type,
                    payload,
                } => {
                    let completion = run_emulator_request(
                        manager,
                        runtime_store,
                        request.client_id,
                        &request_type,
                        &payload,
                    )
                    .await;
                    let _ = inbox.send(ServerCommand::EmulatorRequestFinished {
                        client_id: request.client_id,
                        request_id: request.request_id,
                        completion,
                    });
                }
                QueuedOperation::RuntimeMutation {
                    mutation,
                    codex_cleanup,
                } => {
                    // Only owner removal needs this actor round trip. The
                    // queue keeps replacement sessions behind the barrier.
                    let prepared = match &mutation {
                        RuntimeMutationRequest::RemoveManagedWorkspace { .. }
                        | RuntimeMutationRequest::RemoveWorkspace { .. }
                        | RuntimeMutationRequest::RemoveProject { .. }
                        | RuntimeMutationRequest::RemoveProjectWorkspaces { .. } => {
                            let (completion, receiver) = tokio::sync::oneshot::channel();
                            let _ = inbox.send(ServerCommand::PrepareRuntimeMutation {
                                request: mutation.clone(),
                                completion,
                            });
                            receiver.await.unwrap_or_else(|_| {
                                Err(HostError::state("Runtime stopped before workspace cleanup"))
                            })
                        }
                        _ => Ok(crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown::default()),
                    };
                    let mut stopped_workspace_tab_ids = Vec::new();
                    let mut pending_workspace_shutdown = None;
                    let prepared = match prepared {
                        Ok(mut shutdown) => {
                            stopped_workspace_tab_ids =
                                std::mem::take(&mut shutdown.closed_tab_ids);
                            let result = shutdown.wait().await;
                            if result.is_err() {
                                if let RuntimeMutationRequest::RemoveManagedWorkspace { request } =
                                    &mutation
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
                        Ok(()) => {
                            run_runtime_mutation(manager, runtime_store, mutation, codex_cleanup)
                                .await
                        }
                        Err(error) => RuntimeMutationOutcome {
                            result: Err(error),
                            pending_codex_cleanup: Vec::new(),
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
                }
                QueuedOperation::ParkAll => {
                    let changed_emulators = if let Some(manager) = manager {
                        let mut manager = manager.lock_owned().await;
                        let scopes = manager.session_scopes();
                        manager.park_all().await;
                        scopes
                    } else {
                        Vec::new()
                    };
                    send_maintenance(&inbox, true, Vec::new(), true, changed_emulators);
                }
                QueuedOperation::ReleaseClients {
                    client_ids,
                    park_all,
                } => {
                    let changed_emulators = if let Some(manager) = manager {
                        let mut manager = manager.lock_owned().await;
                        let scopes = manager.session_scopes();
                        for client_id in &client_ids {
                            manager.release_client(*client_id, false).await;
                        }
                        if park_all {
                            manager.park_all().await;
                        }
                        scopes
                    } else {
                        Vec::new()
                    };
                    send_maintenance(&inbox, park_all, client_ids, false, changed_emulators);
                }
                QueuedOperation::CancelPointer { tab_id, client_id } => {
                    if let Some(manager) = manager {
                        manager
                            .lock_owned()
                            .await
                            .cancel_pointer(&tab_id, client_id)
                            .await;
                    }
                    send_maintenance(&inbox, false, Vec::new(), false, Vec::new());
                }
            }
        });
    }
}

fn send_maintenance(
    inbox: &tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    clear_all_pointers: bool,
    released_client_ids: Vec<u64>,
    completed_park_all: bool,
    changed_emulators: Vec<(String, String)>,
) {
    let _ = inbox.send(ServerCommand::EmulatorMaintenanceFinished(
        EmulatorMaintenanceCompletion {
            clear_all_pointers,
            released_client_ids,
            completed_park_all,
            changed_emulators,
        },
    ));
}

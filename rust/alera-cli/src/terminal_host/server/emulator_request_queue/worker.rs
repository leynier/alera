use super::*;
use crate::terminal_host::server::emulator_requests::run_emulator_request;
use crate::terminal_host::server::runtime_mutations::run_runtime_mutation;

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
                QueuedOperation::RuntimeMutation(mutation) => {
                    let outcome = run_runtime_mutation(manager, runtime_store, mutation).await;
                    let _ = inbox.send(ServerCommand::RuntimeMutationFinished(
                        crate::terminal_host::server::runtime_mutations::RuntimeMutationFinished {
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

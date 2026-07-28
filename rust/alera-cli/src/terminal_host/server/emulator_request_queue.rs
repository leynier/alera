use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::terminal_host::emulator::EmulatorFailure;
use crate::terminal_host::host_error::HostError;
use crate::terminal_host::protocol::{error_response, ok_response};

use super::emulator_request_payloads::{EmulatorRequestCompletion, PointerTransition};
use super::runtime_mutations::RuntimeMutationRequest;
use super::{ServerActor, ServerCommand};

#[cfg(test)]
mod maintenance_tests;
mod selection;
mod worker;
use selection::*;

const MAX_EMULATOR_REQUESTS: usize = 256;
const MAX_QUEUED_POINTER_MOVES: usize = 240;
const MAX_REQUESTS_WITH_POINTER_END: usize = MAX_EMULATOR_REQUESTS + 1;
const MAX_INTERACTIVE_QUEUE_AGE: Duration = Duration::from_secs(2);
const ACTIVE_POINTER_TIMEOUT: Duration = Duration::from_secs(30);

pub(super) struct QueuedEmulatorRequest {
    client_id: u64,
    request_id: i64,
    operation: QueuedOperation,
    queued_at: Instant,
}

pub(crate) struct EmulatorMaintenanceCompletion {
    pub(super) clear_all_pointers: bool,
    pub(super) released_client_ids: Vec<u64>,
    pub(super) completed_park_all: bool,
    pub(super) changed_emulators: Vec<(String, String)>,
}

enum QueuedOperation {
    Emulator {
        request_type: String,
        payload: Value,
    },
    RuntimeMutation(RuntimeMutationRequest),
    ParkAll,
    ReleaseClients {
        client_ids: Vec<u64>,
        park_all: bool,
    },
    CancelPointer {
        tab_id: String,
        client_id: u64,
    },
}

#[derive(Default)]
pub(super) struct EmulatorRequestQueue {
    active: bool,
    pending: VecDeque<QueuedEmulatorRequest>,
    runtime_mutations: usize,
    park_all_outstanding: bool,
    pub(super) active_pointers: HashMap<String, ActivePointerState>,
    next_pointer_generation: u64,
}

#[derive(Clone, Copy)]
pub(super) struct ActivePointerState {
    pub(super) client_id: u64,
    pub(super) generation: u64,
}

impl EmulatorRequestQueue {
    pub(super) fn outstanding(&self) -> usize {
        usize::from(self.active) + self.pending.len()
    }

    pub(super) fn has_runtime_mutations(&self) -> bool {
        self.runtime_mutations > 0
    }
}

impl ServerActor {
    pub(super) fn start_emulator_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: String,
        payload: Value,
    ) {
        let request = QueuedEmulatorRequest {
            client_id,
            request_id,
            operation: QueuedOperation::Emulator {
                request_type,
                payload,
            },
            queued_at: Instant::now(),
        };
        let Some(request) = self.coalesce_pointer_move(request) else {
            return;
        };
        let limit = if is_pointer_move(&request) {
            MAX_QUEUED_POINTER_MOVES
        } else if is_pointer_end(&request) {
            MAX_REQUESTS_WITH_POINTER_END
        } else {
            MAX_EMULATOR_REQUESTS
        };
        if self.emulator_requests.outstanding() >= limit {
            self.write_emulator_busy(client_id, request_id);
            return;
        }
        self.cancel_shutdown_timer();
        self.emulator_requests.pending.push_back(request);
        self.start_next_emulator_request();
    }

    pub(super) fn start_runtime_mutation(
        &mut self,
        client_id: u64,
        request_id: i64,
        mutation: RuntimeMutationRequest,
    ) {
        if self.emulator_requests.outstanding() >= MAX_EMULATOR_REQUESTS {
            let error = HostError::state(
                "The emulator request queue is busy. Wait for the current emulator operation to finish and retry.",
            );
            self.client_write(client_id, error_response(request_id, &error));
            return;
        }
        self.cancel_shutdown_timer();
        self.emulator_requests.runtime_mutations += 1;
        self.emulator_requests
            .pending
            .push_back(QueuedEmulatorRequest {
                client_id,
                request_id,
                operation: QueuedOperation::RuntimeMutation(mutation),
                queued_at: Instant::now(),
            });
        self.start_next_emulator_request();
    }

    pub(super) fn queue_emulator_park_all(&mut self) {
        self.emulator_requests.active_pointers.clear();
        if self.emulator_requests.park_all_outstanding {
            return;
        }
        self.emulator_requests.park_all_outstanding = true;
        self.cancel_shutdown_timer();
        self.emulator_requests
            .pending
            .push_front(QueuedEmulatorRequest {
                client_id: 0,
                request_id: 0,
                operation: QueuedOperation::ParkAll,
                queued_at: Instant::now(),
            });
        self.start_next_emulator_request();
    }

    pub(super) fn queue_emulator_client_release(&mut self, client_id: u64, park_all: bool) {
        if let Some(QueuedEmulatorRequest {
            operation:
                QueuedOperation::ReleaseClients {
                    client_ids,
                    park_all: queued_park_all,
                },
            ..
        }) = self.emulator_requests.pending.back_mut()
        {
            client_ids.push(client_id);
            *queued_park_all |= park_all;
            return;
        }
        self.cancel_shutdown_timer();
        self.emulator_requests
            .pending
            .push_back(QueuedEmulatorRequest {
                client_id,
                request_id: 0,
                operation: QueuedOperation::ReleaseClients {
                    client_ids: vec![client_id],
                    park_all,
                },
                queued_at: Instant::now(),
            });
        self.start_next_emulator_request();
    }

    fn queue_emulator_pointer_cancel(&mut self, tab_id: String, client_id: u64) {
        self.cancel_shutdown_timer();
        self.emulator_requests
            .pending
            .push_front(QueuedEmulatorRequest {
                client_id,
                request_id: 0,
                operation: QueuedOperation::CancelPointer { tab_id, client_id },
                queued_at: Instant::now(),
            });
        self.start_next_emulator_request();
    }

    pub(super) fn handle_emulator_request_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        completion: EmulatorRequestCompletion,
    ) {
        self.emulator_requests.active = false;
        if let Some(transition) = completion.pointer_transition {
            self.apply_pointer_transition(transition);
        }
        if let Some(broadcast) = completion.broadcast {
            if broadcast.workspace_tabs_changed {
                self.broadcast_workspace_tabs_changed(Some(&broadcast.workspace_id));
            }
            self.broadcast_mobile_emulator_changed(
                Some(&broadcast.tab_id),
                Some(&broadcast.workspace_id),
                broadcast.reason,
            );
        }
        self.client_write(client_id, ok_response(request_id, completion.response));
        self.start_next_emulator_request();
        self.schedule_shutdown_if_idle();
    }

    pub(super) fn complete_emulator_queue_operation(&mut self) {
        self.emulator_requests.active = false;
        self.start_next_emulator_request();
        self.schedule_shutdown_if_idle();
    }

    pub(super) fn complete_runtime_mutation(&mut self) {
        self.emulator_requests.runtime_mutations =
            self.emulator_requests.runtime_mutations.saturating_sub(1);
        self.complete_emulator_queue_operation();
    }

    pub(super) fn handle_emulator_maintenance_finished(
        &mut self,
        completion: EmulatorMaintenanceCompletion,
    ) {
        let EmulatorMaintenanceCompletion {
            clear_all_pointers,
            released_client_ids,
            completed_park_all,
            changed_emulators,
        } = completion;
        if completed_park_all {
            self.emulator_requests.park_all_outstanding = false;
        }
        if clear_all_pointers {
            self.emulator_requests.active_pointers.clear();
        } else if !released_client_ids.is_empty() {
            self.emulator_requests
                .active_pointers
                .retain(|_, pointer| !released_client_ids.contains(&pointer.client_id));
        }
        for (tab_id, workspace_id) in changed_emulators {
            self.broadcast_mobile_emulator_changed(Some(&tab_id), Some(&workspace_id), "parked");
        }
        self.complete_emulator_queue_operation();
    }

    pub(super) fn cancel_queued_emulator_requests(&mut self, client_id: u64) {
        let cancelled_runtime_mutations = self
            .emulator_requests
            .pending
            .iter()
            .filter(|request| request.client_id == client_id && is_runtime_mutation(request))
            .count();
        self.emulator_requests
            .pending
            .retain(|request| request.client_id != client_id);
        self.emulator_requests.runtime_mutations = self
            .emulator_requests
            .runtime_mutations
            .saturating_sub(cancelled_runtime_mutations);
        self.emulator_requests
            .active_pointers
            .retain(|_, pointer| pointer.client_id != client_id);
        if !self.emulator_requests.active {
            self.start_next_emulator_request();
        }
    }

    fn coalesce_pointer_move(
        &mut self,
        request: QueuedEmulatorRequest,
    ) -> Option<QueuedEmulatorRequest> {
        if !is_pointer_move(&request) {
            return Some(request);
        }
        let should_replace = self.emulator_requests.pending.back().is_some_and(|queued| {
            queued.client_id == request.client_id
                && is_pointer_move(queued)
                && same_tab(queued, &request)
        });
        if should_replace {
            let queued = self
                .emulator_requests
                .pending
                .back_mut()
                .expect("the pointer move tail was present");
            let (client_id, request_id) = (queued.client_id, queued.request_id);
            *queued = request;
            self.client_write(
                client_id,
                ok_response(request_id, json!({"ok": true, "coalesced": true})),
            );
            return None;
        }
        Some(request)
    }

    pub(super) fn start_next_emulator_request(&mut self) {
        if self.emulator_requests.active {
            return;
        }
        loop {
            let next_index = if self.emulator_requests.active_pointers.is_empty() {
                (!self.emulator_requests.pending.is_empty()).then_some(0)
            } else {
                self.emulator_requests
                    .pending
                    .iter()
                    .position(|request| self.is_owned_pointer_request(request))
                    .or_else(|| {
                        self.emulator_requests
                            .pending
                            .iter()
                            .position(can_bypass_active_pointer)
                    })
            };
            let Some(next_index) = next_index else {
                return;
            };
            let request = self
                .emulator_requests
                .pending
                .remove(next_index)
                .expect("the selected emulator request was present");
            if requires_live_client(&request) && !self.clients.contains_key(&request.client_id) {
                if is_runtime_mutation(&request) {
                    self.emulator_requests.runtime_mutations =
                        self.emulator_requests.runtime_mutations.saturating_sub(1);
                }
                continue;
            }
            if is_interactive(&request) && request.queued_at.elapsed() > MAX_INTERACTIVE_QUEUE_AGE {
                self.write_emulator_busy(request.client_id, request.request_id);
                continue;
            }
            self.emulator_requests.active = true;
            self.spawn_emulator_request(request);
            return;
        }
    }

    fn is_owned_pointer_request(&self, request: &QueuedEmulatorRequest) -> bool {
        let Some((request_type, payload)) = emulator_operation(request) else {
            return false;
        };
        let Some(tab_id) = payload.get("tabId").and_then(Value::as_str) else {
            return false;
        };
        self.emulator_requests
            .active_pointers
            .get(tab_id)
            .is_some_and(|pointer| {
                pointer.client_id == request.client_id
                    && matches!(pointer_kind(request_type, payload), Some("move" | "end"))
            })
    }

    fn apply_pointer_transition(&mut self, transition: PointerTransition) {
        match transition {
            PointerTransition::Began { tab_id, client_id }
                if self.clients.contains_key(&client_id) =>
            {
                self.emulator_requests.next_pointer_generation = self
                    .emulator_requests
                    .next_pointer_generation
                    .wrapping_add(1);
                let generation = self.emulator_requests.next_pointer_generation;
                self.emulator_requests.active_pointers.insert(
                    tab_id.clone(),
                    ActivePointerState {
                        client_id,
                        generation,
                    },
                );
                let inbox = self.inbox.clone();
                tokio::spawn(async move {
                    tokio::time::sleep(ACTIVE_POINTER_TIMEOUT).await;
                    let _ = inbox.send(ServerCommand::EmulatorPointerTimeout {
                        tab_id,
                        client_id,
                        generation,
                    });
                });
            }
            PointerTransition::Ended { tab_id, client_id }
                if self
                    .emulator_requests
                    .active_pointers
                    .get(&tab_id)
                    .is_some_and(|pointer| pointer.client_id == client_id) =>
            {
                self.emulator_requests.active_pointers.remove(&tab_id);
            }
            _ => {}
        }
    }

    pub(super) fn handle_emulator_pointer_timeout(
        &mut self,
        tab_id: &str,
        client_id: u64,
        generation: u64,
    ) {
        let current = self
            .emulator_requests
            .active_pointers
            .get(tab_id)
            .is_some_and(|pointer| {
                pointer.client_id == client_id && pointer.generation == generation
            });
        if !current {
            return;
        }
        self.emulator_requests.active_pointers.remove(tab_id);
        self.queue_emulator_pointer_cancel(tab_id.to_string(), client_id);
    }

    fn write_emulator_busy(&self, client_id: u64, request_id: i64) {
        let failure = EmulatorFailure::new(
            "emulator_busy",
            "The emulator request queue is busy.",
            ["Wait for the current emulator operation to finish and retry."],
        );
        self.client_write(client_id, ok_response(request_id, failure.to_json()));
    }
}

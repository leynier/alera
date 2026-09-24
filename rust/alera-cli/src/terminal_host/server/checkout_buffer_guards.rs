use std::collections::{HashMap, HashSet};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::client_delivery::LocalClientRole;
use super::{ClientKind, ServerActor, ServerCommand};

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct BufferGuardScope {
    pub(super) tab_ids: Vec<String>,
    pub(super) workspace_paths: Vec<String>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct BufferGuardBlocker {
    tab_id: String,
    path: String,
    reason: String,
}

pub(super) struct CheckoutBufferGuard {
    pub(super) owner: u64,
    pub(super) project_id: String,
    pub(super) host_id: String,
    pub(super) workspace_id: String,
    pub(super) workspace_instance_id: String,
    pub(super) workspace_path: String,
    pub(super) operation: String,
    pub(super) scope: BufferGuardScope,
    pub(super) participants: HashMap<u64, Option<Vec<BufferGuardBlocker>>>,
    pub(super) disconnected: HashSet<u64>,
    pub(super) claimed_request_id: Option<i64>,
    pub(super) started: bool,
    pub(super) valid: Arc<AtomicBool>,
}

impl CheckoutBufferGuard {
    pub(super) fn status(&self, id: &str) -> Value {
        let pending = self
            .participants
            .values()
            .filter(|ack| ack.is_none())
            .count();
        let blockers: Vec<_> = self.participants.iter().flat_map(|(client, ack)| {
            ack.iter().flatten().map(move |blocker| json!({"clientId": client, "tabId": blocker.tab_id, "path": blocker.path, "reason": blocker.reason}))
        }).collect();
        self.valid.store(
            pending == 0 && blockers.is_empty() && self.disconnected.is_empty(),
            Ordering::SeqCst,
        );
        json!({"guardId": id, "workspaceId": self.workspace_id, "workspaceInstanceId": self.workspace_instance_id, "operation": self.operation,
            "ready": pending == 0 && blockers.is_empty() && self.disconnected.is_empty(),
            "pendingClients": pending, "disconnectedClients": self.disconnected.len(), "blockers": blockers})
    }
}

impl ServerActor {
    pub(super) fn buffer_guard_hello(&mut self, client_id: u64) -> Vec<Value> {
        let Some(client) = self.clients.get(&client_id) else {
            return Vec::new();
        };
        if client.kind != ClientKind::Local || client.local_role != LocalClientRole::App {
            return Vec::new();
        }
        self.checkout_buffer_guards
            .iter_mut()
            .map(|(id, guard)| {
                guard.participants.insert(client_id, None);
                guard.valid.store(false, Ordering::SeqCst);
                json!({"guardId": id, "scope": guard.scope})
            })
            .collect()
    }

    pub(super) fn acknowledge_buffer_guard(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let id = super::requests::require_string_key(payload, "guardId")?;
        let guard = self
            .checkout_buffer_guards
            .get_mut(&id)
            .ok_or_else(|| HostError::state("The buffer guard is no longer active"))?;
        let participant = guard.participants.get_mut(&client_id).ok_or_else(|| {
            HostError::state("This client does not own a buffer acknowledgement for this guard")
        })?;
        let blockers: Vec<BufferGuardBlocker> = serde_json::from_value(
            payload
                .get("blockers")
                .cloned()
                .ok_or_else(|| HostError::format("Buffer blockers are required"))?,
        )
        .map_err(|error| HostError::format(error.to_string()))?;
        if blockers.len() > 1024
            || blockers.iter().any(|blocker| {
                blocker.path.len() > 8192
                    || blocker.reason.len() > 1024
                    || blocker.tab_id.len() > 256
            })
        {
            return Err(HostError::format(
                "Buffer acknowledgement exceeds its limits",
            ));
        }
        // A dirty or busy answer remains a blocker for this attempt. Requiring
        // a new preparation avoids replacing a newer state with a delayed ack.
        if participant.is_some() {
            return Err(HostError::state(
                "This client already acknowledged the buffer guard",
            ));
        }
        *participant = Some(blockers);
        Ok(guard.status(&id))
    }

    pub(super) fn release_checkout_buffer_guard(&mut self, id: &str) {
        self.release_checkout_buffer_guard_with_outcome(id, false);
    }

    pub(super) fn release_checkout_buffer_guard_with_outcome(&mut self, id: &str, retired: bool) {
        if let Some(guard) = self.checkout_buffer_guards.remove(id) {
            guard.valid.store(false, Ordering::SeqCst);
            for client_id in guard.participants.keys() {
                self.client_write(
                    *client_id,
                    event(
                        "checkoutBuffersReleased",
                        json!({"guardId": id, "retired": retired}),
                    ),
                );
            }
        }
    }

    pub(super) fn disconnect_buffer_guard_client(&mut self, client_id: u64) {
        let owned: Vec<_> = self
            .checkout_buffer_guards
            .iter()
            .filter(|(_, guard)| guard.owner == client_id && !guard.started)
            .map(|(id, _)| id.clone())
            .collect();
        for id in owned {
            self.release_checkout_buffer_guard(&id);
        }
        for guard in self.checkout_buffer_guards.values_mut() {
            if guard.participants.contains_key(&client_id) || guard.owner == client_id {
                guard.disconnected.insert(client_id);
                guard.valid.store(false, Ordering::SeqCst);
            }
        }
    }

    pub(super) async fn checkout_buffer_guard_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_authenticated_local_request(client_id, request_type)?;
        match request_type {
            "workspace.bufferGuard.acquire" => {
                self.acquire_checkout_buffer_guard(client_id, payload).await
            }
            "workspace.bufferGuard.ack" => self.acknowledge_buffer_guard(client_id, payload),
            "workspace.bufferGuard.status" | "workspace.bufferGuard.release" => {
                let id = super::requests::require_string_key(payload, "guardId")?;
                if request_type.ends_with(".release")
                    && !self.checkout_buffer_guards.contains_key(&id)
                {
                    return Ok(json!({"guardId": id, "released": true}));
                }
                let guard = self.checkout_buffer_guards.get(&id).ok_or_else(|| {
                    HostError::state(
                        "The buffer guard is no longer active; prepare the operation again",
                    )
                })?;
                if guard.owner != client_id {
                    return Err(HostError::state(
                        "Only the preparing client can inspect or release this buffer guard",
                    ));
                }
                let status = guard.status(&id);
                if request_type.ends_with(".release") {
                    if guard.started {
                        return Err(HostError::state(
                            "Buffer guards remain held until the workspace operation finishes",
                        ));
                    }
                    self.release_checkout_buffer_guard(&id);
                }
                Ok(status)
            }
            _ => Err(HostError::format("Unknown buffer guard operation")),
        }
    }

    async fn acquire_checkout_buffer_guard(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let workspace_id = super::requests::require_string_key(payload, "id")?;
        let operation = super::requests::require_string_key(payload, "operation")?;
        if !matches!(
            operation.as_str(),
            "removeShared" | "removeManaged" | "handOff" | "handOn"
        ) {
            return Err(HostError::format("Choose a supported workspace operation"));
        }
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("Workspace not found"))?;
        if payload
            .get("expectedInstanceId")
            .and_then(Value::as_str)
            .is_some_and(|expected| expected != workspace.instance_id)
        {
            return Err(HostError::state(
                "Workspace identity changed; no operation was prepared",
            ));
        }
        if self.checkout_buffer_guards.values().any(|guard| {
            guard.project_id == workspace.project_id && guard.host_id == workspace.host_id
        }) {
            return Err(HostError::state(
                "Another workspace operation is awaiting buffer verification on this project and host",
            ));
        }
        let participants: HashMap<_, _> = self.clients.iter().filter(|(_, client)| client.authenticated && client.kind == ClientKind::Local && client.local_role == LocalClientRole::App)
            .map(|(id, client)| {
                if !client.checkout_buffer_guards { return Err(HostError::state(format!("Desktop client {id} must update or disconnect before buffer safety can be verified"))); }
                Ok((*id, None))
            }).collect::<HostResult<_>>()?;
        let scope = self.checkout_buffer_scope(&workspace, &operation).await?;
        if self.checkout_buffer_guards.values().any(|guard| {
            guard.host_id == workspace.host_id
                && guard
                    .scope
                    .workspace_paths
                    .iter()
                    .any(|path| scope.workspace_paths.contains(path))
        }) {
            return Err(HostError::state(
                "Another operation is verifying buffers on the same physical checkout",
            ));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let guard = CheckoutBufferGuard {
            owner: client_id,
            project_id: workspace.project_id,
            host_id: workspace.host_id,
            workspace_id,
            workspace_instance_id: workspace.instance_id,
            workspace_path: workspace.path,
            operation,
            scope,
            participants,
            disconnected: HashSet::new(),
            claimed_request_id: None,
            started: false,
            valid: Arc::new(AtomicBool::new(false)),
        };
        let status = guard.status(&id);
        for participant in guard.participants.keys() {
            self.client_write(
                *participant,
                event(
                    "checkoutBuffersLock",
                    json!({"guardId": id, "scope": guard.scope}),
                ),
            );
        }
        self.checkout_buffer_guards.insert(id.clone(), guard);
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(30)).await;
            let _ = inbox.send(ServerCommand::BufferGuardExpired { id });
        });
        Ok(status)
    }

    async fn checkout_buffer_scope(
        &self,
        workspace: &alera_core::runtime::Workspace,
        operation: &str,
    ) -> HostResult<BufferGuardScope> {
        let mut workspace_ids = HashSet::from([workspace.id.clone()]);
        let mut paths = HashSet::new();
        if matches!(operation, "handOff" | "handOn" | "removeManaged") {
            let binding = self
                .runtime_store
                .find_workspace_checkout(&workspace.id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| HostError::state("Workspace checkout is unavailable"))?;
            let mut checkout_ids = HashSet::from([binding.id]);
            paths.insert(binding.path);
            if operation == "handOn" {
                let checkout = self
                    .runtime_store
                    .find_project_checkout(&workspace.project_id, &workspace.host_id)
                    .await
                    .map_err(state_error)?
                    .ok_or_else(|| {
                        HostError::state("Project checkout is not registered on this host")
                    })?;
                checkout_ids.insert(checkout.id);
                paths.insert(checkout.path);
            }
            for candidate in self
                .runtime_store
                .list_workspaces(&workspace.project_id)
                .await
                .map_err(state_error)?
            {
                if candidate.host_id != workspace.host_id {
                    continue;
                }
                if self
                    .runtime_store
                    .find_workspace_checkout(&candidate.id)
                    .await
                    .map_err(state_error)?
                    .is_some_and(|binding| checkout_ids.contains(&binding.id))
                {
                    workspace_ids.insert(candidate.id);
                    paths.insert(candidate.path);
                }
            }
        }
        let mut tab_ids = Vec::new();
        for workspace_id in workspace_ids {
            tab_ids.extend(
                self.runtime_store
                    .list_workspace_tabs(&workspace_id)
                    .await
                    .map_err(state_error)?
                    .into_iter()
                    .map(|tab| tab.id),
            );
        }
        // SSH editor surfaces are read-only; their path strings must never
        // freeze an unrelated local checkout with the same spelling.
        if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
            paths.clear();
        }
        tab_ids.sort();
        let mut workspace_paths: Vec<_> = paths.into_iter().collect();
        workspace_paths.sort();
        Ok(BufferGuardScope {
            tab_ids,
            workspace_paths,
        })
    }
}

fn state_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

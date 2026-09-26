use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

#[derive(Clone, Debug)]
pub(crate) struct CheckoutBufferGuardProof {
    pub(super) id: String,
    valid: Arc<AtomicBool>,
    workspace_id: String,
    instance_id: String,
    project_id: String,
    host_id: String,
    path: String,
}

impl CheckoutBufferGuardProof {
    pub(super) fn is_remote(&self) -> bool {
        self.host_id != alera_core::runtime::LOCAL_HOST_ID
    }
    pub(super) fn verify_workspace(
        &self,
        workspace: &alera_core::runtime::Workspace,
    ) -> HostResult<()> {
        self.verify()?;
        if workspace.id != self.workspace_id
            || workspace.instance_id != self.instance_id
            || workspace.project_id != self.project_id
            || workspace.host_id != self.host_id
            || workspace.path != self.path
        {
            return Err(HostError::state(
                "Workspace identity or location changed after buffer verification",
            ));
        }
        Ok(())
    }
    pub(super) fn verify(&self) -> HostResult<()> {
        if !self.valid.load(Ordering::SeqCst) {
            return Err(HostError::state(
                "Editor buffer verification changed or disconnected. The workspace was preserved; prepare the operation again.",
            ));
        }
        Ok(())
    }
}

impl ServerActor {
    pub(super) fn claim_checkout_buffer_guard(
        &mut self,
        client_id: u64,
        request_id: i64,
        workspace_id: &str,
        operation: &str,
        payload: &serde_json::Value,
    ) -> HostResult<CheckoutBufferGuardProof> {
        let id = payload.get("bufferGuardId").and_then(serde_json::Value::as_str).ok_or_else(|| HostError::state("Prepare this operation with workspace.bufferGuard.acquire and wait for clean editor acknowledgements before retrying with bufferGuardId."))?;
        let guard = self.checkout_buffer_guards.get_mut(id).ok_or_else(|| {
            HostError::state("Buffer verification expired; prepare the operation again")
        })?;
        if guard.owner != client_id
            || guard.workspace_id != workspace_id
            || guard.operation != operation
            || guard.claimed_request_id.is_some()
        {
            return Err(HostError::state(
                "Buffer verification does not belong to this client and workspace operation",
            ));
        }
        if guard.status(id)["ready"] != true {
            return Err(HostError::state(
                "All connected editors must acknowledge clean, frozen buffers before this operation can continue",
            ));
        }
        guard.claimed_request_id = Some(request_id);
        Ok(CheckoutBufferGuardProof {
            id: id.to_string(),
            valid: guard.valid.clone(),
            workspace_id: guard.workspace_id.clone(),
            instance_id: guard.workspace_instance_id.clone(),
            project_id: guard.project_id.clone(),
            host_id: guard.host_id.clone(),
            path: guard.workspace_path.clone(),
        })
    }

    pub(super) async fn start_checkout_buffer_guard(
        &mut self,
        proof: &CheckoutBufferGuardProof,
    ) -> HostResult<()> {
        proof.verify()?;
        let guard = self.checkout_buffer_guards.get(&proof.id).ok_or_else(|| {
            HostError::state("Buffer verification expired before the operation started")
        })?;
        let workspace_id = guard.workspace_id.clone();
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("Workspace disappeared during buffer verification"))?;
        if workspace.instance_id != guard.workspace_instance_id
            || workspace.path != guard.workspace_path
            || workspace.project_id != guard.project_id
            || workspace.host_id != guard.host_id
        {
            return Err(HostError::state(
                "Workspace identity or location changed during buffer verification. Prepare the operation again.",
            ));
        }
        let guarded_tabs = guard.scope.tab_ids.clone();
        let current_tabs = self
            .runtime_store
            .list_workspace_tabs(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if current_tabs
            .iter()
            .any(|tab| !guarded_tabs.contains(&tab.id))
        {
            return Err(HostError::state(
                "Workspace tabs changed during buffer verification. Prepare the operation again.",
            ));
        }
        proof.verify()?;
        if let Some(guard) = self.checkout_buffer_guards.get_mut(&proof.id) {
            guard.started = true;
        }
        Ok(())
    }

    pub(super) fn finish_checkout_buffer_guard(
        &mut self,
        client_id: u64,
        request_id: i64,
        succeeded: bool,
    ) {
        let ids: Vec<_> = self
            .checkout_buffer_guards
            .iter()
            .filter(|(_, guard)| {
                guard.owner == client_id && guard.claimed_request_id == Some(request_id)
            })
            .map(|(id, _)| id.clone())
            .collect();
        for id in ids {
            let retired = succeeded
                && self.checkout_buffer_guards.get(&id).is_some_and(|guard| {
                    matches!(guard.operation.as_str(), "removeShared" | "removeManaged")
                });
            self.release_checkout_buffer_guard_with_outcome(&id, retired);
        }
    }

    pub(super) fn expire_checkout_buffer_guard(&mut self, id: &str) {
        if self
            .checkout_buffer_guards
            .get(id)
            .is_some_and(|guard| !guard.started)
        {
            self.release_checkout_buffer_guard(id);
        }
    }
}

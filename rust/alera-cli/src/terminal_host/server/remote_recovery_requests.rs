use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};
use serde_json::Value;

impl ServerActor {
    pub(super) fn start_remote_relocation_recovery<
        E: crate::ssh_remote::RemoteHostExecutor + Send + Sync + 'static,
    >(
        &mut self,
        client_id: u64,
        request_id: i64,
        workspace_id: String,
        limit: u32,
        executor: E,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = async {
                let workspace = store
                    .find_workspace(&workspace_id)
                    .await?
                    .ok_or_else(|| anyhow::anyhow!("Workspace no longer exists"))?;
                crate::remote_relocation_recovery::inspect(&store, workspace, limit, &executor)
                    .await
            }
            .await;
            let result = super::requests::json_result(result);
            let _ = inbox.send(ServerCommand::RemoteRecoveryFinished {
                client_id,
                request_id,
                result,
            });
        });
    }

    pub(super) fn finish_remote_relocation_recovery(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        if self.require_auth(client_id).is_ok()
            && self
                .require_request_allowed(client_id, "workspace.sshRelocationRecovery")
                .is_ok()
            && self
                .require_shared_checkout_support(client_id, "workspace.sshRelocationRecovery")
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

pub(super) fn recovery_limit(payload: &Value) -> HostResult<u32> {
    match payload.get("limit") {
        None => Ok(20),
        Some(value) => value
            .as_u64()
            .map(|value| value.clamp(1, 100) as u32)
            .ok_or_else(|| HostError::format("Recovery limit must be a non-negative integer")),
    }
}

#[cfg(test)]
#[path = "remote_recovery_requests_tests.rs"]
mod tests;

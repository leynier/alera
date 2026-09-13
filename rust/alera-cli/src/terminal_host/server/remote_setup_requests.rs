use super::{ServerActor, ServerCommand};
use crate::remote_owner_setup::OwnerSetupAction;
use crate::remote_relocation_setup::SetupRequest;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};
use serde_json::Value;

impl ServerActor {
    pub(super) async fn try_start_remote_setup_control(
        &mut self,
        client_id: u64,
        request_id: i64,
        operation: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        let action = match operation {
            "workspace.runSetup"
                if payload
                    .get("relocationId")
                    .is_some_and(|value| !value.is_null()) =>
            {
                OwnerSetupAction::Run
            }
            "workspace.cancelRelocationSetup" => OwnerSetupAction::Cancel,
            "workspace.recoverRelocationSetup" => OwnerSetupAction::Recover,
            _ => return Ok(false),
        };
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, operation)?;
        let workspace_id = super::requests::require_string_key(payload, "id")?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("Workspace no longer exists"))?;
        if workspace.host_id == alera_core::runtime::LOCAL_HOST_ID {
            return Ok(false);
        }
        if payload.get("copiesOnly").and_then(Value::as_bool) == Some(true) {
            return Err(HostError::state(
                "Relocation setup uses its complete owner recipe; copiesOnly is incompatible",
            ));
        }
        let relocation_id = super::requests::require_string_key(payload, "relocationId")?;
        let attempt_id = match payload.get("attemptId") {
            None | Some(Value::Null) => None,
            Some(_) => Some(super::requests::require_string_key(payload, "attemptId")?),
        };
        if !matches!(action, OwnerSetupAction::Run) && attempt_id.is_none() {
            return Err(HostError::state("An exact setup attempt is required"));
        }
        self.start_remote_setup_control(
            client_id,
            request_id,
            SetupRequest {
                workspace_id,
                relocation_id,
                attempt_id,
                action,
            },
            crate::ssh_remote::LiveSshRemoteHost,
        );
        Ok(true)
    }

    pub(super) fn start_remote_setup_control<
        E: crate::ssh_remote::RemoteHostExecutor + Send + Sync + 'static,
    >(
        &mut self,
        client_id: u64,
        request_id: i64,
        request: SetupRequest,
        executor: E,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let operation = request.operation();
        // Cancellation must be able to reach the owner while setup is still running.
        tokio::spawn(async move {
            let result = super::requests::json_result(
                crate::remote_relocation_setup::execute(&store, request, &executor).await,
            );
            let _ = inbox.send(ServerCommand::RemoteSetupFinished {
                client_id,
                request_id,
                operation,
                result,
            });
        });
    }

    pub(super) fn finish_remote_setup_control(
        &mut self,
        client_id: u64,
        request_id: i64,
        operation: &'static str,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        if self.require_auth(client_id).is_ok()
            && self.require_request_allowed(client_id, operation).is_ok()
            && self
                .require_shared_checkout_support(client_id, operation)
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

#[cfg(test)]
#[path = "remote_setup_requests_tests.rs"]
mod tests;

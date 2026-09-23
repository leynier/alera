use serde_json::Value;

use super::requests::require_string_key;
use super::runtime_mutations::RuntimeMutationRequest;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(super) fn try_start_deferred_workspace_setup(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        match request_type {
            "workspace.runSetup" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "id")?;
                let copies_only = payload
                    .get("copiesOnly")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let relocation_id = match payload.get("relocationId") {
                    None | Some(Value::Null) => None,
                    Some(_) => Some(require_string_key(payload, "relocationId")?),
                };
                if copies_only && relocation_id.is_some() {
                    return Err(HostError::state("Relocation setup runs its complete recorded recipe; copiesOnly is incompatible"));
                }
                if let Some(relocation_id) = relocation_id {
                    self.start_runtime_mutation(
                        client_id,
                        request_id,
                        RuntimeMutationRequest::RunRelocationSetup {
                            workspace_id,
                            relocation_id,
                        },
                    );
                } else {
                    self.start_workspace_setup(client_id, request_id, workspace_id, copies_only);
                }
                Ok(true)
            }
            "workspace.recoverRelocationSetup" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RecoverRelocationSetup {
                        workspace_id: require_string_key(payload, "id")?,
                        relocation_id: require_string_key(payload, "relocationId")?,
                        attempt_id: require_string_key(payload, "attemptId")?,
                    },
                );
                Ok(true)
            }
            "workspace.prepareRelocationSetup" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "id")?;
                let relocation_id = require_string_key(payload, "relocationId")?;
                let directory = self.setup_script_directory().ok_or_else(|| {
                    HostError::state("The runtime has no directory for setup launchers")
                })?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::PrepareRelocationSetup {
                        workspace_id,
                        relocation_id,
                        directory,
                    },
                );
                Ok(true)
            }
            _ => Ok(false),
        }
    }
}

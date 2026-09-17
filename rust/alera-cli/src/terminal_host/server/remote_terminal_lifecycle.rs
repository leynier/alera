use alera_core::runtime::{TerminalLifecycleAction, TerminalLifecycleOperation, LOCAL_HOST_ID};
use anyhow::{Context, Result};
use base64::Engine;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use super::{ServerActor, ServerCommand};
use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

static HOME_EPOCH: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| uuid::Uuid::new_v4().to_string());

impl ServerActor {
    pub(super) async fn try_start_remote_terminal_lifecycle(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        self.start_remote_terminal_lifecycle_with_executor(
            client_id,
            request_id,
            verb,
            payload,
            crate::ssh_remote::LiveSshRemoteHost,
        )
        .await
    }

    async fn start_remote_terminal_lifecycle_with_executor<
        E: RemoteHostExecutor + Send + Sync + 'static,
    >(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
        executor: E,
    ) -> HostResult<bool> {
        let action = match verb {
            "terminate" | "tab.remove" => TerminalLifecycleAction::Close,
            "terminal.restart" => TerminalLifecycleAction::Restart,
            _ => return Ok(false),
        };
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, verb)?;
        let session_id = payload["sessionId"].as_str().map(str::to_owned);
        let requested_tab_id = if verb == "tab.remove" {
            payload["id"].as_str()
        } else {
            payload["tabId"].as_str()
        };
        let tab = if let Some(tab_id) = requested_tab_id {
            self.runtime_store
                .find_workspace_tab(tab_id)
                .await
                .map_err(state_error)?
        } else if let Some(session) = session_id.as_ref().and_then(|id| self.sessions.get(id)) {
            self.runtime_store
                .find_workspace_tab(&session.tab_id)
                .await
                .map_err(state_error)?
        } else {
            None
        };
        let Some(tab) = tab else { return Ok(false) };
        if tab.kind != "terminal" {
            return Ok(false);
        }
        let Some(workspace) = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(state_error)?
        else {
            return Ok(false);
        };
        if workspace.host_id == LOCAL_HOST_ID {
            return Ok(false);
        }
        if !crate::ssh_remote::uses_owner_terminal(&self.runtime_store, &workspace)
            .await
            .map_err(state_error)?
        {
            return Ok(false);
        }
        if self
            .runtime_store
            .find_project_checkout(&workspace.project_id, &workspace.host_id)
            .await
            .map_err(state_error)?
            .is_none()
        {
            return Ok(false);
        }
        let session_id = session_id
            .or_else(|| tab.payload["terminalSessionId"].as_str().map(str::to_owned))
            .ok_or_else(|| HostError::state("The remote terminal session identity is missing"))?;
        if tab.kind != "terminal" || tab.payload["terminalSessionId"] != session_id {
            return Err(HostError::state(
                "The remote terminal does not belong to this tab",
            ));
        }
        let session = self.sessions.get(&session_id);
        if session
            .is_some_and(|session| session.workspace_id != workspace.id || session.tab_id != tab.id)
            || payload["workspaceId"]
                .as_str()
                .is_some_and(|id| id != workspace.id)
        {
            return Err(HostError::state(
                "Remote terminal lifecycle metadata changed",
            ));
        }
        let explicit_id = payload["operationId"].as_str();
        if action == TerminalLifecycleAction::Restart && explicit_id.is_none() {
            return Err(HostError::state(
                "Update this client: restarting an SSH terminal requires a stable operationId for safe retries",
            ));
        }
        if payload.get("operationId").is_some()
            && explicit_id.is_none_or(|id| uuid::Uuid::parse_str(id).is_err())
        {
            return Err(HostError::state(
                "Terminal lifecycle requires a stable operation UUID",
            ));
        }
        let mut saved = if let Some(id) = explicit_id {
            self.runtime_store
                .terminal_lifecycle_operation(id)
                .await
                .map_err(state_error)?
        } else {
            None
        };
        if saved.is_none() {
            saved = self
                .runtime_store
                .pending_terminal_lifecycle_for_session(&session_id)
                .await
                .map_err(state_error)?;
            if let (Some(id), Some(pending)) = (explicit_id, &saved) {
                if pending.id != id {
                    return Err(HostError::state(
                        "Retry the original pending terminal operation before starting another",
                    ));
                }
            }
        }
        if saved.is_none() && explicit_id.is_none() {
            if let Some(session) = session {
                saved = self
                    .runtime_store
                    .terminal_lifecycle_for_generation(
                        &session_id,
                        session.instance_id(),
                        Some(HOME_EPOCH.as_str()),
                        action,
                    )
                    .await
                    .map_err(state_error)?;
            }
        }
        let operation = if let Some(saved) = saved {
            if saved.workspace.id != workspace.id
                || saved.workspace.instance_id != workspace.instance_id
                || saved.workspace.host_id != workspace.host_id
                || saved.workspace.path != workspace.path
                || saved.workspace.project_id != workspace.project_id
                || saved.workspace.kind != workspace.kind
                || saved.session_id != session_id
                || saved.tab_id != tab.id
                || saved.action != action
            {
                return Err(HostError::state(
                    "Recover the original pending remote terminal action before changing its scope",
                ));
            }
            saved
        } else {
            let session = session.ok_or_else(|| {
                HostError::state(
                    "The Home session is unavailable; remote terminal closure remains unverified",
                )
            })?;
            let operation = TerminalLifecycleOperation {
                id: explicit_id
                    .map(str::to_owned)
                    .unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
                workspace,
                tab_id: tab.id,
                session_id,
                session_generation: session.instance_id(),
                initiator_epoch: Some(HOME_EPOCH.clone()),
                action,
                closure_verified: false,
            };
            self.runtime_store
                .begin_remote_terminal_lifecycle_operation(&operation)
                .await
                .map_err(state_error)?
        };
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let inbox = self.inbox.clone();
        let store = self.runtime_store.clone();
        let verb = verb.to_string();
        let payload = payload.clone();
        tokio::spawn(async move {
            let result = if operation.closure_verified {
                Ok(operation.clone())
            } else {
                async {
                    let owner = execute(&store, &operation, &executor).await?;
                    store
                        .complete_remote_terminal_lifecycle_operation(&operation, &owner)
                        .await
                }
                .await
            }
            .map_err(state_error);
            let _ = inbox.send(ServerCommand::RemoteTerminalLifecycleFinished {
                client_id,
                request_id,
                verb,
                payload,
                result,
            });
        });
        Ok(true)
    }

    pub(super) async fn finish_remote_terminal_lifecycle(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: String,
        payload: Value,
        result: HostResult<TerminalLifecycleOperation>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        let response = match result {
            Err(error) => Err(error),
            Ok(operation) => {
                if operation.action == TerminalLifecycleAction::Close {
                    self.cancel_agent_title_job(&operation.tab_id);
                    self.broadcast_workspace_tabs_changed(Some(&operation.workspace.id));
                }
                if self
                    .sessions
                    .get(&operation.session_id)
                    .is_some_and(|session| {
                        session.instance_id() != operation.session_generation
                            || operation.initiator_epoch.as_deref() != Some(HOME_EPOCH.as_str())
                    })
                {
                    if operation.action == TerminalLifecycleAction::Restart
                        && payload["operationId"].as_str() == Some(operation.id.as_str())
                    {
                        let verb = if self.is_mobile_client(client_id) {
                            "terminal.attach"
                        } else {
                            "createOrAttach"
                        };
                        self.handle_request(client_id, verb, &payload).await
                    } else {
                        Err(HostError::state(
                            "The Home terminal changed after owner closure; replacement preserved",
                        ))
                    }
                } else {
                    if verb == "tab.remove" {
                        self.handle_request(
                            client_id,
                            "terminate",
                            &json!({"sessionId":operation.session_id}),
                        )
                        .await
                    } else {
                        self.handle_request(client_id, &verb, &payload).await
                    }
                }
            }
        };
        match response {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
        self.schedule_shutdown_if_idle();
    }
}

async fn execute<E: RemoteHostExecutor>(
    store: &alera_core::runtime::RuntimeStore,
    operation: &TerminalLifecycleOperation,
    executor: &E,
) -> Result<TerminalLifecycleOperation> {
    let target = require_bootstrapped_ssh_target(store, &operation.workspace.host_id).await?;
    let install = target
        .install_dir
        .as_deref()
        .filter(|path| !path.is_empty())
        .context("Bootstrap the SSH host again to record its installation directory")?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let mut workspace = operation.workspace.clone();
    workspace.host_id = LOCAL_HOST_ID.into();
    let mut payload = json!({"operationId":operation.id,"workspace":workspace,"tabId":operation.tab_id,"sessionId":operation.session_id,"action":operation.action});
    {
        let mut project = store
            .find_project(&workspace.project_id)
            .await?
            .context("The terminal project is missing")?;
        let checkout = store
            .find_project_checkout(&workspace.project_id, &operation.workspace.host_id)
            .await?
            .context("The registered SSH project checkout is missing")?;
        project.repo_path = checkout.path;
        let repository_path = store
            .find_workspace_checkout(&workspace.id)
            .await?
            .and_then(|binding| binding.repository_path);
        payload["registrationBase64"] = json!(base64::engine::general_purpose::STANDARD.encode(
            serde_json::to_vec(
                &json!({"project":project,"workspace":workspace,"repositoryPath":repository_path})
            )?
        ));
    }
    let encoded = base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(&payload)?);
    let quote = if windows {
        crate::ssh_bootstrap::powershell_string
    } else {
        crate::ssh_bootstrap::shell_quote
    };
    let arguments = format!(
        "project control-owner-terminal --request-base64 {}",
        quote(&encoded)
    );
    let profile = hex::encode(Sha256::digest(operation.workspace.project_id.as_bytes()));
    let script = crate::remote_owner_terminal_launch::owner_command_script(
        windows, install, &profile, &arguments,
    );
    let output = tokio::time::timeout(
        std::time::Duration::from_secs(60),
        executor.run(&target, windows, &script),
    )
    .await
    .context("The owner terminal response timed out; retry to recover the original operation")??;
    let value: Value = serde_json::from_str(output.trim())
        .context("The SSH owner returned invalid terminal closure evidence")?;
    if value["processClosureVerified"] != true {
        anyhow::bail!("The owner did not verify terminal process closure");
    }
    Ok(serde_json::from_value(value["operation"].clone())?)
}

fn state_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

#[cfg(test)]
#[path = "remote_terminal_lifecycle_tests.rs"]
mod tests;

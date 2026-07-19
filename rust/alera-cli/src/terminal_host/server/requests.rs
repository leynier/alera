use alera_core::{
    git as core_git,
    runtime::{
        LinkedReview, Project, ProjectConfig, SshTarget, WorkbenchLayoutRecord, Workspace,
        WorkspaceTabRecord, WorkspaceTag,
    },
};
use chrono::{DateTime, Utc};
use serde_json::{json, Map, Value};

use crate::agent_status::reconcile_agent_integrations;
use crate::managed_workspace::{
    create_managed_workspace, remove_managed_workspace, ManagedWorkspaceCreateRequest,
    ManagedWorkspaceRemoveRequest,
};
use crate::mobile_access::{
    apply_mobile_settings_update_resolved, authenticate_mobile_device, cancel_mobile_pairing_offer,
    create_mobile_pairing_offer_for_settings, list_mobile_devices, mobile_status,
    pair_mobile_device, prepare_mobile_pairing_offer_settings_resolved, rename_mobile_device,
    revoke_mobile_device, MobileDevicePairRequest, MobilePairingCreateRequest,
    MobileSettingsUpdateRequest, MOBILE_PROTOCOL_VERSION,
};
use crate::ssh_bootstrap::{build_ssh_bootstrap_plan, SshTargetBootstrapRequest};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{
    error_response, event, int_or, ok_response, require_object, TerminalHostConfig,
    TerminalHostLaunch, PROTOCOL_VERSION, RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
    RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY, RUNTIME_HOST_LIFECYCLE_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY, RUNTIME_HOST_MOBILE_CAPABILITY,
    RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY, RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY, RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
};
use crate::terminal_host::session::{Session, SessionDriver};

use super::mobile_terminal_requests::mobile_request_allowed;
use super::{ClientKind, ServerActor, ServerCommand};

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectConfigUpsertRequest {
    project_id: String,
    config: ProjectConfig,
    #[serde(default)]
    updated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct MobileHelloRequest {
    protocol_version: i64,
    device_id: String,
    device_token: String,
}

impl ServerActor {
    /// Parse and dispatch one client line, then write the response. Malformed
    /// messages without a request id drop the connection because there is no
    /// response target.
    pub(super) async fn handle_line(&mut self, client_id: u64, line: String) {
        let decoded: Value = match serde_json::from_str(&line) {
            Ok(value) => value,
            // jsonDecode threw: no request id is available, so drop the client.
            Err(_) => {
                self.dispose_client(client_id).await;
                return;
            }
        };
        let Some(obj) = decoded.as_object() else {
            self.dispose_client(client_id).await;
            return;
        };
        let request_id = obj.get("id").and_then(Value::as_i64);
        let outcome: HostResult<Value> = match extract_request(obj) {
            Ok((request_type, payload)) => {
                if let Some(id) = request_id {
                    match self.try_start_deferred_request(client_id, id, &request_type, &payload) {
                        Ok(true) => return,
                        Ok(false) => {}
                        Err(error) => {
                            if let Some(id) = request_id {
                                self.client_write(client_id, error_response(id, &error));
                            } else {
                                self.dispose_client(client_id).await;
                            }
                            return;
                        }
                    }
                    if request_type.starts_with("orchestration.") {
                        match self
                            .handle_orchestration_request(client_id, id, &request_type, &payload)
                            .await
                        {
                            // A parked waiter answers later (wake or timeout).
                            Ok(None) => return,
                            Ok(Some(value)) => {
                                self.client_write(client_id, ok_response(id, value));
                            }
                            Err(error) => {
                                self.client_write(client_id, error_response(id, &error));
                            }
                        }
                        return;
                    }
                }
                self.handle_request(client_id, &request_type, &payload)
                    .await
            }
            Err(error) => Err(error),
        };
        match outcome {
            Ok(payload) => {
                if let Some(id) = request_id {
                    self.client_write(client_id, ok_response(id, payload));
                }
            }
            Err(error) => {
                if let Some(id) = request_id {
                    self.client_write(client_id, error_response(id, &error));
                } else {
                    self.dispose_client(client_id).await;
                }
            }
        }
    }

    fn try_start_deferred_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        match request_type {
            "workspace.createManaged" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let request: ManagedWorkspaceCreateRequest = parse_payload(payload)?;
                self.start_managed_workspace_create(client_id, request_id, request);
                Ok(true)
            }
            "workspace.removeManaged" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let request: ManagedWorkspaceRemoveRequest = parse_payload(payload)?;
                self.start_managed_workspace_remove(client_id, request_id, request);
                Ok(true)
            }
            "write" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.queue_terminal_input(client_id, request_id, payload)
            }
            _ => Ok(false),
        }
    }

    fn start_managed_workspace_create(
        &mut self,
        client_id: u64,
        request_id: i64,
        request: ManagedWorkspaceCreateRequest,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = json_result(create_managed_workspace(&store, request).await);
            let _ = inbox.send(ServerCommand::ManagedWorkspaceCreated {
                client_id,
                request_id,
                result,
            });
        });
    }

    fn start_managed_workspace_remove(
        &mut self,
        client_id: u64,
        request_id: i64,
        request: ManagedWorkspaceRemoveRequest,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = json_result(remove_managed_workspace(&store, request).await);
            let _ = inbox.send(ServerCommand::ManagedWorkspaceRemoved {
                client_id,
                request_id,
                result,
            });
        });
    }

    pub(super) async fn handle_managed_workspace_created(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        match result {
            Ok(payload) => {
                self.client_write(client_id, ok_response(request_id, payload));
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
            }
            Err(error) => {
                self.client_write(client_id, error_response(request_id, &error));
            }
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn handle_managed_workspace_removed(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        match result {
            Ok(payload) => {
                if let Some(id) = payload
                    .get("id")
                    .and_then(Value::as_str)
                    .map(str::to_string)
                {
                    self.terminate_sessions_for_workspace(&id).await;
                }
                self.client_write(client_id, ok_response(request_id, payload));
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
            }
            Err(error) => {
                self.client_write(client_id, error_response(request_id, &error));
            }
        }
        self.schedule_shutdown_if_idle();
    }

    async fn handle_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        match request_type {
            "hello" => {
                let version_ok = payload.get("protocolVersion") == Some(&json!(PROTOCOL_VERSION));
                let token_ok =
                    payload.get("token").and_then(Value::as_str) == Some(self.token.as_str());
                if !version_ok || !token_ok {
                    return Err(HostError::state("Terminal host authentication failed."));
                }
                if let Some(client) = self.clients.get_mut(&client_id) {
                    client.authenticated = true;
                }
                self.cancel_shutdown_timer();
                Ok(json!({}))
            }
            "mobile.hello" => {
                if !self.is_mobile_client(client_id) {
                    return Err(HostError::state(
                        "mobile authentication is only available on the mobile gateway.",
                    ));
                }
                let request: MobileHelloRequest = parse_payload(payload)?;
                if request.protocol_version != MOBILE_PROTOCOL_VERSION {
                    return Err(HostError::state(format!(
                        "Unsupported mobile protocol version: {}",
                        request.protocol_version
                    )));
                }
                let device = authenticate_mobile_device(
                    &self.runtime_store,
                    &request.device_id,
                    &request.device_token,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
                if let Some(client) = self.clients.get_mut(&client_id) {
                    client.authenticated = true;
                    client.mobile_device_id = Some(device.id.clone());
                    client.mobile_device_name = Some(device.display_name.clone());
                }
                self.cancel_shutdown_timer();
                self.broadcast_authenticated(event("mobileDevicesChanged", json!({})));
                Ok(json!({
                    "protocolVersion": MOBILE_PROTOCOL_VERSION,
                    "runtime": "alera",
                    "runtimeCapabilities": [
                        RUNTIME_HOST_CAPABILITY,
                        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                        RUNTIME_HOST_MOBILE_CAPABILITY,
                        RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
                        RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
                        RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY,
                        RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
                        RUNTIME_HOST_LIFECYCLE_CAPABILITY,
                        RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
                    ],
                    "authenticated": true,
                    "device": device,
                }))
            }
            "mobile.device.pair" if self.is_mobile_client(client_id) => {
                let request: MobileDevicePairRequest = parse_payload(payload)?;
                let value = json_result(pair_mobile_device(&self.runtime_store, request).await)?;
                self.broadcast_authenticated(event("mobileDevicesChanged", json!({})));
                self.broadcast_authenticated(event("mobilePairingsChanged", json!({})));
                Ok(value)
            }
            _ => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.handle_authenticated_request(client_id, request_type, payload)
                    .await
            }
        }
    }

    async fn handle_authenticated_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        match request_type {
            "configure" => {
                self.require_auth(client_id)?;
                let config = TerminalHostConfig::from_json(payload)?;
                self.apply_config(config).await;
                Ok(json!({}))
            }
            "host.shutdown" => {
                if self.is_mobile_client(client_id) {
                    return Err(HostError::state(
                        "Mobile clients cannot stop the runtime host.",
                    ));
                }
                let force = payload
                    .get("force")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let active_sessions = self
                    .sessions
                    .values()
                    .filter(|session| session.running())
                    .count();
                let active_jobs = self.ssh_bootstrap_jobs.len()
                    + usize::from(self.managed_workspace_jobs > 0)
                    + self.coordinators.len();
                if !force && (active_sessions > 0 || active_jobs > 0) {
                    return Err(HostError::state(format!(
                        "Runtime host has {active_sessions} active terminal session(s) and {active_jobs} active background job(s). Retry with --force to stop it."
                    )));
                }
                let _ = self.inbox.send(ServerCommand::RequestedShutdown);
                Ok(json!({
                    "stopped": true,
                    "forced": force,
                    "activeSessions": active_sessions,
                    "activeJobs": active_jobs,
                }))
            }
            "createOrAttach" => {
                self.require_auth(client_id)?;
                self.create_or_attach(client_id, payload).await
            }
            "write" => {
                self.require_auth(client_id)?;
                Ok(json!({}))
            }
            "terminal.read" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                let cursor = payload.get("cursor").and_then(Value::as_u64);
                let max_bytes = payload
                    .get("maxBytes")
                    .and_then(Value::as_u64)
                    .unwrap_or(65_536)
                    .max(1) as usize;
                let session = self
                    .sessions
                    .get(&session_id)
                    .ok_or_else(|| HostError::state(format!("terminal not found: {session_id}")))?;
                let snapshot = session.snapshot_payload();
                let bytes =
                    crate::terminal_host::protocol::decode_bytes(snapshot.get("snapshotBase64"))?;
                let (base_cursor, end_cursor) = session.output_stream_range();
                let (requested_cursor, start_cursor, next_cursor) =
                    terminal_read_window(base_cursor, end_cursor, cursor, max_bytes as u64);
                let (start_cursor, next_cursor) =
                    align_terminal_text_window(&bytes, base_cursor, start_cursor, next_cursor);
                let start = (start_cursor - base_cursor) as usize;
                let end = (next_cursor - base_cursor) as usize;
                let selected = &bytes[start..end];
                Ok(json!({
                    "handle": session_id,
                    "baseCursor": base_cursor,
                    "cursor": start_cursor,
                    "nextCursor": next_cursor,
                    "truncated": requested_cursor < base_cursor,
                    "text": String::from_utf8_lossy(selected),
                    "dataBase64": crate::terminal_host::protocol::encode_bytes(selected),
                }))
            }
            "resize" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                let cols = int_or(payload, "cols", 80) as u16;
                let rows = int_or(payload, "rows", 24) as u16;
                if self.is_mobile_client(client_id) {
                    // A mobile resize (keyboard open/close, rotation) claims
                    // the driver seat and applies the phone viewport in place.
                    self.claim_mobile_driver(client_id, &session_id, Some((cols, rows)));
                } else if let Some(session) = self.sessions.get_mut(&session_id) {
                    if matches!(session.driver, SessionDriver::Mobile { .. }) {
                        // The phone drives; remember the desktop's ask so
                        // reclaim restores it instead of fighting over dims.
                        session.desktop_dims = Some((cols, rows));
                    } else {
                        session.resize(cols, rows);
                    }
                }
                Ok(json!({}))
            }
            "terminal.reclaim" => {
                self.require_auth(client_id)?;
                if self.is_mobile_client(client_id) {
                    return Err(HostError::state(
                        "terminal.reclaim is only available to desktop clients.",
                    ));
                }
                let session_id = self.require_session(payload)?;
                let restored = self.reclaim_terminal_for_desktop(&session_id);
                Ok(json!({ "restored": restored }))
            }
            "terminal.driver.list" => {
                self.require_auth(client_id)?;
                Ok(self.terminal_driver_list_payload())
            }
            "setOutputPaused" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                let paused = payload
                    .get("paused")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                self.flush_all_output(&session_id);
                let snapshot = if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.set_output_paused(client_id, paused);
                    session.snapshot_payload()
                } else {
                    json!({})
                };
                Ok(snapshot)
            }
            "detach" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                self.flush_all_output(&session_id);
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.detach(client_id);
                }
                self.release_mobile_driver_for_session(client_id, &session_id);
                self.immediate_checkpoint(&session_id).await;
                Ok(json!({}))
            }
            "terminate" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                self.cleanup_orchestration_for_closed_session(
                    &session_id,
                    "terminal was explicitly terminated",
                )
                .await;
                if !self.remove_terminal_session_tab(&session_id).await? {
                    self.flush_all_output(&session_id);
                    self.await_output_writes(&session_id).await;
                    let store = self.store.clone();
                    if let Some(mut session) = self.sessions.remove(&session_id) {
                        session.terminate(true, &store).await;
                    }
                }
                self.schedule_shutdown_if_idle();
                Ok(json!({}))
            }
            "terminal.create" => {
                self.require_auth(client_id)?;
                self.create_mobile_terminal(client_id, payload).await
            }
            "terminal.attach" => {
                self.require_auth(client_id)?;
                self.attach_mobile_terminal(client_id, payload).await
            }
            "status.get" => {
                self.require_auth(client_id)?;
                Ok(json!({
                    "runtimeHostVersion": option_env!("ALERA_BUILD_VERSION").unwrap_or(env!("CARGO_PKG_VERSION")),
                    "runtimeHostCommit": option_env!("ALERA_BUILD_COMMIT").unwrap_or("unknown"),
                    "protocolVersion": PROTOCOL_VERSION,
                    "orchestrationProtocolVersion": crate::terminal_host::protocol::ORCHESTRATION_PROTOCOL_VERSION,
                    "dispatchPreambleVersion": crate::terminal_host::protocol::DISPATCH_PREAMBLE_VERSION,
                    "skillVersion": crate::terminal_host::protocol::ORCHESTRATION_SKILL_VERSION,
                    "runtime": "alera",
                    "runtimeCapabilities": [
                        RUNTIME_HOST_CAPABILITY,
                        RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                        RUNTIME_HOST_MOBILE_CAPABILITY,
                        RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
                        RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
                        RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
                        RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
                        RUNTIME_HOST_LIFECYCLE_CAPABILITY,
                        RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
                    ],
                    "authenticated": true,
                    "persistent": self.config.persistent,
                    "activeSessions": self.sessions.values().filter(|session| session.running()).count(),
                    "activeAgents": self.agent_presence_items().as_array().map_or(0, Vec::len),
                    "mobileGatewayEnabled": self.mobile_gateway.is_some(),
                }))
            }
            "runtimeMetadata.get" => {
                self.require_auth(client_id)?;
                let key = require_string_key(payload, "key")?;
                json_result(self.runtime_store.get_metadata(&key).await)
            }
            "runtimeMetadata.set" => {
                self.require_auth(client_id)?;
                let key = require_string_key(payload, "key")?;
                let value = require_string_key(payload, "value")?;
                json_result(self.runtime_store.set_metadata(&key, &value).await)?;
                Ok(json!({}))
            }
            "runtimeSettings.get" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.runtime_settings().await)
            }
            "runtimeSettings.update" => {
                self.require_auth(client_id)?;
                if let Some(value) = payload.get("workspaceDirectory") {
                    let workspace_directory = match value {
                        Value::String(value) => Some(value.as_str()),
                        Value::Null => None,
                        _ => {
                            return Err(HostError::format(
                                "workspaceDirectory must be a string or null.",
                            ))
                        }
                    };
                    json_result(
                        self.runtime_store
                            .set_workspace_directory(workspace_directory)
                            .await,
                    )?;
                }
                if let Some(value) = payload.get("confirmWorkspaceRemoval") {
                    let value = value.as_bool().ok_or_else(|| {
                        HostError::format("confirmWorkspaceRemoval must be a boolean.")
                    })?;
                    json_result(
                        self.runtime_store
                            .set_confirm_workspace_removal(value)
                            .await,
                    )?;
                }
                if let Some(value) = payload.get("agentStatusHooks") {
                    let settings = serde_json::from_value(value.clone()).map_err(|_| {
                        HostError::format("agentStatusHooks must contain boolean agent switches.")
                    })?;
                    json_result(
                        self.runtime_store
                            .set_agent_status_hook_settings(&settings)
                            .await,
                    )?;
                    self.agent_presence
                        .retain_enabled(&settings.enabled_agents());
                    let runtime_dir = self.runtime_dir.clone();
                    let reconcile_settings = settings.clone();
                    let warnings = tokio::task::spawn_blocking(move || {
                        reconcile_agent_integrations(&runtime_dir, &reconcile_settings)
                    })
                    .await
                    .unwrap_or_else(|error| vec![error.to_string()]);
                    for warning in warnings {
                        eprintln!("alera agent integration warning: {warning}");
                    }
                    self.broadcast_agent_presence_changed();
                }
                let value = json_result(self.runtime_store.runtime_settings().await)?;
                self.broadcast_authenticated(event("runtimeSettingsChanged", json!({})));
                Ok(value)
            }
            "workspaceSidebar.snapshot" => self.workspace_sidebar_snapshot(client_id).await,
            "workbenchViewPrefs.get" => self.workbench_view_prefs(client_id).await,
            "workbenchViewPrefs.update" => {
                self.update_workbench_view_prefs(client_id, payload).await
            }
            "workspaceActivity.list" => self.workspace_activity(client_id).await,
            "workspaceActivity.upsertAll" => {
                self.upsert_workspace_activity(client_id, payload).await
            }
            "workspaceActivity.remove" => self.remove_workspace_activity(client_id, payload).await,
            "agentPresence.list" => {
                self.require_auth(client_id)?;
                Ok(self.agent_presence_items())
            }
            "project.list" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.list_projects().await)
            }
            "hostDirectory.roots" => {
                self.require_auth(client_id)?;
                self.host_directory_roots_request()
            }
            "hostDirectory.list" => {
                self.require_auth(client_id)?;
                self.host_directory_list_request(payload)
            }
            "project.register" => {
                self.require_auth(client_id)?;
                self.project_register_request(payload).await
            }
            "project.rename" => {
                self.require_auth(client_id)?;
                self.project_rename_request(payload).await
            }
            "project.remove.preview" => {
                self.require_auth(client_id)?;
                self.project_remove_preview_request(payload).await
            }
            "project.clone.start" => {
                self.require_auth(client_id)?;
                self.project_clone_start_request(payload).await
            }
            "project.clone.list" => {
                self.require_auth(client_id)?;
                self.project_clone_list_request().await
            }
            "project.clone.cancel" => {
                self.require_auth(client_id)?;
                self.project_clone_cancel_request(payload).await
            }
            "project.branches.list" => {
                self.require_auth(client_id)?;
                let project_id = require_string_key(payload, "projectId")?;
                let project = self
                    .runtime_store
                    .find_project(&project_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| HostError::state(format!("Project not found: {project_id}")))?;
                let branches = core_git::list_branches(&project.repo_path)
                    .map_err(|error| HostError::state(error.to_string()))?;
                let local_branches = branches
                    .iter()
                    .filter_map(|branch| {
                        match core_git::branch_exists(&project.repo_path, branch) {
                            Ok(true) => Some(Ok(branch.clone())),
                            Ok(false) => None,
                            Err(error) => Some(Err(HostError::state(error.to_string()))),
                        }
                    })
                    .collect::<HostResult<Vec<String>>>()?;
                Ok(json!({
                    "projectId": project.id,
                    "branches": branches,
                    "localBranches": local_branches,
                }))
            }
            "project.upsert" => {
                self.require_auth(client_id)?;
                let project: Project = parse_payload(payload)?;
                let value = json_result(self.runtime_store.upsert_project(project).await)?;
                self.broadcast_authenticated(event("projectsChanged", json!({})));
                Ok(value)
            }
            "project.remove" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                let workspace_ids: Vec<String> = self
                    .runtime_store
                    .list_workspaces(&id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .into_iter()
                    .map(|workspace| workspace.id)
                    .collect();
                json_result(self.runtime_store.remove_project(&id).await)?;
                self.terminate_sessions_for_workspaces(&workspace_ids).await;
                self.broadcast_authenticated(event("projectsChanged", json!({})));
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
                self.broadcast_authenticated(event("projectConfigsChanged", json!({})));
                Ok(json!({}))
            }
            "projectConfig.find" => {
                self.require_auth(client_id)?;
                let project_id = require_string_key(payload, "projectId")?;
                json_result(self.runtime_store.find_project_config(&project_id).await)
            }
            "projectConfig.effective" => {
                self.require_auth(client_id)?;
                self.project_effective_config_request(payload).await
            }
            "projectConfig.list" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.list_project_configs().await)
            }
            "projectConfig.upsert" => {
                self.require_auth(client_id)?;
                let request: ProjectConfigUpsertRequest = parse_payload(payload)?;
                let value = json_result(
                    self.runtime_store
                        .upsert_project_config(
                            &request.project_id,
                            request.config,
                            request.updated_at.unwrap_or_else(Utc::now),
                        )
                        .await,
                )?;
                self.broadcast_authenticated(event("projectConfigsChanged", json!({})));
                Ok(value)
            }
            "projectConfig.remove" => {
                self.require_auth(client_id)?;
                let project_id = require_string_key(payload, "projectId")?;
                json_result(self.runtime_store.remove_project_config(&project_id).await)?;
                self.broadcast_authenticated(event("projectConfigsChanged", json!({})));
                Ok(json!({}))
            }
            "workspace.list" => {
                self.require_auth(client_id)?;
                let project_id = require_string_key(payload, "projectId")?;
                json_result(self.runtime_store.list_workspaces(&project_id).await)
            }
            "workspace.listAll" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.list_all_workspaces().await)
            }
            "workspace.find" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                json_result(self.runtime_store.find_workspace(&id).await)
            }
            "workspace.upsert" => {
                self.require_auth(client_id)?;
                let workspace: Workspace = parse_payload(payload)?;
                let value = json_result(self.runtime_store.upsert_workspace(workspace).await)?;
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                Ok(value)
            }
            "workspace.setPinned" => self.handle_workspace_pinning(client_id, payload).await,
            "workspace.rename" => self.rename_workspace_request(client_id, payload).await,
            "workspace.sleep" => self.sleep_workspace_request(client_id, payload).await,
            "workspace.repositoryWebUrl" => {
                self.workspace_repository_web_url(client_id, payload).await
            }
            "workspace.remove" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                let cascade_tabs = payload
                    .get("cascadeTabs")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                json_result(self.runtime_store.remove_workspace(&id, cascade_tabs).await)?;
                self.terminate_sessions_for_workspace(&id).await;
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
                Ok(json!({}))
            }
            "workspace.removeForProject" => {
                self.require_auth(client_id)?;
                let project_id = require_string_key(payload, "projectId")?;
                let workspace_ids: Vec<String> = self
                    .runtime_store
                    .list_workspaces(&project_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .into_iter()
                    .map(|workspace| workspace.id)
                    .collect();
                json_result(
                    self.runtime_store
                        .remove_workspaces_for_project(&project_id)
                        .await,
                )?;
                self.terminate_sessions_for_workspaces(&workspace_ids).await;
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
                Ok(json!({}))
            }
            "tab.list" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                json_result(self.runtime_store.list_workspace_tabs(&workspace_id).await)
            }
            "tab.find" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                json_result(self.runtime_store.find_workspace_tab(&id).await)
            }
            "tab.upsert" => {
                self.require_auth(client_id)?;
                let tab: WorkspaceTabRecord = parse_payload(payload)?;
                let value = self.upsert_workspace_tab_and_spawn(tab).await?;
                Ok(json!(value))
            }
            "tab.remove" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                json_result(self.runtime_store.remove_workspace_tab(&id).await)?;
                self.terminate_sessions_for_tab(&id).await;
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
                Ok(json!({}))
            }
            "tab.removeForWorkspace" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                json_result(
                    self.runtime_store
                        .remove_workspace_tabs_for_workspace(&workspace_id)
                        .await,
                )?;
                self.terminate_sessions_for_workspace(&workspace_id).await;
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
                Ok(json!({}))
            }
            "linkedReview.find" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                json_result(self.runtime_store.find_linked_review(&workspace_id).await)
            }
            "linkedReview.upsert" => {
                self.require_auth(client_id)?;
                let review: LinkedReview = parse_payload(payload)?;
                let value = json_result(self.runtime_store.upsert_linked_review(review).await)?;
                self.broadcast_authenticated(event("linkedReviewsChanged", json!({})));
                Ok(value)
            }
            "linkedReview.remove" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                json_result(self.runtime_store.remove_linked_review(&workspace_id).await)?;
                self.broadcast_authenticated(event("linkedReviewsChanged", json!({})));
                Ok(json!({}))
            }
            "layout.find" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                json_result(
                    self.runtime_store
                        .find_workbench_layout(&workspace_id)
                        .await,
                )
            }
            "layout.upsert" => {
                self.require_auth(client_id)?;
                let layout: WorkbenchLayoutRecord = parse_payload(payload)?;
                let value = json_result(self.runtime_store.upsert_workbench_layout(layout).await)?;
                self.broadcast_authenticated(event("workbenchLayoutsChanged", json!({})));
                Ok(value)
            }
            "layout.remove" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                json_result(
                    self.runtime_store
                        .remove_workbench_layout(&workspace_id)
                        .await,
                )?;
                self.broadcast_authenticated(event("workbenchLayoutsChanged", json!({})));
                Ok(json!({}))
            }
            "workspaceTag.list" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.list_tags().await)
            }
            "workspaceTag.create" => self.create_workspace_tag(client_id, payload).await,
            "workspaceTag.setForWorkspace" => self.set_tags_for_workspace(client_id, payload).await,
            "workspaceTag.upsert" => {
                self.require_auth(client_id)?;
                let tag: WorkspaceTag = parse_payload(payload)?;
                let value = json_result(self.runtime_store.upsert_tag(tag).await)?;
                self.broadcast_authenticated(event("workspaceTagsChanged", json!({})));
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                Ok(value)
            }
            "workspaceTag.remove" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                json_result(self.runtime_store.remove_tag(&id).await)?;
                self.broadcast_authenticated(event("workspaceTagsChanged", json!({})));
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                Ok(json!({}))
            }
            "workspaceTag.assign" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let tag_id = require_string_key(payload, "tagId")?;
                json_result(self.runtime_store.assign_tag(&workspace_id, &tag_id).await)?;
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                Ok(json!({}))
            }
            "workspaceTag.unassign" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let tag_id = require_string_key(payload, "tagId")?;
                json_result(
                    self.runtime_store
                        .unassign_tag(&workspace_id, &tag_id)
                        .await,
                )?;
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                Ok(json!({}))
            }
            "workspaceRelation.list" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.list_relations().await)
            }
            "workspaceRelation.link" => {
                self.require_auth(client_id)?;
                let parent_id = require_string_key(payload, "parentWorkspaceId")?;
                let child_id = require_string_key(payload, "childWorkspaceId")?;
                let value = json_result(
                    self.runtime_store
                        .link_workspaces(&parent_id, &child_id)
                        .await,
                )?;
                self.broadcast_authenticated(event("workspaceRelationsChanged", json!({})));
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                Ok(value)
            }
            "workspaceRelation.unlink" => {
                self.require_auth(client_id)?;
                let parent_id = require_string_key(payload, "parentWorkspaceId")?;
                let child_id = require_string_key(payload, "childWorkspaceId")?;
                json_result(
                    self.runtime_store
                        .unlink_workspaces(&parent_id, &child_id)
                        .await,
                )?;
                self.broadcast_authenticated(event("workspaceRelationsChanged", json!({})));
                self.broadcast_authenticated(event("workspacesChanged", json!({})));
                Ok(json!({}))
            }
            "workspaceCascade.preview" => {
                self.require_auth(client_id)?;
                let workspace_ids = string_array(payload.get("workspaceIds"));
                let tag_ids = string_array(payload.get("tagIds"));
                let include_descendants = payload
                    .get("includeDescendants")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let include_tags = payload
                    .get("includeTags")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                json_result(
                    self.runtime_store
                        .cascade_preview(
                            &workspace_ids,
                            &tag_ids,
                            include_descendants,
                            include_tags,
                        )
                        .await,
                )
            }
            "sshTarget.list" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.list_ssh_targets().await)
            }
            "sshTarget.upsert" => {
                self.require_auth(client_id)?;
                let mut target: SshTarget = parse_payload(payload)?;
                if payload.get("installDir").is_none() {
                    if let Some(existing) = self
                        .runtime_store
                        .find_ssh_target(&target.id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?
                    {
                        target.install_dir = existing.install_dir;
                    }
                }
                let value = json_result(self.runtime_store.upsert_ssh_target(target).await)?;
                self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
                Ok(value)
            }
            "sshTarget.remove" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                self.cancel_ssh_bootstrap_job_before_remove(&id).await?;
                json_result(self.runtime_store.remove_ssh_target(&id).await)?;
                self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
                Ok(json!({}))
            }
            "sshTarget.bootstrap.plan" => {
                self.require_auth(client_id)?;
                let request: SshTargetBootstrapRequest = parse_payload(payload)?;
                json_result(build_ssh_bootstrap_plan(&self.runtime_store, &request).await)
            }
            "sshTarget.bootstrap.start" => {
                self.require_auth(client_id)?;
                let request: SshTargetBootstrapRequest = parse_payload(payload)?;
                self.start_ssh_bootstrap_job(request).await
            }
            "sshTarget.bootstrap.cancel" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                self.cancel_ssh_bootstrap_job(&id).await
            }
            "sshTarget.bootstrap.jobs" => {
                self.require_auth(client_id)?;
                Ok(self.list_ssh_bootstrap_jobs())
            }
            "mobile.status.get" => {
                self.require_auth(client_id)?;
                json_result(mobile_status(&self.runtime_store, Some(true)).await)
            }
            "mobile.settings.update" => {
                self.require_auth(client_id)?;
                let request: MobileSettingsUpdateRequest = parse_payload(payload)?;
                let current = self
                    .runtime_store
                    .mobile_access_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                let next = apply_mobile_settings_update_resolved(current.clone(), request)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                let value =
                    serde_json::to_value(self.apply_mobile_gateway_settings(current, next).await?)
                        .map_err(|error| HostError::format(error.to_string()))?;
                self.broadcast_authenticated(event("mobileSettingsChanged", json!({})));
                Ok(value)
            }
            "mobile.pairing.create" | "pairing.create" => {
                self.require_auth(client_id)?;
                let request: MobilePairingCreateRequest = parse_payload(payload)?;
                let current = self
                    .runtime_store
                    .mobile_access_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                let (next, endpoint) =
                    prepare_mobile_pairing_offer_settings_resolved(current.clone(), &request)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                let settings = if next == current {
                    if self.mobile_gateway.is_none() {
                        self.restart_mobile_gateway().await?;
                    }
                    current
                } else {
                    self.apply_mobile_gateway_settings(current, next).await?
                };
                let value = json_result(
                    create_mobile_pairing_offer_for_settings(
                        &self.runtime_store,
                        &settings,
                        &request,
                        endpoint,
                    )
                    .await,
                )?;
                self.broadcast_authenticated(event("mobilePairingsChanged", json!({})));
                Ok(value)
            }
            "mobile.pairing.cancel" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                json_result(cancel_mobile_pairing_offer(&self.runtime_store, &id).await)?;
                self.broadcast_authenticated(event("mobilePairingsChanged", json!({})));
                Ok(json!({}))
            }
            "mobile.device.list" => {
                self.require_auth(client_id)?;
                let include_revoked = payload
                    .get("includeRevoked")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                json_result(list_mobile_devices(&self.runtime_store, include_revoked).await)
            }
            "mobile.device.pair" => {
                self.require_auth(client_id)?;
                let request: MobileDevicePairRequest = parse_payload(payload)?;
                let value = json_result(pair_mobile_device(&self.runtime_store, request).await)?;
                self.broadcast_authenticated(event("mobileDevicesChanged", json!({})));
                self.broadcast_authenticated(event("mobilePairingsChanged", json!({})));
                Ok(value)
            }
            "mobile.device.revoke" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                json_result(revoke_mobile_device(&self.runtime_store, &id).await)?;
                self.dispose_mobile_clients_for_device(&id).await;
                self.broadcast_authenticated(event("mobileDevicesChanged", json!({})));
                Ok(json!({}))
            }
            "mobile.device.rename" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                let display_name = require_string_key(payload, "displayName")?;
                let value = json_result(
                    rename_mobile_device(&self.runtime_store, &id, &display_name).await,
                )?;
                self.broadcast_authenticated(event("mobileDevicesChanged", json!({})));
                Ok(value)
            }
            other => Err(HostError::state(format!(
                "Unknown terminal host request: {other}"
            ))),
        }
    }

    pub(super) fn is_mobile_client(&self, client_id: u64) -> bool {
        self.clients
            .get(&client_id)
            .is_some_and(|client| client.kind == ClientKind::Mobile)
    }

    fn require_request_allowed(&self, client_id: u64, request_type: &str) -> HostResult<()> {
        let Some(client) = self.clients.get(&client_id) else {
            return Err(HostError::state(
                "Terminal host client is not authenticated.",
            ));
        };
        if client.kind == ClientKind::Local || mobile_request_allowed(request_type) {
            return Ok(());
        }
        Err(HostError::state(format!(
            "Mobile clients cannot call terminal host request: {request_type}"
        )))
    }

    pub(super) async fn create_or_attach(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let session_id = require_string(payload, "sessionId")?;
        let workspace_id = require_string(payload, "workspaceId")?;
        let tab_id = require_string(payload, "tabId")?;
        let working_directory = require_string(payload, "workingDirectory")?;

        let max_bytes = self.config.scrollback_bytes as usize;

        // Live session: attach only. Dead session: remint with the same handle so
        // ALERA_TERMINAL_HANDLE / orchestration dispatch targets stay valid.
        if self.sessions.contains_key(&session_id) {
            let running = self.sessions.get(&session_id).is_some_and(Session::running);
            if running {
                self.flush_all_output(&session_id);
                let session = self.sessions.get_mut(&session_id).expect("just checked");
                session.attach(client_id);
                return Ok(session.attachment_payload(false));
            }
        }
        let (initial_scrollback, initial_output_stream_bytes) = self
            .take_terminal_restart_state(&session_id, &workspace_id, &tab_id, max_bytes)
            .await;

        let launch = TerminalHostLaunch::from_json(&Value::Object(
            require_object(payload.get("launch"), "launch")?.clone(),
        ))?;
        let cols = int_or(payload, "cols", 80) as u16;
        let rows = int_or(payload, "rows", 24) as u16;
        self.start_new_terminal_session(
            session_id.clone(),
            workspace_id,
            tab_id,
            working_directory,
            launch,
            cols,
            rows,
            initial_scrollback,
            initial_output_stream_bytes,
        )
        .await?;
        let session = self.sessions.get_mut(&session_id).expect("just inserted");
        session.attach(client_id);
        Ok(session.attachment_payload(true))
    }
}

/// Validate the request envelope. The payload-object check precedes the id/type
/// validity check to preserve the existing wire error order.
fn extract_request(obj: &Map<String, Value>) -> HostResult<(String, Value)> {
    let payload = match obj.get("payload") {
        Some(value @ Value::Object(_)) => value.clone(),
        _ => return Err(HostError::format("request payload must be a JSON object.")),
    };
    let id_ok = obj.get("id").and_then(Value::as_i64).is_some();
    let request_type = obj.get("type").and_then(Value::as_str);
    match (id_ok, request_type) {
        (true, Some(request_type)) => Ok((request_type.to_string(), payload)),
        _ => Err(HostError::format("Terminal host request is malformed.")),
    }
}

fn require_string(payload: &Value, key: &str) -> HostResult<String> {
    match payload.get(key) {
        Some(Value::String(value)) => Ok(value.clone()),
        _ => Err(HostError::format(
            "createOrAttach requires session metadata.",
        )),
    }
}

pub(super) fn require_string_key(payload: &Value, key: &str) -> HostResult<String> {
    match payload.get(key) {
        Some(Value::String(value)) if !value.trim().is_empty() => Ok(value.clone()),
        _ => Err(HostError::format(format!("{key} is required."))),
    }
}

fn string_array(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|item| item.as_str().map(str::to_string))
            .collect(),
        _ => Vec::new(),
    }
}

pub(super) fn optional_string_key(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(super) fn terminal_session_id_from_tab(tab: &WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get("terminalSessionId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn terminal_read_window(
    base_cursor: u64,
    end_cursor: u64,
    cursor: Option<u64>,
    max_bytes: u64,
) -> (u64, u64, u64) {
    let requested = cursor.unwrap_or_else(|| end_cursor.saturating_sub(max_bytes).max(base_cursor));
    let start = requested.clamp(base_cursor, end_cursor);
    let next = start.saturating_add(max_bytes).min(end_cursor);
    (requested, start, next)
}

fn align_terminal_text_window(
    bytes: &[u8],
    base_cursor: u64,
    start_cursor: u64,
    next_cursor: u64,
) -> (u64, u64) {
    let mut start = (start_cursor - base_cursor) as usize;
    let mut end = (next_cursor - base_cursor) as usize;
    if let Some(scalar_end) = containing_utf8_scalar_end(bytes, start) {
        start = scalar_end;
    }
    end = end.max(start).min(bytes.len());
    while let Some(incomplete_at) = trailing_incomplete_utf8_start(&bytes[start..end]) {
        if end < bytes.len() {
            end += 1;
        } else {
            end = start + incomplete_at;
            break;
        }
    }
    (base_cursor + start as u64, base_cursor + end as u64)
}

fn containing_utf8_scalar_end(bytes: &[u8], index: usize) -> Option<usize> {
    if index >= bytes.len() || !is_utf8_continuation(bytes[index]) {
        return None;
    }
    let search_start = index.saturating_sub(3);
    for lead in (search_start..index).rev() {
        if is_utf8_continuation(bytes[lead]) {
            continue;
        }
        for end in (index + 1)..=(lead + 4).min(bytes.len()) {
            if std::str::from_utf8(&bytes[lead..end]).is_ok() {
                return Some(end);
            }
        }
        return None;
    }
    None
}

fn trailing_incomplete_utf8_start(bytes: &[u8]) -> Option<usize> {
    let mut offset = 0;
    while offset < bytes.len() {
        match std::str::from_utf8(&bytes[offset..]) {
            Ok(_) => return None,
            Err(error) => {
                offset += error.valid_up_to();
                match error.error_len() {
                    Some(length) => offset += length,
                    None => return Some(offset),
                }
            }
        }
    }
    None
}

fn is_utf8_continuation(byte: u8) -> bool {
    byte & 0b1100_0000 == 0b1000_0000
}

fn parse_payload<T>(payload: &Value) -> HostResult<T>
where
    T: serde::de::DeserializeOwned,
{
    serde_json::from_value(payload.clone()).map_err(|error| HostError::format(error.to_string()))
}

fn json_result<T, E>(result: Result<T, E>) -> HostResult<Value>
where
    T: serde::Serialize,
    E: std::fmt::Display,
{
    result
        .map_err(|error| HostError::state(error.to_string()))
        .and_then(|value| {
            serde_json::to_value(value).map_err(|error| HostError::format(error.to_string()))
        })
}

#[cfg(test)]
mod tests;

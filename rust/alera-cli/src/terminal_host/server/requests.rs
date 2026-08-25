use alera_core::{
    git as core_git,
    runtime::{
        LinkedReview, Project, ProjectConfig, WorkbenchLayoutRecord, Workspace, WorkspaceTabRecord,
        WorkspaceTag,
    },
};
use chrono::{DateTime, Utc};
use serde_json::{json, Map, Value};

use crate::mobile_access::{
    apply_mobile_settings_update_resolved, cancel_mobile_pairing_offer,
    create_mobile_pairing_offer_for_settings, delete_mobile_device, list_mobile_devices,
    mobile_status, pair_mobile_device, prepare_mobile_pairing_offer_settings_resolved,
    rename_mobile_device, revoke_mobile_device, MobileDevicePairRequest,
    MobilePairingCreateRequest, MobileSettingsUpdateRequest,
};
use crate::ssh_bootstrap::{build_ssh_bootstrap_plan, SshTargetBootstrapRequest};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{
    error_response, event, int_or, ok_response, TerminalHostConfig,
};
use crate::terminal_host::session::SessionDriver;

use super::host_service_requests::required_non_blank;
pub(super) use super::request_payloads::{json_result, parse_payload};
use super::runtime_mutation_barrier::conflicts_with_runtime_mutation;
use super::{ClientKind, ServerActor, ServerCommand};

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectConfigUpsertRequest {
    project_id: String,
    config: ProjectConfig,
    #[serde(default)]
    updated_at: Option<DateTime<Utc>>,
}

impl ServerActor {
    /// Parse and dispatch one client line, then write the response. Malformed
    /// messages without a request id drop the connection because there is no
    /// response target.
    pub(super) async fn handle_line(&mut self, client_id: u64, line: String) {
        let mut restart_after_response = false;
        let mut shutdown_after_response = false;
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
                restart_after_response = request_type == "host.restart";
                shutdown_after_response = request_type == "host.shutdown";
                if let Some(id) = request_id {
                    if self.emulator_requests.has_runtime_mutations()
                        && conflicts_with_runtime_mutation(&request_type)
                    {
                        self.client_write(
                            client_id,
                            error_response(
                                id,
                                &HostError::state(
                                    "A runtime mutation is in progress. Wait for it to finish and retry.",
                                ),
                            ),
                        );
                        return;
                    }
                    if request_type.starts_with("browser.") {
                        match self
                            .handle_browser_request(client_id, id, &request_type, &payload)
                            .await
                        {
                            // Routed calls are parked until the app driver
                            // completes, times out, or disconnects.
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
                    match self
                        .try_start_deferred_request(client_id, id, &request_type, &payload)
                        .await
                    {
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
                    if restart_after_response {
                        self.restart_runtime_after_client_write(client_id);
                    }
                    if shutdown_after_response {
                        self.shutdown_runtime_after_client_write(client_id);
                    }
                } else if shutdown_after_response {
                    // There is no response to order against for a malformed
                    // request without an id, so preserve the legacy shutdown
                    // behavior for that case.
                    let _ = self.inbox.send(ServerCommand::RequestedShutdown);
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

    async fn handle_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        match request_type {
            "hello" => self.handle_hello(client_id, payload),
            "mobile.hello" => self.handle_mobile_hello(client_id, payload).await,
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
            request_type if request_type.starts_with("codex.") => {
                self.handle_codex_request(client_id, request_type, payload)
                    .await
            }
            "mobile.workspaceQuickOpen.stop" => self.stop_mobile_workspace_quick_open(payload),
            "configure" => {
                self.require_auth(client_id)?;
                // Crash reporting is a live switch rather than a start-up flag:
                // the sidecar outlives the app, so requiring a restart would
                // leave the setting lying about what is actually happening.
                if let Some(enabled) = payload.get("crashReporting").and_then(Value::as_bool) {
                    crate::terminal_host::diagnostics::sentry_reporting::set_enabled(enabled);
                }
                let config = TerminalHostConfig::from_json(payload)?;
                self.apply_config(config).await;
                Ok(json!({}))
            }
            "host.promotePersistent" => self.promote_persistent(),
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
                    + self.coordinators.len()
                    + self.emulator_requests.outstanding()
                    + self.emulators.as_ref().map_or(0, |emulators| {
                        emulators
                            .try_lock()
                            .map_or(1, |manager| manager.active_count())
                    })
                    + self.browser.active_jobs();
                let active_agents = self.agent_presence_items().as_array().map_or(0, Vec::len);
                if !force {
                    if let Some(message) = host_shutdown_busy_message(
                        active_agents,
                        active_sessions,
                        active_jobs,
                        self.account_push.active_subscriptions > 0,
                    ) {
                        return Err(HostError::state(message));
                    }
                }
                Ok(json!({
                    "stopped": true,
                    "forced": force,
                    "activeSessions": active_sessions,
                    "activeJobs": active_jobs,
                    "activeAgents": active_agents,
                    "activePushSubscriptions": self.account_push.active_subscriptions,
                }))
            }
            "host.restart" => {
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
                    + self.coordinators.len()
                    + self.emulator_requests.outstanding()
                    + self.emulators.as_ref().map_or(0, |emulators| {
                        emulators
                            .try_lock()
                            .map_or(1, |manager| manager.active_count())
                    })
                    + self.browser.active_jobs();
                let active_agents = self.agent_presence_items().as_array().map_or(0, Vec::len);
                if !force {
                    if let Some(message) = host_shutdown_busy_message(
                        active_agents,
                        active_sessions,
                        active_jobs,
                        self.account_push.active_subscriptions > 0,
                    ) {
                        return Err(HostError::state(message));
                    }
                }
                Ok(json!({
                    "restarting": true,
                    "forced": force,
                    "activeSessions": active_sessions,
                    "activeJobs": active_jobs,
                    "activeAgents": active_agents,
                    "activePushSubscriptions": self.account_push.active_subscriptions,
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
                let session_id = self.require_session_id(payload)?;
                let restored = self.reclaim_terminal_for_desktop(&session_id);
                Ok(json!({ "restored": restored }))
            }
            "terminal.driver.list" => {
                self.require_auth(client_id)?;
                Ok(self.terminal_driver_list_payload())
            }
            "terminal.pulse.status" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, "terminal.pulse.status")?;
                self.terminal_pulse_status(payload).await
            }
            "setOutputPaused" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                let paused = payload
                    .get("paused")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                self.flush_all_output(&session_id);
                Ok(self.set_output_paused_for_client(&session_id, client_id, paused))
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
                self.queue_terminal_exit_push(&session_id, None).await;
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
            "terminal.restart" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, "terminal.restart")?;
                if self.is_mobile_client(client_id) {
                    self.restart_mobile_terminal(client_id, payload).await
                } else {
                    self.restart_terminal(client_id, payload).await
                }
            }
            "status.get" => {
                self.require_auth(client_id)?;
                Ok(self.host_status_payload())
            }
            "account.status" => self.account_status().await,
            "account.signIn.cancel" => {
                self.require_auth(client_id)?;
                Ok(self.cancel_account_sign_in())
            }
            "resources.snapshot" => {
                self.require_auth(client_id)?;
                self.handle_resource_snapshot(payload)
            }
            ty if ty.starts_with("agentCanvas.") => self.canvas(client_id, ty, payload).await,
            _ if request_type.starts_with("automation.") => {
                self.handle_automation_request(client_id, request_type, payload)
                    .await
            }
            "shellEnvironment.reload" => {
                self.require_auth(client_id)?;
                let (path_count, variable_count) =
                    crate::login_shell_environment::reload_login_shell_environment().await;
                Ok(json!({
                    "pathEntryCount": path_count,
                    "variableCount": variable_count,
                }))
            }
            _ if request_type.starts_with("computer.") => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                match self.handle_computer_request(request_type, payload).await? {
                    Some(value) => Ok(value),
                    None => Err(HostError::state(format!(
                        "Unknown computer-use request: {request_type}"
                    ))),
                }
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
            "mobile.runtimeSettings.get" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.runtime_settings().await)
            }
            "runtimeSettings.update" => {
                self.require_auth(client_id)?;
                self.apply_mobile_runtime_settings(payload).await
            }
            "mobile.runtimeSettings.update" => {
                self.require_auth(client_id)?;
                const ALLOWED: [&str; 8] = [
                    "workspaceDirectory",
                    "confirmProjectRemoval",
                    "confirmWorkspaceRemoval",
                    "defaultAgentProfileId",
                    "agentStatusHooks",
                    "agentQuotas",
                    "mobilePushNotifications",
                    "automation",
                ];
                if let Some(key) = payload
                    .as_object()
                    .and_then(|object| object.keys().find(|key| !ALLOWED.contains(&key.as_str())))
                {
                    return Err(HostError::format(format!(
                        "Unsupported mobile setting: {key}."
                    )));
                }
                self.apply_mobile_runtime_settings(payload).await
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
                let project_id = workspace.project_id.clone();
                let value = json_result(self.runtime_store.upsert_workspace(workspace).await)?;
                self.broadcast_workspaces_changed(Some(&project_id));
                Ok(value)
            }
            "workspace.setPinned" => self.handle_workspace_pinning(client_id, payload).await,
            "workspace.rename" => self.rename_workspace_request(client_id, payload).await,
            "workspace.repositoryWebUrl" => {
                self.workspace_repository_web_url(client_id, payload).await
            }
            "tab.list" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let tabs = self
                    .runtime_store
                    .list_workspace_tabs(&workspace_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                if self.is_mobile_client(client_id) {
                    Ok(self.mobile_workspace_tabs_payload(
                        self.workspace_tabs_for_client(client_id, tabs),
                    ))
                } else {
                    Ok(json!(self.workspace_tabs_for_client(client_id, tabs)))
                }
            }
            "tab.find" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                let tab = self
                    .runtime_store
                    .find_workspace_tab(&id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .and_then(|tab| self.workspace_tab_for_client(client_id, tab));
                Ok(json!(tab))
            }
            "tab.upsert" => {
                self.require_auth(client_id)?;
                let mut tab: WorkspaceTabRecord = parse_payload(payload)?;
                if let Some(stored) = self
                    .runtime_store
                    .find_workspace_tab(&tab.id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                {
                    super::tab_compatibility::preserve_host_owned_tab_payload(&stored, &mut tab);
                }
                let value = self.upsert_workspace_tab_and_spawn(tab).await?;
                Ok(json!(self.workspace_tab_for_client(client_id, value)))
            }
            "tab.rename" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                let title = require_string_key(payload, "title")?;
                let tab = self
                    .runtime_store
                    .rename_workspace_tab(&id, &title)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                let workspace_id = tab.workspace_id.clone();
                let tab = self.workspace_tab_for_client(client_id, tab);
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
                Ok(json!(tab))
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
                self.broadcast_workspaces_changed(None);
                Ok(value)
            }
            "workspaceTag.remove" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                json_result(self.runtime_store.remove_tag(&id).await)?;
                self.broadcast_authenticated(event("workspaceTagsChanged", json!({})));
                self.broadcast_workspaces_changed(None);
                Ok(json!({}))
            }
            "workspaceTag.assign" => {
                self.require_auth(client_id)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let tag_id = require_string_key(payload, "tagId")?;
                json_result(self.runtime_store.assign_tag(&workspace_id, &tag_id).await)?;
                self.broadcast_workspaces_changed(None);
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
                self.broadcast_workspaces_changed(None);
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
                self.broadcast_workspaces_changed(None);
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
                self.broadcast_workspaces_changed(None);
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
            "agentProfile.list" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.agent_profile_list().await
            }
            "agentProfile.launch" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.launch_agent_profile(Some(client_id), payload).await
            }
            "agentProfile.launchIdempotent" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                required_non_blank(payload, "clientMutationId")?;
                self.launch_agent_profile(Some(client_id), payload).await
            }
            "mobile.promptImage.start" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_mobile_prompt_image_upload(payload)
            }
            "mobile.promptImage.chunk" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.append_mobile_prompt_image_chunk(payload)
            }
            "mobile.promptImage.complete" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.complete_mobile_prompt_image_upload(payload)
            }
            "mobile.promptImage.cancel" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.cancel_mobile_prompt_image_upload(payload)
            }
            "aiText.cancel" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.cancel_ai_assist(payload)
            }
            "mobile.aiDictation.transcribe" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                super::ai_dictation_requests::transcribe_mobile(payload, &self.runtime_dir).await
            }
            "mobile.aiDictation.capabilities" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                super::ai_dictation_requests::capabilities(&self.runtime_dir)
            }
            "aiDictation.cancel" | "mobile.aiDictation.cancel" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                super::ai_dictation_requests::cancel(payload)
            }
            "aiDictation.credentials.status" => {
                self.require_authenticated_local_request(client_id, request_type)?;
                self.ai_dictation_credential_status(payload).await
            }
            "aiDictation.credentials.save" => {
                self.require_authenticated_local_request(client_id, request_type)?;
                self.save_ai_dictation_credential(payload).await
            }
            "aiDictation.credentials.clear" => {
                self.require_authenticated_local_request(client_id, request_type)?;
                self.clear_ai_dictation_credential().await
            }
            "agentProfile.upsert" => {
                self.require_auth(client_id)?;
                self.agent_profile_upsert(payload).await
            }
            "agentProfile.reorder" => {
                self.require_authenticated_local_request(client_id, request_type)?;
                self.agent_profile_reorder(payload).await
            }
            "agentProfile.removalImpact" => {
                self.require_auth(client_id)?;
                self.agent_profile_removal_impact(payload).await
            }
            "agentProfile.remove" => {
                self.require_auth(client_id)?;
                self.agent_profile_remove(payload).await
            }
            "sshTarget.list" => {
                self.require_auth(client_id)?;
                self.ssh_target_list().await
            }
            "sshTarget.upsert" => {
                self.require_auth(client_id)?;
                self.ssh_target_upsert(payload).await
            }
            "sshTarget.remove" => {
                self.require_auth(client_id)?;
                self.ssh_target_remove(payload).await
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
            "mobile.device.delete" => {
                self.require_auth(client_id)?;
                let id = require_string_key(payload, "id")?;
                json_result(delete_mobile_device(&self.runtime_store, &id).await)?;
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

pub(super) fn require_string(payload: &Value, key: &str) -> HostResult<String> {
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

fn host_shutdown_busy_message(
    active_agents: usize,
    active_sessions: usize,
    active_jobs: usize,
    has_push_subscriptions: bool,
) -> Option<String> {
    if active_agents == 0 && active_sessions == 0 && active_jobs == 0 && !has_push_subscriptions {
        return None;
    }
    Some(format!(
        "Runtime host has {active_agents} active agent(s), {active_sessions} active terminal session(s), {active_jobs} active background job(s), and {} active push subscription(s). Retry with --force to stop it.",
        usize::from(has_push_subscriptions)
    ))
}

#[cfg(test)]
#[path = "requests/access_cases.rs"]
mod access_cases;

#[cfg(test)]
mod tests;

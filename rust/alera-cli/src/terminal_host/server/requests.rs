use std::collections::BTreeMap;

use alera_core::{
    git as core_git,
    runtime::{
        LinkedReview, Project, ProjectConfig, SshTarget, WorkbenchLayoutRecord, Workspace,
        WorkspaceTabRecord, WorkspaceTag,
    },
};
use chrono::{DateTime, Utc};
use serde_json::{json, Map, Value};

use crate::managed_workspace::{
    create_managed_workspace, remove_managed_workspace, ManagedWorkspaceCreateRequest,
    ManagedWorkspaceRemoveRequest,
};
use crate::mobile_access::{
    apply_mobile_settings_update, authenticate_mobile_device,
    create_mobile_pairing_offer_for_settings, list_mobile_devices, mobile_status,
    pair_mobile_device, prepare_mobile_pairing_offer_settings, revoke_mobile_device,
    MobileDevicePairRequest, MobilePairingCreateRequest, MobileSettingsUpdateRequest,
    MOBILE_PROTOCOL_VERSION,
};
use crate::ssh_bootstrap::{build_ssh_bootstrap_plan, SshTargetBootstrapRequest};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{
    error_response, event, int_or, ok_response, require_object, TerminalHostConfig,
    TerminalHostLaunch, PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
    RUNTIME_HOST_CAPABILITY, RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CAPABILITY, RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
};
use crate::terminal_host::session::Session;
use uuid::Uuid;

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
                    client.app_client =
                        payload.get("clientKind").and_then(Value::as_str) == Some("app");
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
            "createOrAttach" => {
                self.require_auth(client_id)?;
                self.create_or_attach(client_id, payload).await
            }
            "write" => {
                self.require_auth(client_id)?;
                Ok(json!({}))
            }
            "resize" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                let cols = int_or(payload, "cols", 80);
                let rows = int_or(payload, "rows", 24);
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.resize(cols as u16, rows as u16);
                }
                Ok(json!({}))
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
                self.immediate_checkpoint(&session_id).await;
                Ok(json!({}))
            }
            "terminate" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                self.flush_all_output(&session_id);
                self.await_output_writes(&session_id).await;
                self.cleanup_orchestration_for_closed_session(
                    &session_id,
                    "terminal was explicitly terminated",
                )
                .await;
                let store = self.store.clone();
                if let Some(mut session) = self.sessions.remove(&session_id) {
                    session.terminate(true, &store).await;
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
                    "protocolVersion": PROTOCOL_VERSION,
                    "runtime": "alera",
                    "runtimeCapabilities": [
                        RUNTIME_HOST_CAPABILITY,
                        RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                        RUNTIME_HOST_MOBILE_CAPABILITY,
                        RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
                    ],
                    "authenticated": true,
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
                let workspace_directory = match payload.get("workspaceDirectory") {
                    Some(Value::String(value)) => Some(value.as_str()),
                    Some(Value::Null) | None => None,
                    _ => {
                        return Err(HostError::format(
                            "workspaceDirectory must be a string or null.",
                        ))
                    }
                };
                let value = json_result(
                    self.runtime_store
                        .set_workspace_directory(workspace_directory)
                        .await,
                )?;
                self.broadcast_authenticated(event("runtimeSettingsChanged", json!({})));
                Ok(value)
            }
            "project.list" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.list_projects().await)
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
                Ok(json!({}))
            }
            "projectConfig.find" => {
                self.require_auth(client_id)?;
                let project_id = require_string_key(payload, "projectId")?;
                json_result(self.runtime_store.find_project_config(&project_id).await)
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
                let value = json_result(self.runtime_store.upsert_workspace_tab(tab).await)?;
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
                Ok(value)
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
                let next = apply_mobile_settings_update(current.clone(), request)
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
                    prepare_mobile_pairing_offer_settings(current.clone(), &request)
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
            other => Err(HostError::state(format!(
                "Unknown terminal host request: {other}"
            ))),
        }
    }

    fn is_mobile_client(&self, client_id: u64) -> bool {
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

    async fn create_mobile_terminal(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let workspace_id = require_string_key(payload, "workspaceId")?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
        let tab_id = Uuid::new_v4().to_string();
        let session_id = Uuid::new_v4().to_string();
        let title =
            optional_string_key(payload, "title").unwrap_or_else(|| "Mobile Terminal".into());
        let now = Utc::now();
        let tab = WorkspaceTabRecord {
            id: tab_id.clone(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".to_string(),
            title,
            created_at: now,
            updated_at: now,
            payload: json!({
                "terminalSessionId": session_id,
                "source": "mobile",
            }),
        };
        let tab = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let attachment_payload =
            mobile_terminal_attachment_payload(&workspace, &tab.id, &session_id, payload);
        match self.create_or_attach(client_id, &attachment_payload).await {
            Ok(attachment) => {
                self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
                Ok(json!({
                    "tab": tab,
                    "attachment": attachment,
                }))
            }
            Err(error) => {
                let _ = self.runtime_store.remove_workspace_tab(&tab.id).await;
                Err(error)
            }
        }
    }

    async fn attach_mobile_terminal(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace tab not found: {tab_id}")))?;
        if tab.kind != "terminal" {
            return Err(HostError::state(format!(
                "Workspace tab is not a terminal: {}",
                tab.id
            )));
        }
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("Workspace not found: {}", tab.workspace_id))
            })?;
        let session_id = optional_string_key(payload, "sessionId")
            .or_else(|| terminal_session_id_from_tab(&tab))
            .unwrap_or_else(|| tab.id.clone());
        let attachment_payload =
            mobile_terminal_attachment_payload(&workspace, &tab.id, &session_id, payload);
        let attachment = self
            .create_or_attach(client_id, &attachment_payload)
            .await?;
        Ok(json!({
            "tab": tab,
            "attachment": attachment,
        }))
    }

    async fn create_or_attach(&mut self, client_id: u64, payload: &Value) -> HostResult<Value> {
        let session_id = require_string(payload, "sessionId")?;
        let workspace_id = require_string(payload, "workspaceId")?;
        let tab_id = require_string(payload, "tabId")?;
        let working_directory = require_string(payload, "workingDirectory")?;

        let store = self.store.clone();
        let max_bytes = self.config.scrollback_bytes as usize;
        let mut initial_scrollback = Vec::new();

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
            if let Some(mut dead) = self.sessions.remove(&session_id) {
                initial_scrollback = dead.buffer.to_bytes();
                dead.terminate(false, &store).await;
            }
            self.agent_presence.remove(&session_id);
        } else if let Some(restored) = Session::restore_exited(
            session_id.clone(),
            workspace_id.clone(),
            tab_id.clone(),
            &store,
            max_bytes,
        )
        .await
        {
            initial_scrollback = restored.buffer.to_bytes();
        }

        let launch = TerminalHostLaunch::from_json(&Value::Object(
            require_object(payload.get("launch"), "launch")?.clone(),
        ))?;
        let cols = int_or(payload, "cols", 80) as u16;
        let rows = int_or(payload, "rows", 24) as u16;
        let inbox = self.inbox.clone();
        let reader_session_id = session_id.clone();
        let session = Session::start(
            session_id.clone(),
            workspace_id,
            tab_id,
            working_directory,
            &launch,
            cols,
            rows,
            max_bytes,
            &initial_scrollback,
            &store,
            move |event| {
                let _ = inbox.send(ServerCommand::Pty {
                    session_id: reader_session_id.clone(),
                    event,
                });
            },
        )
        .await?;
        self.sessions.insert(session_id.clone(), session);
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

fn require_string_key(payload: &Value, key: &str) -> HostResult<String> {
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

fn optional_string_key(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn terminal_session_id_from_tab(tab: &WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get("terminalSessionId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn mobile_terminal_attachment_payload(
    workspace: &Workspace,
    tab_id: &str,
    session_id: &str,
    payload: &Value,
) -> Value {
    json!({
        "sessionId": session_id,
        "workspaceId": workspace.id.clone(),
        "tabId": tab_id,
        "workingDirectory": workspace.path.clone(),
        "launch": default_mobile_terminal_launch(&workspace.path),
        "cols": int_or(payload, "cols", 80),
        "rows": int_or(payload, "rows", 24),
    })
}

fn default_mobile_terminal_launch(working_directory: &str) -> Value {
    let environment = mobile_terminal_environment();
    #[cfg(windows)]
    {
        let shell = std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string());
        json!({
            "label": "shell",
            "shell": shell,
            "arguments": ["/d", "/s", "/k", &format!("cd /d {}", cmd_quote(working_directory))],
            "environment": environment,
        })
    }
    #[cfg(not(windows))]
    {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
        let command = format!(
            "cd {} || true; exec {}",
            sh_quote(working_directory),
            sh_quote(&shell)
        );
        json!({
            "label": "shell",
            "shell": "/bin/sh",
            "arguments": ["-c", command],
            "environment": environment,
        })
    }
}

fn mobile_terminal_environment() -> BTreeMap<String, String> {
    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    #[cfg(not(windows))]
    {
        environment
            .entry("PATH".to_string())
            .or_insert_with(|| "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin".to_string());
        environment
            .entry("TERM".to_string())
            .or_insert_with(|| "xterm-256color".to_string());
    }
    environment
}

#[cfg(not(windows))]
fn sh_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

#[cfg(windows)]
fn cmd_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}

fn mobile_request_allowed(request_type: &str) -> bool {
    matches!(
        request_type,
        "status.get"
            | "mobile.status.get"
            | "project.list"
            | "project.branches.list"
            | "workspace.list"
            | "workspace.listAll"
            | "workspace.find"
            | "tab.list"
            | "tab.find"
            | "linkedReview.find"
            | "layout.find"
            | "workspaceTag.list"
            | "workspaceRelation.list"
            | "workspaceCascade.preview"
            | "terminal.create"
            | "terminal.attach"
            | "write"
            | "resize"
            | "setOutputPaused"
            | "detach"
            | "terminate"
    )
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
mod tests {
    use super::*;

    #[test]
    fn mobile_allowlist_excludes_managed_workspace_mutations() {
        assert!(!mobile_request_allowed("workspace.createManaged"));
        assert!(!mobile_request_allowed("workspace.removeManaged"));
    }
}

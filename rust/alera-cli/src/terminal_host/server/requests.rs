use alera_core::runtime::{
    Project, SshTarget, WorkbenchLayoutRecord, Workspace, WorkspaceTabRecord, WorkspaceTag,
};
use serde_json::{json, Map, Value};
use uuid::Uuid;

use crate::ssh_bootstrap::{build_ssh_bootstrap_plan, SshTargetBootstrapRequest};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{
    decode_bytes, error_response, event, int_or, ok_response, require_object, TerminalHostConfig,
    TerminalHostLaunch, PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
    RUNTIME_HOST_CAPABILITY,
};
use crate::terminal_host::session::Session;

use super::{ServerActor, ServerCommand};

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
                let session_id = self.require_session(payload)?;
                let bytes = decode_bytes(payload.get("dataBase64"))?;
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.write(&bytes);
                }
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
                self.flush_output_batch(&session_id);
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
                self.flush_output_batch(&session_id);
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.detach(client_id);
                }
                self.immediate_checkpoint(&session_id).await;
                Ok(json!({}))
            }
            "terminate" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                self.flush_output_batch(&session_id);
                self.await_output_writes(&session_id).await;
                let store = self.store.clone();
                if let Some(mut session) = self.sessions.remove(&session_id) {
                    session.terminate(true, &store).await;
                }
                self.schedule_shutdown_if_idle();
                Ok(json!({}))
            }
            "status.get" => {
                self.require_auth(client_id)?;
                Ok(json!({
                    "protocolVersion": PROTOCOL_VERSION,
                    "runtime": "alera",
                    "runtimeCapabilities": [RUNTIME_HOST_CAPABILITY, RUNTIME_HOST_BOOTSTRAP_CAPABILITY],
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
            "project.list" => {
                self.require_auth(client_id)?;
                json_result(self.runtime_store.list_projects().await)
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
            "pairing.create" => {
                self.require_auth(client_id)?;
                Ok(json!({
                    "pairingId": Uuid::new_v4().to_string(),
                    "status": "pending",
                    "transport": "webSocket",
                }))
            }
            other => Err(HostError::state(format!(
                "Unknown terminal host request: {other}"
            ))),
        }
    }

    async fn create_or_attach(&mut self, client_id: u64, payload: &Value) -> HostResult<Value> {
        let session_id = require_string(payload, "sessionId")?;
        let workspace_id = require_string(payload, "workspaceId")?;
        let tab_id = require_string(payload, "tabId")?;
        let working_directory = require_string(payload, "workingDirectory")?;

        if self.sessions.contains_key(&session_id) {
            self.flush_output_batch(&session_id);
            let session = self.sessions.get_mut(&session_id).expect("just checked");
            session.attach(client_id);
            return Ok(session.attachment_payload(false));
        }

        let store = self.store.clone();
        let max_bytes = self.config.scrollback_bytes as usize;
        if let Some(restored) = Session::restore_exited(
            session_id.clone(),
            workspace_id.clone(),
            tab_id.clone(),
            &store,
            max_bytes,
        )
        .await
        {
            self.sessions.insert(session_id.clone(), restored);
            if let Some(session) = self.sessions.get_mut(&session_id) {
                session.set_max_bytes(max_bytes);
            }
            self.immediate_checkpoint(&session_id).await;
            let session = self.sessions.get_mut(&session_id).expect("just inserted");
            session.attach(client_id);
            return Ok(session.attachment_payload(false));
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

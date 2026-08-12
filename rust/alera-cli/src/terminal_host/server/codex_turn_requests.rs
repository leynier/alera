use serde_json::{json, Value};
use uuid::Uuid;

use alera_core::runtime::{Workspace, WorkspaceTabRecord};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::codex_state::{
    active_turn_id, append_question_answer, remove_pending_request, set_thread_and_snapshot,
    snapshot, tab_thread_id,
};
use super::super::codex_tab_lifecycle::{
    active_cwd, normalize_configuration, set_active_cwd, set_configuration,
    set_thread_owned_by_alera,
};
use super::super::codex_thread_identity::{
    apply_manual_thread_title, ensure_expected_thread, pending_thread_name,
};
use super::super::requests::require_string_key;
use super::super::ServerActor;
use super::codex_thread_sessions::allowed_cwd;
use super::{copy_optional, turn_params};

impl ServerActor {
    pub(super) async fn start_codex_turn(&mut self, payload: &Value) -> HostResult<Value> {
        let (tab, thread_id, current_cwd) = self.materialize_codex_thread(payload).await?;
        let original_input = payload.get("input").cloned().unwrap_or_else(|| json!([]));
        let app_server_input = super::super::codex_workspace_inputs::normalize_legacy_codex_inputs(
            original_input.clone(),
            &current_cwd,
        )
        .await?;
        let mut turn_payload = payload.clone();
        turn_payload["cwd"] = Value::String(current_cwd);
        let params = turn_params(&turn_payload, &thread_id, app_server_input);
        let client_user_message_id = params
            .get("clientUserMessageId")
            .and_then(Value::as_str)
            .map(str::to_string);
        let result = self.codex_server_request("turn/start", params).await?;
        let turn_id = result
            .pointer("/turn/id")
            .or_else(|| result.get("turnId"))
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| format!("queued-{}", Uuid::new_v4()));
        self.persist_codex_user_input(
            &tab.id,
            &original_input,
            payload.get("userMessage"),
            &turn_id,
            client_user_message_id.as_deref(),
            false,
        )
        .await;
        Ok(result)
    }

    pub(in crate::terminal_host::server) async fn materialize_codex_thread(
        &mut self,
        payload: &Value,
    ) -> HostResult<(WorkspaceTabRecord, String, String)> {
        let mut tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        ensure_expected_thread(payload, tab_thread_id(&tab).as_deref())?;
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("Workspace not found: {}", tab.workspace_id))
            })?;
        let workspaces = self.codex_workspaces(None).await?;
        let current_cwd = request_cwd(&tab, &workspace, &workspaces)?;
        let configuration = payload
            .get("configuration")
            .map(normalize_configuration)
            .transpose()
            .map_err(HostError::format)?;
        if let Some(configuration) = configuration {
            set_configuration(&mut tab, configuration);
        }
        let pending_thread_name = pending_thread_name(&tab);
        let mut created_thread = false;
        let thread_id = if let Some(thread_id) = tab_thread_id(&tab) {
            thread_id
        } else {
            created_thread = true;
            let server = self.ensure_codex_server(Some(&current_cwd)).await?;
            let mut params = json!({
                "cwd": current_cwd,
                "approvalPolicy": payload
                    .get("approvalPolicy")
                    .cloned()
                    .unwrap_or(json!("on-request")),
                "runtimeWorkspaceRoots": workspaces.iter().map(|item| item.path.clone()).collect::<Vec<_>>(),
            });
            copy_optional(payload, &mut params, "model");
            let response = server.request("thread/start", params).await?;
            let thread_id = response
                .pointer("/thread/id")
                .or_else(|| response.get("threadId"))
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
                .map(str::to_string)
                .ok_or_else(|| HostError::state("Codex app-server returned no thread id."))?;
            let mut next_snapshot = response
                .get("snapshot")
                .filter(|value| value.is_object())
                .cloned()
                .unwrap_or_else(|| snapshot(&tab));
            if let (Some(name), Some(snapshot)) =
                (pending_thread_name.as_ref(), next_snapshot.as_object_mut())
            {
                snapshot.insert("title".to_string(), Value::String(name.clone()));
            }
            set_active_cwd(&mut tab, &current_cwd);
            set_thread_and_snapshot(&mut tab, &thread_id, next_snapshot);
            set_thread_owned_by_alera(&mut tab, true);
            thread_id
        };
        if created_thread || payload.get("configuration").is_some() {
            tab = self
                .runtime_store
                .upsert_workspace_tab(tab)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            if created_thread {
                if let Some(server) = self.codex.as_ref() {
                    server
                        .record_thread_hydration(
                            &tab.id,
                            &thread_id,
                            &current_cwd,
                            tab.updated_at,
                            None,
                        )
                        .await;
                }
                self.refresh_codex_presence(&tab);
                self.schedule_codex_presence_changed();
                self.broadcast_workspace_tabs_changed(Some(&tab.workspace_id));
            }
        }
        if created_thread {
            if let Some(name) = pending_thread_name {
                self.codex_server_request(
                    "thread/name/set",
                    json!({"threadId": thread_id, "name": name}),
                )
                .await?;
            }
        }
        Ok((tab, thread_id, current_cwd))
    }

    pub(super) async fn interrupt_codex_turn(&mut self, payload: &Value) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        let thread_id = tab_thread_id(&tab)
            .ok_or_else(|| HostError::state("The Codex thread has not been opened."))?;
        let turn_id = payload
            .get("turnId")
            .and_then(Value::as_str)
            .map(str::to_string)
            .or_else(|| active_turn_id(&snapshot(&tab)))
            .ok_or_else(|| HostError::state("There is no active Codex turn."))?;
        let result = self
            .codex_server_request(
                "turn/interrupt",
                json!({"threadId": thread_id, "turnId": turn_id}),
            )
            .await;
        if result.is_ok() {
            self.clear_codex_active_turn(&tab).await;
        }
        result
    }

    pub(super) async fn steer_codex_turn(&mut self, payload: &Value) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        let thread_id = tab_thread_id(&tab)
            .ok_or_else(|| HostError::state("The Codex thread has not been opened."))?;
        let turn_id = require_string_key(payload, "turnId")?;
        let input = payload.get("input").cloned().unwrap_or_else(|| json!([]));
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("Codex workspace no longer exists."))?;
        let workspaces = self.codex_workspaces(None).await?;
        let current_cwd = request_cwd(&tab, &workspace, &workspaces)?;
        let app_server_input = super::super::codex_workspace_inputs::normalize_legacy_codex_inputs(
            input.clone(),
            &current_cwd,
        )
        .await?;
        let client_user_message_id = payload
            .get("clientUserMessageId")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let result = self
            .codex_server_request(
                "turn/steer",
                steer_params(
                    &thread_id,
                    &turn_id,
                    &client_user_message_id,
                    app_server_input,
                ),
            )
            .await?;
        self.persist_codex_user_input(
            &tab.id,
            &input,
            payload.get("userMessage"),
            &turn_id,
            Some(&client_user_message_id),
            true,
        )
        .await;
        Ok(result)
    }

    pub(super) async fn rename_codex_thread(&mut self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let title = require_string_key(payload, "name")?;
        let tab = self.codex_tab(&tab_id).await?;
        if let Some(thread_id) = tab_thread_id(&tab) {
            self.codex_server_request(
                "thread/name/set",
                json!({"threadId": thread_id, "name": title}),
            )
            .await?;
        }
        let mut saved = tab;
        apply_manual_thread_title(&mut saved, &title);
        saved = self
            .runtime_store
            .upsert_workspace_tab(saved)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": tab_thread_id(&saved),
                "snapshot": snapshot(&saved),
            }),
        ));
        Ok(json!(saved))
    }

    pub(super) async fn codex_thread_command(
        &mut self,
        payload: &Value,
        method: &str,
    ) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        let thread_id = tab_thread_id(&tab)
            .ok_or_else(|| HostError::state("The Codex thread has not been opened."))?;
        let mut params = payload.clone();
        if let Some(object) = params.as_object_mut() {
            object.remove("tabId");
            object.insert("threadId".to_string(), Value::String(thread_id));
            if method == "review/start" && !object.contains_key("target") {
                object.insert("target".to_string(), json!({"type": "uncommittedChanges"}));
            }
        }
        self.codex_server_request(method, params).await
    }

    pub(in crate::terminal_host::server) async fn respond_to_codex_request(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        self.respond_to_codex_request_scoped(payload, None).await
    }

    pub(in crate::terminal_host::server) async fn respond_to_codex_request_for_tab(
        &mut self,
        payload: &Value,
        tab_id: &str,
    ) -> HostResult<Value> {
        self.respond_to_codex_request_scoped(payload, Some(tab_id))
            .await
    }

    async fn respond_to_codex_request_scoped(
        &mut self,
        payload: &Value,
        tab_id: Option<&str>,
    ) -> HostResult<Value> {
        let id = payload
            .get("requestId")
            .cloned()
            .ok_or_else(|| HostError::format("Codex response requires requestId."))?;
        let server = self.ensure_codex_server(None).await?;
        let result = payload.get("result").cloned();
        server
            .respond(id.clone(), result, payload.get("error").cloned())
            .await?;
        let tab = match tab_id {
            Some(tab_id) => self
                .find_codex_tab_by_id(tab_id)
                .await?
                .filter(|tab| tab_has_pending_request(tab, &id)),
            None => self.find_codex_tab_for_request(&id).await?,
        };
        if let Some(tab) = tab {
            let mut next = tab;
            append_question_answer(
                &mut next,
                &id,
                payload.get("result").unwrap_or(&Value::Null),
            );
            remove_pending_request(&mut next, &id);
            if let Ok(saved) = self.runtime_store.upsert_workspace_tab(next).await {
                self.refresh_codex_presence(&saved);
                self.schedule_codex_presence_changed();
                self.broadcast_authenticated(crate::terminal_host::protocol::event(
                    "codexThreadChanged",
                    json!({
                        "tabId": saved.id,
                        "workspaceId": saved.workspace_id,
                        "threadId": tab_thread_id(&saved),
                        "snapshot": snapshot(&saved),
                    }),
                ));
            }
        }
        Ok(json!({}))
    }

    pub(super) async fn snooze_codex_request(&mut self, payload: &Value) -> HostResult<Value> {
        let id = payload
            .get("requestId")
            .cloned()
            .ok_or_else(|| HostError::format("Codex snooze requires requestId."))?;
        let Some(mut tab) = self.find_codex_tab_for_request(&id).await? else {
            return Ok(json!({}));
        };
        let Some(requests) = tab
            .payload
            .pointer_mut("/codexSnapshot/pendingRequests")
            .and_then(Value::as_array_mut)
        else {
            return Ok(json!({}));
        };
        let Some(request) = requests
            .iter_mut()
            .find(|request| request.get("id") == Some(&id))
            .and_then(Value::as_object_mut)
        else {
            return Ok(json!({}));
        };
        request.insert("autoResolutionSnoozed".to_string(), Value::Bool(true));
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": tab_thread_id(&saved),
                "snapshot": snapshot(&saved),
            }),
        ));
        Ok(json!({}))
    }
}

fn request_cwd(
    tab: &WorkspaceTabRecord,
    workspace: &Workspace,
    workspaces: &[Workspace],
) -> HostResult<String> {
    let candidate = active_cwd(tab).unwrap_or_else(|| workspace.path.clone());
    allowed_cwd(&candidate, workspaces)
        .ok_or_else(|| HostError::format("Codex cwd must be inside a known workspace."))
}

fn steer_params(
    thread_id: &str,
    turn_id: &str,
    client_user_message_id: &str,
    input: Value,
) -> Value {
    json!({
        "threadId": thread_id,
        "expectedTurnId": turn_id,
        "clientUserMessageId": client_user_message_id,
        "input": input,
    })
}

fn tab_has_pending_request(tab: &WorkspaceTabRecord, request_id: &Value) -> bool {
    snapshot(tab)
        .get("pendingRequests")
        .and_then(Value::as_array)
        .is_some_and(|requests| {
            requests
                .iter()
                .any(|request| request.get("id") == Some(request_id))
        })
}

#[cfg(test)]
#[path = "codex_turn_requests_tests.rs"]
mod tests;

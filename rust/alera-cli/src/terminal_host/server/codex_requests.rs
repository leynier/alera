//! Host requests for Codex threads, turns, approvals, and catalogues.

#[path = "codex_requests_catalogue.rs"]
mod codex_requests_catalogue;

use alera_core::runtime::WorkspaceTabRecord;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::codex_app_server::CodexAppServer;
use super::codex_state::{
    active_turn_id, append_question_answer, append_user_input, is_codex_tab,
    remove_pending_request, snapshot, tab_thread_id,
};
use super::requests::require_string_key;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn handle_codex_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        self.require_codex_client(client_id)?;
        match request_type {
            "codex.tab.create" => self.create_codex_tab(payload).await,
            "codex.thread.open" => self.open_codex_thread(payload).await,
            "codex.thread.snapshot" => self.codex_thread_snapshot(payload).await,
            "codex.model.list" => self.codex_server_request("model/list", json!({})).await,
            "codex.collaborationModes.list" => {
                self.codex_server_request("collaborationMode/list", json!({}))
                    .await
            }
            "codex.skills.list" => self.list_codex_skills(payload).await,
            "codex.apps.list" => self.list_codex_apps(payload).await,
            "codex.turn.start" => self.start_codex_turn(payload).await,
            "codex.turn.interrupt" => self.interrupt_codex_turn(payload).await,
            "codex.turn.steer" => self.steer_codex_turn(payload).await,
            "codex.thread.rename" => self.rename_codex_thread(payload).await,
            "codex.thread.compact" => {
                self.codex_thread_command(payload, "thread/compact/start")
                    .await
            }
            "codex.review.start" => self.codex_thread_command(payload, "review/start").await,
            "codex.response" => self.respond_to_codex_request(payload).await,
            _ => Err(HostError::state(format!(
                "Unknown Codex request: {request_type}"
            ))),
        }
    }

    async fn start_codex_turn(&mut self, payload: &Value) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        let thread_id = tab_thread_id(&tab)
            .ok_or_else(|| HostError::state("Open the Codex thread before sending a message."))?;
        let input = payload.get("input").cloned().unwrap_or_else(|| json!([]));
        let params = turn_params(payload, &thread_id, input.clone());
        let result = self.codex_server_request("turn/start", params).await?;
        let turn_id = result
            .pointer("/turn/id")
            .or_else(|| result.get("turnId"))
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| format!("queued-{}", Uuid::new_v4()));
        let mut next = self.codex_tab(&tab.id).await?;
        append_user_input(&mut next, &input, &turn_id);
        let saved = self
            .runtime_store
            .upsert_workspace_tab(next)
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
        Ok(result)
    }

    async fn interrupt_codex_turn(&mut self, payload: &Value) -> HostResult<Value> {
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

    async fn steer_codex_turn(&mut self, payload: &Value) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        let thread_id = tab_thread_id(&tab)
            .ok_or_else(|| HostError::state("The Codex thread has not been opened."))?;
        let turn_id = require_string_key(payload, "turnId")?;
        self.codex_server_request(
            "turn/steer",
            json!({
                "threadId": thread_id,
                "expectedTurnId": turn_id,
                "input": payload.get("input").cloned().unwrap_or_else(|| json!([])),
            }),
        )
        .await
    }

    async fn rename_codex_thread(&mut self, payload: &Value) -> HostResult<Value> {
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
        let mut saved = self
            .runtime_store
            .rename_workspace_tab(&tab_id, &title)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if let Some(payload) = saved.payload.as_object_mut() {
            payload.insert("manualTitle".to_string(), Value::Bool(true));
            if let Some(snapshot) = payload
                .get_mut("codexSnapshot")
                .and_then(Value::as_object_mut)
            {
                snapshot.insert("title".to_string(), Value::String(title.clone()));
            }
        }
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

    async fn codex_thread_command(&mut self, payload: &Value, method: &str) -> HostResult<Value> {
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

    async fn respond_to_codex_request(&mut self, payload: &Value) -> HostResult<Value> {
        let id = payload
            .get("requestId")
            .cloned()
            .ok_or_else(|| HostError::format("Codex response requires requestId."))?;
        let server = self.ensure_codex_server(None).await?;
        let result = payload
            .get("result")
            .cloned()
            .map(normalize_codex_response_result);
        server
            .respond(id.clone(), result, payload.get("error").cloned())
            .await?;
        if let Some(tab) = self.find_codex_tab_for_request(&id).await? {
            let mut next = tab;
            append_question_answer(
                &mut next,
                &id,
                payload.get("result").unwrap_or(&Value::Null),
            );
            remove_pending_request(&mut next, &id);
            if let Ok(saved) = self.runtime_store.upsert_workspace_tab(next).await {
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
            }
        }
        Ok(json!({}))
    }

    pub(super) async fn codex_server_request(
        &mut self,
        method: &str,
        params: Value,
    ) -> HostResult<Value> {
        let server = self.ensure_codex_server(None).await?;
        let result = server.request(method, params).await;
        if let Err(error) = &result {
            self.broadcast_codex_server_error(error.wire_message());
        }
        result
    }

    pub(super) async fn ensure_codex_server(
        &mut self,
        cwd: Option<&str>,
    ) -> HostResult<CodexAppServer> {
        if let Some(server) = self.codex.as_ref() {
            return Ok(server.clone());
        }
        let server = CodexAppServer::start(self.inbox.clone(), cwd).await?;
        self.codex = Some(server.clone());
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "codexServerChanged",
            json!({"status": "ready"}),
        ));
        Ok(server)
    }

    pub(super) async fn codex_tab(&self, tab_id: &str) -> HostResult<WorkspaceTabRecord> {
        let tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace tab not found: {tab_id}")))?;
        if !is_codex_tab(&tab) {
            return Err(HostError::state(
                "The selected workspace tab is not a Codex tab.",
            ));
        }
        Ok(tab)
    }

    async fn clear_codex_active_turn(&mut self, tab: &WorkspaceTabRecord) {
        let mut next = tab.clone();
        if let Some(object) = next.payload.as_object_mut() {
            object.remove("codexActiveTurnId");
            if let Some(snapshot) = object
                .get_mut("codexSnapshot")
                .and_then(Value::as_object_mut)
            {
                snapshot.remove("activeTurnId");
            }
        }
        let _ = self.runtime_store.upsert_workspace_tab(next).await;
    }

    fn require_codex_client(&self, client_id: u64) -> HostResult<()> {
        if self
            .clients
            .get(&client_id)
            .is_some_and(|client| client.supports_codex_tab_kind)
        {
            return Ok(());
        }
        Err(HostError::state(
            "This client does not support the Codex chat tab.",
        ))
    }
}

fn copy_optional(payload: &Value, target: &mut Value, key: &str) {
    if let Some(value) = payload.get(key) {
        if let Some(object) = target.as_object_mut() {
            object.insert(key.to_string(), value.clone());
        }
    }
}

fn normalize_codex_response_result(mut result: Value) -> Value {
    let Some(object) = result.as_object_mut() else {
        return result;
    };
    if object.get("decision").and_then(Value::as_str) != Some("acceptForSession") {
        return result;
    }
    object.insert("decision".to_string(), Value::String("accept".to_string()));
    object
        .entry("acceptSettings".to_string())
        .or_insert_with(|| json!({"forSession": true}));
    result
}

fn turn_params(payload: &Value, thread_id: &str, input: Value) -> Value {
    let mut params = json!({
        "threadId": thread_id,
        "input": input,
        "approvalPolicy": payload
            .get("approvalPolicy")
            .cloned()
            .unwrap_or(json!("on-request")),
    });
    for key in [
        "model",
        "cwd",
        "serviceTier",
        "collaborationMode",
        "reasoning",
        "effort",
    ] {
        copy_optional(payload, &mut params, key);
    }
    if let Some(effort) = payload.pointer("/reasoning/effort") {
        params["effort"] = effort.clone();
    }
    if let Some(mode) = params
        .get("collaborationMode")
        .and_then(|value| value.get("mode"))
        .and_then(Value::as_str)
    {
        let model = params
            .get("model")
            .and_then(Value::as_str)
            .unwrap_or("gpt-5.6-sol");
        let effort = params
            .get("effort")
            .and_then(Value::as_str)
            .or_else(|| params.pointer("/reasoning/effort").and_then(Value::as_str))
            .unwrap_or("high");
        params["collaborationMode"] = json!({
            "mode": mode,
            "settings": {"model": model, "reasoning_effort": effort},
        });
    }
    params
}

#[cfg(test)]
mod tests {
    use super::{normalize_codex_response_result, turn_params};
    use serde_json::json;

    #[test]
    fn turn_params_maps_current_and_legacy_reasoning_inputs() {
        let params = turn_params(
            &json!({
                "model": "gpt-current",
                "reasoning": {"effort": "medium"},
                "serviceTier": "fast",
                "approvalPolicy": "never",
                "collaborationMode": {"mode": "plan"},
                "input": [{"type": "text", "text": "plan"}],
            }),
            "thread-1",
            json!([{"type": "text", "text": "plan"}]),
        );
        assert_eq!(params["threadId"], "thread-1");
        assert_eq!(params["effort"], "medium");
        assert_eq!(params["serviceTier"], "fast");
        assert_eq!(params["approvalPolicy"], "never");
        assert_eq!(
            params["collaborationMode"]["settings"]["model"],
            "gpt-current"
        );
        assert_eq!(
            params["collaborationMode"]["settings"]["reasoning_effort"],
            "medium"
        );
    }

    #[test]
    fn turn_params_defaults_to_a_current_codex_model_for_collaboration() {
        let params = turn_params(
            &json!({"collaborationMode": {"mode": "plan"}}),
            "thread-1",
            json!([]),
        );
        assert_eq!(
            params["collaborationMode"]["settings"]["model"],
            "gpt-5.6-sol"
        );
    }

    #[test]
    fn normalizes_legacy_session_approval_decision() {
        let result = normalize_codex_response_result(json!({
            "decision": "acceptForSession"
        }));
        assert_eq!(result["decision"], "accept");
        assert_eq!(result["acceptSettings"]["forSession"], true);
    }
}

//! Host requests for Codex threads, turns, approvals, and catalogues.

#[path = "codex_requests_catalogue.rs"]
pub(super) mod codex_requests_catalogue;
#[path = "codex_thread_sessions.rs"]
pub(super) mod codex_thread_sessions;
#[path = "codex_turn_requests.rs"]
mod codex_turn_requests;

pub(super) use super::codex_runtime_cleanup::CodexCleanupPlan;

use alera_core::runtime::WorkspaceTabRecord;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::codex_app_server::CodexAppServer;
use super::codex_state::is_codex_tab;
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
        if matches!(
            request_type,
            "codex.turn.interrupt"
                | "codex.thread.recover"
                | "codex.thread.new"
                | "codex.thread.clear"
                | "codex.thread.resume"
                | "codex.session.new"
                | "codex.session.clear"
                | "codex.session.resume"
        ) {
            self.guard_codex_history_mutation(payload, request_type == "codex.turn.interrupt")
                .await?;
        }
        if matches!(
            request_type,
            "codex.turn.start" | "codex.turn.steer" | "codex.review.start" | "codex.thread.compact"
        ) {
            let tab = self
                .codex_tab(&super::requests::require_string_key(payload, "tabId")?)
                .await?;
            let state = self.codex_delivery_state(&tab).await?;
            if self.codex_history_scans.contains(&tab.id)
                || state.history_locked()
                || state.messages.iter().any(|entry| entry.status == "sending")
            {
                return Err(HostError::state(
                    "A history or delivery operation is in progress.",
                ));
            }
        }
        if request_type.starts_with("codex.queue.") {
            return self.handle_codex_queue_request(request_type, payload).await;
        }
        let result = match request_type {
            "codex.thread.fork" => self.fork_codex_history(payload).await,
            "codex.thread.edit" => self.edit_codex_history(payload).await,
            "codex.tab.create" => self.create_codex_tab(payload).await,
            "codex.tab.configure" => self.configure_codex_tab(payload).await,
            "codex.thread.open" => self.open_codex_thread(payload).await,
            "codex.thread.list" | "codex.threads.list" | "codex.session.list" => {
                self.list_codex_threads(payload).await
            }
            "codex.thread.resume" | "codex.session.resume" => {
                self.resume_codex_thread(payload).await
            }
            "codex.thread.history" | "codex.thread.turns.list" | "codex.session.history" => {
                self.list_codex_thread_history(payload).await
            }
            "codex.thread.new" | "codex.session.new" => self.new_codex_thread(payload).await,
            "codex.thread.clear" | "codex.session.clear" => self.clear_codex_thread(payload).await,
            "codex.thread.recover" => self.recover_codex_thread(payload).await,
            "codex.thread.snapshot" => self.codex_thread_snapshot(payload).await,
            "codex.thread.items.list" => self.list_codex_thread_items(payload).await,
            "codex.goal.get" | "codex.thread.goal.get" => self.get_codex_goal(payload).await,
            "codex.goal.set" | "codex.thread.goal.set" => self.set_codex_goal(payload).await,
            "codex.goal.clear" | "codex.thread.goal.clear" => self.clear_codex_goal(payload).await,
            "codex.model.list" => {
                self.codex_server_cached_request("models", "model/list", json!({}))
                    .await
            }
            "codex.collaborationModes.list" => {
                self.codex_server_cached_request(
                    "collaborationModes",
                    "collaborationMode/list",
                    json!({}),
                )
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
            "codex.review.branches" => self.codex_review_branches(payload).await,
            "codex.review.start" => self.codex_thread_command(payload, "review/start").await,
            "codex.response" => self.respond_to_codex_request(payload).await,
            "codex.request.snooze" => self.snooze_codex_request(payload).await,
            _ => Err(HostError::state(format!(
                "Unknown Codex request: {request_type}"
            ))),
        }?;
        if matches!(
            request_type,
            "codex.thread.open"
                | "codex.thread.snapshot"
                | "codex.thread.resume"
                | "codex.thread.new"
                | "codex.thread.clear"
                | "codex.session.resume"
                | "codex.session.new"
                | "codex.session.clear"
                | "codex.thread.recover"
        ) {
            let mut result = result;
            let tab = self
                .codex_tab(&super::requests::require_string_key(payload, "tabId")?)
                .await?;
            result["chatFeatures"] =
                json!(["codexForkV1", "codexHistoryEditV1", "codexSharedQueueV1"]);
            result["queue"] = self.codex_delivery_state(&tab).await?.snapshot();
            result["historyRevision"] = tab
                .payload
                .get("codexHistoryRevision")
                .cloned()
                .unwrap_or(json!(0));
            return Ok(result);
        }
        Ok(result)
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

    pub(super) async fn codex_server_cached_request(
        &mut self,
        cache_key: &str,
        method: &str,
        params: Value,
    ) -> HostResult<Value> {
        let server = self.ensure_codex_server(None).await?;
        if let Some(cached) = server.cached_catalogue(cache_key).await {
            return Ok(cached);
        }
        let result = server.request(method, params).await;
        match result {
            Ok(value) => {
                server
                    .cache_catalogue(cache_key.to_string(), value.clone())
                    .await;
                Ok(value)
            }
            Err(error) => {
                self.broadcast_codex_server_error(error.wire_message());
                Err(error)
            }
        }
    }

    pub(super) async fn ensure_codex_server(
        &mut self,
        cwd: Option<&str>,
    ) -> HostResult<CodexAppServer> {
        if let Some(server) = self.codex.as_ref() {
            return Ok(server.clone());
        }
        let startup = self.codex_server_startup(cwd);
        let result = startup.clone().await;
        self.adopt_codex_startup(&startup, result)
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
        clear_codex_active_turn_payload(&mut next.payload);
        if let Ok(saved) = self.runtime_store.upsert_workspace_tab(next).await {
            self.refresh_codex_presence(&saved);
            self.schedule_codex_presence_changed();
        }
    }

    pub(super) fn require_codex_client(&self, client_id: u64) -> HostResult<()> {
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

fn clear_codex_active_turn_payload(payload: &mut Value) {
    let Some(object) = payload.as_object_mut() else {
        return;
    };
    object.remove("codexActiveTurnId");
    let Some(snapshot) = object.get_mut("codexSnapshot") else {
        return;
    };
    super::codex_state::clear_review_transition(snapshot);
    if let Some(snapshot) = snapshot.as_object_mut() {
        snapshot.remove("activeTurnId");
    }
}

#[cfg(test)]
mod active_turn_tests {
    use serde_json::json;

    use super::clear_codex_active_turn_payload;

    #[test]
    fn clearing_an_interrupted_turn_discards_review_transition_state() {
        let mut payload = json!({
            "codexActiveTurnId": "review-worker",
            "codexSnapshot": {
                "activeTurnId": "review-entry",
                "aleraReviewTransition": {
                    "entryTurnId": "review-entry",
                    "workerTurnId": "review-worker",
                },
            },
        });

        clear_codex_active_turn_payload(&mut payload);

        assert!(payload.get("codexActiveTurnId").is_none());
        assert!(payload["codexSnapshot"].get("activeTurnId").is_none());
        assert!(payload["codexSnapshot"]
            .get("aleraReviewTransition")
            .is_none());
    }
}

fn copy_optional(payload: &Value, target: &mut Value, key: &str) {
    if let Some(value) = payload.get(key) {
        if let Some(object) = target.as_object_mut() {
            object.insert(key.to_string(), value.clone());
        }
    }
}

pub(super) fn turn_params(payload: &Value, thread_id: &str, input: Value) -> Value {
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
        "sandboxPolicy",
        "approvalsReviewer",
        "collaborationMode",
        "reasoning",
        "effort",
        "clientUserMessageId",
    ] {
        copy_optional(payload, &mut params, key);
    }
    if params
        .get("clientUserMessageId")
        .is_none_or(|value| value.as_str().is_none_or(str::is_empty))
    {
        params["clientUserMessageId"] = Value::String(Uuid::new_v4().to_string());
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
    use super::turn_params;
    use serde_json::json;

    #[test]
    fn turn_params_maps_current_and_legacy_reasoning_inputs() {
        let params = turn_params(
            &json!({
                "model": "gpt-current",
                "reasoning": {"effort": "medium"},
                "serviceTier": "fast",
                "approvalPolicy": "never",
                "sandboxPolicy": {"type": "dangerFullAccess"},
                "collaborationMode": {"mode": "plan"},
                "input": [{"type": "text", "text": "plan"}],
                "userMessage": {
                    "text": "plan",
                    "attachments": [{"path": "/tmp/plan.md"}]
                },
            }),
            "thread-1",
            json!([{"type": "text", "text": "plan"}]),
        );
        assert_eq!(params["threadId"], "thread-1");
        assert_eq!(params["effort"], "medium");
        assert_eq!(params["serviceTier"], "fast");
        assert_eq!(params["approvalPolicy"], "never");
        assert!(params.get("approvalsReviewer").is_none());
        assert_eq!(params["sandboxPolicy"]["type"], "dangerFullAccess");
        assert!(params.get("userMessage").is_none());
        assert!(params["clientUserMessageId"].as_str().is_some());
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
    fn turn_params_only_overrides_the_reviewer_when_explicitly_requested() {
        let params = turn_params(
            &json!({"approvalsReviewer": "auto_review"}),
            "thread-1",
            json!([]),
        );

        assert_eq!(params["approvalsReviewer"], "auto_review");
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
    fn turn_params_preserves_default_collaboration_mode() {
        let params = turn_params(
            &json!({
                "model": "gpt-current",
                "effort": "medium",
                "collaborationMode": {"mode": "default"}
            }),
            "thread-1",
            json!([{"type": "text", "text": "implement"}]),
        );
        assert_eq!(params["collaborationMode"]["mode"], "default");
        assert_eq!(
            params["collaborationMode"]["settings"]["model"],
            "gpt-current"
        );
        assert_eq!(
            params["collaborationMode"]["settings"]["reasoning_effort"],
            "medium"
        );
    }
}

use std::path::Path;

use alera_core::runtime::{
    AgentCanvas, AgentCanvasCapabilities, AgentCanvasDecisionInput, AgentCanvasDecisionState,
    AgentCanvasState, RuntimeStore,
};
use chrono::{Duration, Utc};
use serde_json::{json, Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

impl ServerActor {
    pub(super) async fn canvas(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        self.handle_agent_canvas_request(request_type, payload)
            .await
    }

    pub(super) async fn handle_agent_canvas_request(
        &mut self,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        // A request is also a convenient, bounded maintenance tick. This keeps
        // durable timeout and retention behavior correct while the host is
        // attached, without creating an always-running background loop.
        self.runtime_store
            .expire_agent_canvas_decisions()
            .await
            .map_err(state_error)?;
        match request_type {
            "agentCanvas.capabilities" => capabilities_payload(),
            "agentCanvas.catalog" => {
                let workspace_id = required_string(payload, "workspaceId")?;
                let include_history = payload
                    .get("includeHistory")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let canvases = self
                    .runtime_store
                    .list_agent_canvases(&workspace_id, include_history)
                    .await
                    .map_err(state_error)?;
                Ok(json!({
                    "workspaceId": workspace_id,
                    "canvases": canvases,
                    "capabilities": AgentCanvasCapabilities::default(),
                }))
            }
            "agentCanvas.get" => {
                let canvas_id = required_string(payload, "canvasId")?;
                let canvas = self
                    .runtime_store
                    .find_agent_canvas(&canvas_id)
                    .await
                    .map_err(state_error)?
                    .ok_or_else(|| {
                        HostError::state(format!("Agent Canvas not found: {canvas_id}"))
                    })?;
                Ok(json!({ "canvas": canvas }))
            }
            "agentCanvas.publish" => self.publish_agent_canvas(payload).await,
            "agentCanvas.events" => {
                let workspace_id = required_string(payload, "workspaceId")?;
                let since = payload.get("since").and_then(Value::as_i64).unwrap_or(0);
                let limit = payload.get("limit").and_then(Value::as_i64).unwrap_or(200);
                let events = self
                    .runtime_store
                    .list_agent_canvas_events(&workspace_id, since, limit)
                    .await
                    .map_err(state_error)?;
                Ok(json!({ "workspaceId": workspace_id, "events": events }))
            }
            "agentCanvas.decision.get" => {
                let decision_id = required_string(payload, "decisionId")?;
                let decision = self
                    .runtime_store
                    .find_agent_canvas_decision(&decision_id)
                    .await
                    .map_err(state_error)?
                    .ok_or_else(|| {
                        HostError::state(format!("Agent Canvas decision not found: {decision_id}"))
                    })?;
                Ok(json!({ "decision": decision }))
            }
            "agentCanvas.decision.resolve" => self.resolve_agent_canvas_decision(payload).await,
            "agentCanvas.wait" => self.wait_agent_canvas(payload).await,
            "agentCanvas.complete" => {
                self.change_agent_canvas_state(payload, CanvasStateChange::Complete)
                    .await
            }
            "agentCanvas.close" => {
                self.change_agent_canvas_state(payload, CanvasStateChange::Close)
                    .await
            }
            "agentCanvas.pin" => {
                let canvas_id = required_string(payload, "canvasId")?;
                let pinned = payload
                    .get("pinned")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let canvas = self
                    .runtime_store
                    .set_agent_canvas_pinned(&canvas_id, pinned)
                    .await
                    .map_err(state_error)?;
                self.broadcast_canvas(&canvas, if pinned { "pinned" } else { "unpinned" });
                Ok(json!({ "canvas": canvas }))
            }
            "agentCanvas.remove" => {
                let canvas_id = required_string(payload, "canvasId")?;
                let canvas = self
                    .runtime_store
                    .find_agent_canvas(&canvas_id)
                    .await
                    .map_err(state_error)?
                    .ok_or_else(|| {
                        HostError::state(format!("Agent Canvas not found: {canvas_id}"))
                    })?;
                let removed = self
                    .runtime_store
                    .remove_agent_canvas(&canvas_id)
                    .await
                    .map_err(state_error)?;
                if removed {
                    self.broadcast_agent_canvas_changed(
                        &canvas.workspace_id,
                        &canvas.id,
                        canvas.revision,
                        "removed",
                    );
                }
                Ok(json!({ "removed": removed, "canvasId": canvas_id }))
            }
            "agentCanvas.action" => self.handle_typed_action(payload).await,
            _ => Err(HostError::state(format!(
                "Unknown Agent Canvas request: {request_type}"
            ))),
        }
    }

    async fn publish_agent_canvas(&mut self, payload: &Value) -> HostResult<Value> {
        let workspace_id = required_string(payload, "workspaceId")?;
        let terminal_session_id = required_string(payload, "terminalSessionId")?;
        let tab_id = optional_string(payload, "tabId");
        let agent_type =
            optional_string(payload, "agentType").unwrap_or_else(|| "unknown".to_string());
        let title = optional_string(payload, "title").unwrap_or_else(|| "Agent Run".to_string());
        self.validate_canvas_identity(&workspace_id, &terminal_session_id, tab_id.as_deref())?;
        let canvas = self
            .runtime_store
            .upsert_agent_canvas_identity(
                &workspace_id,
                &terminal_session_id,
                tab_id.as_deref(),
                &agent_type,
                &title,
            )
            .await
            .map_err(state_error)?;
        if let Some(canvas_id) = payload.get("canvasId").and_then(Value::as_str) {
            if canvas_id != canvas.id {
                return Err(HostError::state(
                    "Agent Canvas id does not match the terminal identity.",
                ));
            }
        }
        enforce_publish_rate(self.runtime_store(), &canvas.id).await?;
        let document = payload
            .get("document")
            .cloned()
            .ok_or_else(|| HostError::format("document is required."))?;
        let requested_state = payload
            .get("state")
            .and_then(Value::as_str)
            .map(|value| {
                AgentCanvasState::parse(value).ok_or_else(|| {
                    HostError::format(format!("unsupported Agent Canvas state: {value}"))
                })
            })
            .transpose()?;
        let decisions = decision_inputs(payload.get("decisions"), &document)?;
        let expected_revision = payload.get("expectedRevision").and_then(Value::as_i64);
        let result = self
            .runtime_store
            .publish_agent_canvas(
                &canvas.id,
                document,
                expected_revision,
                requested_state,
                optional_string(payload, "title").as_deref(),
                &decisions,
            )
            .await
            .map_err(state_error)?;
        if result.changed {
            let reason = if result.canvas.decisions.iter().any(|decision| {
                decision.revision == result.canvas.revision
                    && decision.state == AgentCanvasDecisionState::Pending
            }) {
                "decisionRequest"
            } else {
                "revision"
            };
            self.broadcast_canvas(&result.canvas, reason);
        }
        Ok(json!({
            "canvas": result.canvas,
            "changed": result.changed,
        }))
    }

    async fn resolve_agent_canvas_decision(&mut self, payload: &Value) -> HostResult<Value> {
        let decision_id = required_string(payload, "decisionId")?;
        let resolution = payload
            .get("resolution")
            .cloned()
            .ok_or_else(|| HostError::format("resolution is required."))?;
        let decision = self
            .runtime_store
            .resolve_agent_canvas_decision(&decision_id, resolution)
            .await
            .map_err(state_error)?;
        if let Some(canvas) = self
            .runtime_store
            .find_agent_canvas(&decision.canvas_id)
            .await
            .map_err(state_error)?
        {
            self.broadcast_canvas(&canvas, "decisionResolved");
        }
        Ok(json!({ "decision": decision }))
    }

    async fn wait_agent_canvas(&mut self, payload: &Value) -> HostResult<Value> {
        let decision_id = required_string(payload, "decisionId")?;
        let decision = self
            .runtime_store
            .find_agent_canvas_decision(&decision_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| {
                HostError::state(format!("Agent Canvas decision not found: {decision_id}"))
            })?;
        Ok(json!({
            "decision": decision,
            "ready": decision.state != AgentCanvasDecisionState::Pending,
            "waitIsDurable": true,
        }))
    }

    async fn change_agent_canvas_state(
        &mut self,
        payload: &Value,
        change: CanvasStateChange,
    ) -> HostResult<Value> {
        let canvas_id = required_string(payload, "canvasId")?;
        let canvas = match change {
            CanvasStateChange::Complete => self
                .runtime_store
                .complete_agent_canvas(&canvas_id)
                .await
                .map_err(state_error)?,
            CanvasStateChange::Close => self
                .runtime_store
                .close_agent_canvas(&canvas_id)
                .await
                .map_err(state_error)?,
        };
        self.broadcast_canvas(
            &canvas,
            match change {
                CanvasStateChange::Complete => "completed",
                CanvasStateChange::Close => "closed",
            },
        );
        Ok(json!({ "canvas": canvas }))
    }

    async fn handle_typed_action(&mut self, payload: &Value) -> HostResult<Value> {
        let canvas_id = required_string(payload, "canvasId")?;
        let canvas = self
            .runtime_store
            .find_agent_canvas(&canvas_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("Agent Canvas not found: {canvas_id}")))?;
        let action = payload
            .get("action")
            .and_then(Value::as_object)
            .ok_or_else(|| HostError::format("action must be a JSON object."))?;
        validate_typed_action(action, &canvas)?;
        if action.get("kind").and_then(Value::as_str) == Some("resolveDecision") {
            let decision_id = required_string_from_map(action, "decisionId")?;
            let resolution = action
                .get("resolution")
                .cloned()
                .ok_or_else(|| HostError::format("resolution is required."))?;
            let decision = self
                .runtime_store
                .resolve_agent_canvas_decision(&decision_id, resolution)
                .await
                .map_err(state_error)?;
            self.broadcast_canvas(&canvas, "decisionResolved");
            return Ok(json!({ "accepted": true, "decision": decision }));
        }
        Ok(json!({
            "accepted": true,
            "requiresConfirmation": false,
            "action": Value::Object(action.clone()),
        }))
    }

    fn runtime_store(&self) -> &RuntimeStore {
        &self.runtime_store
    }

    fn validate_canvas_identity(
        &self,
        workspace_id: &str,
        terminal_session_id: &str,
        tab_id: Option<&str>,
    ) -> HostResult<()> {
        let session = self.sessions.get(terminal_session_id).ok_or_else(|| {
            HostError::state(
                "Agent Canvas publishing requires an active terminal session identity.",
            )
        })?;
        if session.workspace_id != workspace_id {
            return Err(HostError::state(
                "Agent Canvas terminal identity does not belong to this workspace.",
            ));
        }
        if let Some(tab_id) = tab_id {
            if session.tab_id != tab_id {
                return Err(HostError::state(
                    "Agent Canvas terminal identity does not match the tab.",
                ));
            }
        }
        Ok(())
    }

    fn broadcast_canvas(&self, canvas: &AgentCanvas, reason: &str) {
        self.broadcast_agent_canvas_changed(
            &canvas.workspace_id,
            &canvas.id,
            canvas.revision,
            reason,
        );
    }
}

include!("agent_canvas_request_support.rs");

//! Worker verbs: `context`, `escalate` and `complete`, plus the implicit
//! acceptance every worker command performs.
//!
//! There is no accept step and no heartbeat. The first command a worker runs
//! from its terminal accepts the dispatch, and any later one (or terminal
//! output, or an agent hook) renews its lease and revives it if it stalled.

use alera_core::runtime::{
    ActivityOutcome, NewOrchestrationMessage, OrchestrationDispatchContext,
    OrchestrationDispatchStatus, OrchestrationMessagePriority, OrchestrationMessageType,
};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::dispatch_preamble::{build_worker_contract, WorkerKind};

use super::orchestration_validation::{optional_string, require_string, state_error};
use super::ServerActor;

pub(super) fn context_token_hash(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

/// `complete` requires only a summary. The optional evidence arrays are
/// stored as empty arrays when absent, so every stored result has one shape.
fn normalized_completion_result(payload: &Value) -> HostResult<Map<String, Value>> {
    let mut result = payload
        .get("result")
        .and_then(Value::as_object)
        .cloned()
        .ok_or_else(|| HostError::format("result must be an object."))?;
    let summary = result
        .get("summary")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::format("result.summary is required."))?;
    result.insert("summary".to_string(), json!(summary));
    match result.get("completionKind") {
        None | Some(Value::Null) => {
            result.insert("completionKind".to_string(), json!("success"));
        }
        Some(Value::String(kind)) if kind == "success" || kind == "failure" => {}
        Some(_) => {
            return Err(HostError::format(
                "result.completionKind must be success or failure.",
            ))
        }
    }
    for field in ["artifacts", "filesModified", "validation"] {
        match result.get(field) {
            None | Some(Value::Null) => {
                result.insert(field.to_string(), json!([]));
            }
            Some(Value::Array(_)) => {}
            Some(_) => {
                return Err(HostError::format(format!(
                    "result.{field} must be an array."
                )))
            }
        }
    }
    Ok(result)
}

impl ServerActor {
    /// The active dispatch of the calling worker terminal, after checking its
    /// context token. A dispatch still awaiting acceptance is accepted here
    /// (and the owned spawn's one-shot launch prompt is consumed); a stalled
    /// one is revived. Every worker command goes through this.
    pub(super) async fn touch_worker_dispatch(
        &mut self,
        payload: &Value,
    ) -> HostResult<OrchestrationDispatchContext> {
        let terminal = optional_string(payload, "terminal").ok_or_else(|| {
            HostError::format("terminal is required; run inside an Alera terminal.")
        })?;
        let dispatch = self
            .runtime_store
            .active_orchestration_dispatch_for_handle(&terminal)
            .await
            .map_err(state_error)?
            .ok_or_else(|| {
                HostError::state(format!("no active dispatch for terminal {terminal}"))
            })?;
        let token_hash =
            optional_string(payload, "contextToken").map(|token| context_token_hash(&token));
        if let Some(expected_hash) = dispatch.context_token_hash.as_deref() {
            let provided = token_hash
                .as_deref()
                .ok_or_else(|| HostError::state("dispatch context token is required"))?;
            if provided != expected_hash {
                return Err(HostError::state(
                    "dispatch context token is invalid or stale",
                ));
            }
        }
        match dispatch.status {
            OrchestrationDispatchStatus::AwaitingAcceptance => {
                let accepted = self
                    .runtime_store
                    .accept_orchestration_dispatch(
                        &dispatch.id,
                        &terminal,
                        token_hash.as_deref().unwrap_or_default(),
                    )
                    .await
                    .map_err(state_error)?;
                self.consume_owned_spawn_metadata(&terminal).await;
                self.broadcast_orchestration_board_change().await;
                Ok(accepted)
            }
            _ => {
                self.record_dispatch_activity(&dispatch).await;
                Ok(self
                    .runtime_store
                    .orchestration_dispatch_by_id(&dispatch.id)
                    .await
                    .map_err(state_error)?
                    .unwrap_or(dispatch))
            }
        }
    }

    /// Renews a dispatch's lease. When the worker had stalled, its stall gate
    /// is resolved as `resumed` so nobody acts on a worker that recovered.
    pub(super) async fn record_dispatch_activity(
        &mut self,
        dispatch: &OrchestrationDispatchContext,
    ) -> ActivityOutcome {
        let outcome = match self
            .runtime_store
            .record_orchestration_activity(&dispatch.id)
            .await
        {
            Ok(outcome) => outcome,
            Err(error) => {
                tracing::warn!(
                    dispatch_id = %dispatch.id,
                    "[orchestration] recording activity failed: {error}"
                );
                return ActivityOutcome::Ignored;
            }
        };
        if outcome == ActivityOutcome::Revived {
            if let Err(error) = self
                .runtime_store
                .resolve_stall_gate_as_resumed(&dispatch.task_id)
                .await
            {
                tracing::warn!(
                    task_id = %dispatch.task_id,
                    "[orchestration] resolving a stall gate as resumed failed: {error}"
                );
            }
            self.coordinator_log(&format!(
                "dispatch {} showed activity again and is no longer stalled",
                dispatch.id
            ));
            self.broadcast_orchestration_board_change().await;
        }
        outcome
    }

    pub(super) async fn orchestration_context(&mut self, payload: &Value) -> HostResult<Value> {
        let dispatch = self.touch_worker_dispatch(payload).await?;
        if let Some(context) = self.workflow_worker_context(&dispatch).await? {
            return Ok(context);
        }
        let mut task = self
            .runtime_store
            .orchestration_task_by_id(&dispatch.task_id)
            .await
            .map_err(state_error)?;
        let mut base_drift = Value::Null;
        if let Some((task_spec, stored_drift)) =
            self.orchestration_preflight_context(&dispatch).await?
        {
            if let Some(task) = task.as_mut() {
                task.spec = task_spec;
            }
            base_drift = stored_drift;
        }
        self.compose_orchestration_task_prompt(&mut task, dispatch.agent_profile.as_deref())
            .await?;
        let gate_resolution = self.latest_resolved_gate(&dispatch.task_id).await?;
        let mut worker_instructions = build_worker_contract(
            &dispatch.coordinator_handle,
            WorkerKind::PromptReturningAgent,
        );
        if let Some(task) = task.as_ref() {
            worker_instructions =
                super::agent_prompt_composition::append_role_contract(task, &worker_instructions)?;
        }
        Ok(json!({
            "task": task,
            "dispatch": dispatch,
            "baseDrift": base_drift,
            "gateResolution": gate_resolution.map(|gate| json!({
                "question": gate.question,
                "resolution": gate.resolution,
            })),
            "workerInstructions": worker_instructions,
            "coordinatorHandle": dispatch.coordinator_handle,
            "assigneeHandle": dispatch.assignee_handle,
            "phase": dispatch.status.as_str(),
            "lastActivityAt": dispatch.last_activity_at,
            "completionState": dispatch.status.as_str(),
        }))
    }

    async fn orchestration_preflight_context(
        &self,
        dispatch: &OrchestrationDispatchContext,
    ) -> HostResult<Option<(String, Value)>> {
        let Some(handle) = dispatch.assignee_handle.as_deref() else {
            return Ok(None);
        };
        let Some(tab) = self
            .runtime_store
            .find_workspace_tab(handle)
            .await
            .map_err(state_error)?
        else {
            return Ok(None);
        };
        let Some(preflight) = tab.payload.get("orchestrationPreflight") else {
            return Ok(None);
        };
        if preflight.get("taskId").and_then(Value::as_str) != Some(dispatch.task_id.as_str())
            || preflight.get("dispatchId").and_then(Value::as_str) != Some(dispatch.id.as_str())
        {
            return Ok(None);
        }
        let Some(task_spec) = preflight.get("taskSpec").and_then(Value::as_str) else {
            return Ok(None);
        };
        Ok(Some((
            task_spec.to_string(),
            preflight.get("baseDrift").cloned().unwrap_or(Value::Null),
        )))
    }

    pub(super) async fn orchestration_escalate(&mut self, payload: &Value) -> HostResult<Value> {
        let subject = require_string(payload, "subject")?;
        let dispatch = self.touch_worker_dispatch(payload).await?;
        let assignee = dispatch.assignee_handle.clone().unwrap_or_default();
        if let Some(launch) = self
            .runtime_store
            .workflow_launch_for_terminal(&assignee)
            .await
            .map_err(state_error)?
        {
            self.runtime_store
                .workflow_launch_attention(&launch.id, &subject)
                .await
                .map_err(state_error)?;
            self.broadcast_orchestration_board_change().await;
        }
        let message = self
            .runtime_store
            .insert_orchestration_message(NewOrchestrationMessage {
                from_handle: assignee,
                to_handle: dispatch.coordinator_handle.clone(),
                subject,
                body: optional_string(payload, "body").unwrap_or_default(),
                message_type: OrchestrationMessageType::Escalation,
                priority: OrchestrationMessagePriority::High,
                payload: Some(
                    json!({
                        "taskId": dispatch.task_id,
                        "dispatchId": dispatch.id,
                    })
                    .to_string(),
                ),
                run_id: dispatch.run_id.clone(),
                workspace_id: Some(dispatch.workspace_id.clone()),
                task_id: Some(dispatch.task_id.clone()),
                dispatch_id: Some(dispatch.id.clone()),
                ..NewOrchestrationMessage::default()
            })
            .await
            .map_err(state_error)?;
        self.queue_escalation_push(&dispatch.task_id, &message.subject)
            .await;
        self.notify_message_arrived(
            &dispatch.coordinator_handle,
            OrchestrationMessageType::Escalation,
        )
        .await;
        Ok(json!({ "dispatchId": dispatch.id, "message": message }))
    }

    pub(super) async fn orchestration_complete(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let result = normalized_completion_result(payload)?;
        let dispatch = self.touch_worker_dispatch(payload).await?;
        let assignee = dispatch
            .assignee_handle
            .clone()
            .ok_or_else(|| HostError::state("active dispatch has no assignee"))?;
        let task = self
            .runtime_store
            .orchestration_task_by_id(&dispatch.task_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("dispatch task no longer exists"))?;
        super::orchestration_requests::validate_result_schema(
            &result,
            task.result_schema.as_deref(),
        )?;
        let result_json =
            serde_json::to_string(&result).map_err(|error| HostError::format(error.to_string()))?;
        let summary = result["summary"].as_str().unwrap_or_default().to_string();
        if result["completionKind"] == "failure" {
            self.remove_dispatch_context(&assignee);
            let failed = self
                .runtime_store
                .fail_orchestration_dispatch_with_result(&dispatch.id, &summary, Some(&result_json))
                .await
                .map_err(state_error)?;
            if self.is_workflow_terminal(&assignee).await {
                self.terminate_sessions_for_tab(&assignee).await;
            }
            return Ok(Some(json!({
                "taskId": dispatch.task_id,
                "dispatchId": failed.id,
                "dispatchStatus": failed.status.as_str(),
            })));
        }
        self.complete_or_defer_dispatch_result(
            client_id,
            request_id,
            &dispatch,
            &assignee,
            result_json,
        )
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_summary_alone_completes_with_empty_evidence() {
        let result =
            normalized_completion_result(&json!({ "result": { "summary": "  done  " } })).unwrap();
        assert_eq!(
            Value::Object(result),
            json!({
                "summary": "done",
                "completionKind": "success",
                "artifacts": [],
                "filesModified": [],
                "validation": [],
            })
        );
    }

    #[test]
    fn completion_needs_a_summary_and_known_shapes() {
        for invalid in [
            json!({ "result": {} }),
            json!({ "result": { "summary": "  " } }),
            json!({ "result": { "summary": "x", "completionKind": "partial" } }),
            json!({ "result": { "summary": "x", "artifacts": "a.txt" } }),
            json!({ "summary": "x" }),
        ] {
            assert!(normalized_completion_result(&invalid).is_err(), "{invalid}");
        }
        let kept = normalized_completion_result(&json!({
            "result": { "summary": "x", "completionKind": "failure", "validation": [{"ok": true}] }
        }))
        .unwrap();
        assert_eq!(kept["completionKind"], "failure");
        assert_eq!(kept["validation"], json!([{"ok": true}]));
    }
}

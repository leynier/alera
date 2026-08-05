use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationRunStatus, AutomationState,
};
use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::automation_run_target_requests::{actor_for_circuit_reset, requested_target_identity};
use super::requests::require_string_key;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn automation_context_request(
        &self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let id = require_string_key(payload, "run")?;
        let identity = requested_target_identity(payload)?;
        self.verify_live_target_identity(client_id, &identity)
            .await?;
        let actor = self.resolve_execution_actor(&id, actor, &identity).await?;
        let run = self
            .runtime_store
            .verify_automation_run_identity(&id, &actor, &identity)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let automation = self
            .runtime_store
            .find_automation(&run.automation_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("automation definition is missing"))?;
        Ok(json!({
            "run": run,
            "automation": automation,
            "completion": {
                "required": true,
                "commands": ["heartbeat", "complete", "cancel"],
            },
        }))
    }

    pub(super) async fn automation_heartbeat_request(
        &self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let id = require_string_key(payload, "run")?;
        let identity = requested_target_identity(payload)?;
        self.verify_live_target_identity(client_id, &identity)
            .await?;
        let actor = self.resolve_execution_actor(&id, actor, &identity).await?;
        let run = self
            .runtime_store
            .verify_automation_run_identity(&id, &actor, &identity)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let run = self
            .runtime_store
            .heartbeat_automation_run(&run.id, actor)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        serde_json::to_value(run).map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn automation_wait_request(
        &self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let id = require_string_key(payload, "run")?;
        let identity = requested_target_identity(payload)?;
        let actor = self.resolve_execution_actor(&id, actor, &identity).await?;
        self.verify_lifecycle_target_identity(client_id, &id, &identity, &actor)
            .await?;
        let waiting = payload
            .get("waiting")
            .and_then(Value::as_bool)
            .unwrap_or(true);
        let run = self
            .runtime_store
            .set_automation_run_waiting(&id, actor, waiting)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        serde_json::to_value(run).map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn automation_extend_request(
        &self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let id = require_string_key(payload, "run")?;
        let identity = requested_target_identity(payload)?;
        let actor = self.resolve_execution_actor(&id, actor, &identity).await?;
        if actor.kind == AutomationActorKind::ManagedAgent {
            return Err(HostError::state(
                "only a human actor can extend waiting automation runs",
            ));
        }
        self.verify_lifecycle_target_identity(client_id, &id, &identity, &actor)
            .await?;
        let until = payload
            .get("until")
            .and_then(Value::as_str)
            .and_then(|value| value.parse().ok())
            .or_else(|| {
                payload
                    .get("seconds")
                    .and_then(Value::as_i64)
                    .filter(|value| *value > 0)
                    .map(|seconds| Utc::now() + chrono::Duration::seconds(seconds))
            })
            .ok_or_else(|| HostError::format("waiting extension requires until or seconds"))?;
        if until <= Utc::now() {
            return Err(HostError::format("waiting extension must be in the future"));
        }
        let run = self
            .runtime_store
            .extend_waiting_automation_run(&id, until, actor)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        serde_json::to_value(run).map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn automation_complete_request(
        &mut self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let id = require_string_key(payload, "run")?;
        let identity = requested_target_identity(payload)?;
        self.verify_live_target_identity(client_id, &identity)
            .await?;
        let actor = self.resolve_execution_actor(&id, actor, &identity).await?;
        let status: AutomationRunStatus = serde_json::from_value(
            payload
                .get("status")
                .cloned()
                .ok_or_else(|| HostError::format("automation status is required"))?,
        )
        .map_err(|_| HostError::format("automation status must be success, failure, or blocked"))?;
        if !matches!(
            status,
            AutomationRunStatus::Success
                | AutomationRunStatus::Failure
                | AutomationRunStatus::Blocked
        ) {
            return Err(HostError::format(
                "automation status must be success, failure, or blocked",
            ));
        }
        let summary = payload
            .get("summary")
            .and_then(Value::as_str)
            .map(str::to_string);
        if summary
            .as_deref()
            .is_none_or(|value| value.trim().is_empty())
        {
            return Err(HostError::format(
                "automation completion summary is required",
            ));
        }
        let error = payload
            .get("error")
            .and_then(Value::as_str)
            .map(str::to_string);
        let current = self
            .runtime_store
            .verify_automation_run_identity(&id, &actor, &identity)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let definition = self
            .runtime_store
            .find_automation(&current.automation_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("automation definition is missing"))?;
        let run = self
            .runtime_store
            .complete_automation_run(&id, status, summary, error, actor)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let _ = self
            .runtime_store
            .archive_one_time_automation_if_final(
                &run.automation_id,
                AutomationActor {
                    kind: AutomationActorKind::ManagedAgent,
                    id: run.actor_id.clone(),
                    label: Some("one-time automation finalizer".to_string()),
                },
            )
            .await;
        if current.trigger == alera_core::runtime::AutomationRunTrigger::Scheduled
            && status.counts_as_failure()
            && self
                .runtime_store
                .count_automation_failure_streak(&run.automation_id)
                .await
                .unwrap_or_default()
                >= definition.circuit_failure_threshold
        {
            let _ = self
                .runtime_store
                .set_automation_circuit_opened(
                    &run.automation_id,
                    true,
                    AutomationActor {
                        kind: AutomationActorKind::ManagedAgent,
                        id: run.actor_id.clone(),
                        label: Some("Alera Automation Circuit Breaker".to_string()),
                    },
                    Some("automation circuit breaker opened"),
                )
                .await;
            let _ = self
                .runtime_store
                .set_automation_state(
                    &run.automation_id,
                    AutomationState::Blocked,
                    AutomationActor {
                        kind: AutomationActorKind::ManagedAgent,
                        id: None,
                        label: Some("Alera Automation Circuit Breaker".to_string()),
                    },
                    Some("automation circuit breaker opened"),
                )
                .await;
        }
        if current.trigger == alera_core::runtime::AutomationRunTrigger::Scheduled
            && status == AutomationRunStatus::Success
            && definition.circuit_opened
        {
            let _ = self
                .runtime_store
                .set_automation_circuit_opened(
                    &run.automation_id,
                    false,
                    actor_for_circuit_reset(&run),
                    Some("scheduled success reset the automation circuit breaker"),
                )
                .await;
            if definition.state == AutomationState::Blocked {
                let _ = self
                    .runtime_store
                    .set_automation_state(
                        &run.automation_id,
                        AutomationState::Active,
                        actor_for_circuit_reset(&run),
                        Some("scheduled success reset the automation circuit breaker"),
                    )
                    .await;
            }
        }
        if status == AutomationRunStatus::Blocked {
            let _ = self
                .runtime_store
                .set_automation_state(
                    &run.automation_id,
                    AutomationState::Blocked,
                    AutomationActor {
                        kind: AutomationActorKind::ManagedAgent,
                        id: run.actor_id.clone(),
                        label: Some("managed automation agent".to_string()),
                    },
                    run.error.as_deref().or(run.summary.as_deref()),
                )
                .await;
        }
        self.cleanup_automation_owned_target(&run, run.status).await;
        self.queue_automation_push(&run, &definition, status, run.summary.as_deref())
            .await;
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "automationRunChanged",
            json!({ "automationId": run.automation_id, "runId": run.id }),
        ));
        serde_json::to_value(run).map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn automation_cancel_request(
        &self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let id = require_string_key(payload, "run")?;
        let identity = requested_target_identity(payload)?;
        let actor = self.resolve_execution_actor(&id, actor, &identity).await?;
        self.verify_lifecycle_target_identity(client_id, &id, &identity, &actor)
            .await?;
        let current = self
            .runtime_store
            .find_automation_run(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("automation run not found: {id}")))?;
        if current.status.is_final() {
            return serde_json::to_value(current)
                .map_err(|error| HostError::state(error.to_string()));
        }
        let run = self
            .runtime_store
            .request_automation_cancel(&id, actor)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        serde_json::to_value(run).map_err(|error| HostError::state(error.to_string()))
    }
}

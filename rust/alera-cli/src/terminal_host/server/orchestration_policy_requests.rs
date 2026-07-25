//! Execution policy verbs: a run-scoped stage plan the user approves before the
//! coordinator is allowed to dispatch.
//!
//! Decision gates are the natural approval primitive but are task-scoped at the
//! storage level, and creating one closes the active dispatch. Explicit
//! propose/approve verbs give the same property, a durable user decision before
//! execution, without a destructive schema migration.

use alera_core::runtime::OrchestrationCoordinatorRun;
use serde_json::{json, Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::orchestration_validation::{optional_string, require_string};
use super::ServerActor;

/// Stall handling for workers under an approved policy.
const STALL_POLICIES: [&str; 3] = ["ask", "auto-failover", "wait"];
const DEFAULT_STALL_POLICY: &str = "ask";
const POLICY_VERSION: i64 = 1;

impl ServerActor {
    pub(super) async fn orchestration_run_policy_propose(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let run_id = require_string(payload, "run")?;
        let policy = payload
            .get("policy")
            .ok_or_else(|| HostError::format("policy is required."))?;
        let normalized = self.validated_policy(policy).await?;
        let encoded = serde_json::to_string(&normalized)
            .map_err(|error| HostError::format(error.to_string()))?;
        let run = self
            .runtime_store
            .propose_orchestration_execution_policy(&run_id, &encoded)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(policy_response(&run))
    }

    pub(super) async fn orchestration_run_policy_show(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let run_id = require_string(payload, "run")?;
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(&run_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("coordinator run not found: {run_id}")))?;
        Ok(policy_response(&run))
    }

    pub(super) async fn orchestration_run_policy_resolve(
        &mut self,
        payload: &Value,
        approved: bool,
    ) -> HostResult<Value> {
        let run_id = require_string(payload, "run")?;
        // A rejection has to say why; an approval does not need a reason.
        let reason = if approved {
            optional_string(payload, "reason").unwrap_or_else(|| "approved".to_string())
        } else {
            require_string(payload, "reason")?
        };
        let run = self
            .runtime_store
            .resolve_orchestration_execution_policy(&run_id, approved)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let action = if approved {
            "run.policy.approve"
        } else {
            "run.policy.reject"
        };
        self.runtime_store
            .insert_orchestration_audit_event(
                optional_string(payload, "actor").as_deref(),
                action,
                &run_id,
                &reason,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(policy_response(&run))
    }

    /// Validates the plan and returns it normalized. Every referenced profile
    /// must already exist in the catalog: a name that resolves to nothing would
    /// only fail much later, at dispatch, with no way back to the user.
    async fn validated_policy(&mut self, policy: &Value) -> HostResult<Value> {
        let object = policy
            .as_object()
            .ok_or_else(|| HostError::format("policy must be an object."))?;
        let version = object.get("version").and_then(Value::as_i64);
        if version.is_some_and(|value| value != POLICY_VERSION) {
            return Err(HostError::format(format!(
                "unsupported policy version: {}. Expected {POLICY_VERSION}.",
                version.unwrap_or_default()
            )));
        }
        let stall_policy = object
            .get("stallPolicy")
            .and_then(Value::as_str)
            .unwrap_or(DEFAULT_STALL_POLICY)
            .to_string();
        if !STALL_POLICIES.contains(&stall_policy.as_str()) {
            return Err(HostError::format(format!(
                "policy.stallPolicy must be one of {}.",
                STALL_POLICIES.join(", ")
            )));
        }
        let stages = object
            .get("stages")
            .and_then(Value::as_array)
            .ok_or_else(|| HostError::format("policy.stages must be an array."))?;
        if stages.is_empty() {
            return Err(HostError::format("policy.stages must not be empty."));
        }

        let known = self.known_profile_names().await?;
        let mut seen_ids = Vec::<String>::new();
        let mut normalized_stages = Vec::<Value>::new();
        for (index, stage) in stages.iter().enumerate() {
            let stage = stage.as_object().ok_or_else(|| {
                HostError::format(format!("policy.stages[{index}] must be an object."))
            })?;
            let id = stage_string(stage, "id", index)?;
            if seen_ids.contains(&id) {
                return Err(HostError::format(format!("duplicate stage id: {id}.")));
            }
            let profile = stage_string(stage, "profile", index)?;
            require_known_profile(&known, &profile)?;
            let mut fallbacks = Vec::<String>::new();
            if let Some(raw) = stage.get("fallbacks") {
                let entries = raw.as_array().ok_or_else(|| {
                    HostError::format(format!(
                        "policy.stages[{index}].fallbacks must be an array."
                    ))
                })?;
                for entry in entries {
                    let name = entry
                        .as_str()
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .ok_or_else(|| {
                            HostError::format(format!(
                                "policy.stages[{index}].fallbacks entries must be profile names."
                            ))
                        })?;
                    require_known_profile(&known, name)?;
                    fallbacks.push(name.to_string());
                }
            }
            let mut normalized = Map::new();
            normalized.insert("id".to_string(), json!(id));
            if let Some(title) = stage.get("title").and_then(Value::as_str) {
                normalized.insert("title".to_string(), json!(title.trim()));
            }
            normalized.insert("profile".to_string(), json!(profile));
            normalized.insert("fallbacks".to_string(), json!(fallbacks));
            normalized_stages.push(Value::Object(normalized));
            seen_ids.push(id);
        }

        Ok(json!({
            "version": POLICY_VERSION,
            "stallPolicy": stall_policy,
            "stages": normalized_stages,
        }))
    }

    /// Binds a task to a stage its run actually declares. A stage id that is not
    /// in the approved plan is rejected rather than stored, because a task
    /// pointing at a stage nobody declared can never resolve a profile.
    pub(super) async fn bind_task_to_policy_stage(
        &mut self,
        task_id: &str,
        run_id: Option<&str>,
        stage_id: &str,
    ) -> HostResult<()> {
        let Some(run_id) = run_id else {
            return Err(HostError::format(
                "stage requires the task to belong to a run.".to_string(),
            ));
        };
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("coordinator run not found: {run_id}")))?;
        let declared = run
            .execution_policy
            .as_deref()
            .and_then(|raw| serde_json::from_str::<Value>(raw).ok())
            .map(|policy| stage_ids(&policy))
            .unwrap_or_default();
        if !declared.iter().any(|candidate| candidate == stage_id) {
            return Err(HostError::format(format!(
                "run {run_id} declares no stage {stage_id}."
            )));
        }
        self.runtime_store
            .set_orchestration_task_stage(task_id, Some(stage_id))
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }

    async fn known_profile_names(&mut self) -> HostResult<Vec<String>> {
        let profiles = self
            .runtime_store
            .list_agent_profiles()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(profiles.into_iter().map(|profile| profile.name).collect())
    }
}

/// The stage ids a stored policy declares.
pub(super) fn stage_ids(policy: &Value) -> Vec<String> {
    policy
        .get("stages")
        .and_then(Value::as_array)
        .map(|stages| {
            stages
                .iter()
                .filter_map(|stage| stage.get("id").and_then(Value::as_str))
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn stage_string(stage: &Map<String, Value>, key: &str, index: usize) -> HostResult<String> {
    stage
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::format(format!("policy.stages[{index}].{key} is required.")))
}

fn require_known_profile(known: &[String], name: &str) -> HostResult<()> {
    if known
        .iter()
        .any(|candidate| candidate.eq_ignore_ascii_case(name))
    {
        return Ok(());
    }
    Err(HostError::format(format!(
        "unknown agent profile: {name}. Declare it in Settings before referencing it in a policy."
    )))
}

fn policy_response(run: &OrchestrationCoordinatorRun) -> Value {
    let policy = run
        .execution_policy
        .as_deref()
        .and_then(|raw| serde_json::from_str::<Value>(raw).ok());
    json!({
        "runId": run.id,
        "workspaceId": run.workspace_id,
        "status": run.execution_policy_status.as_str(),
        "policy": policy,
        "updatedAt": run.execution_policy_updated_at,
        "blocksDispatch": run.execution_policy_status.blocks_dispatch(),
    })
}

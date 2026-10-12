//! A coordinator proposes its run's plan (`orchestration.planPropose`, plan
//! v2) and reads what it plans against (`orchestration.planContext`). Shared
//! stages name profiles from the catalog, so the host normalizes them before
//! the store validates and materializes the plan.

use alera_core::runtime::{RunActor, RunActorKind, RunPlanInput, RunPlanStageInput};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::orchestration_validation::{optional_string, require_string};
use super::ServerActor;

impl ServerActor {
    /// Stores the next plan revision of a run. With approval required it
    /// waits behind a plan gate; otherwise the run starts at once.
    pub(super) async fn orchestration_plan_propose(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let run_id = require_string(payload, "run")?;
        let raw = payload
            .get("plan")
            .cloned()
            .ok_or_else(|| HostError::format("plan is required."))?;
        let mut plan: RunPlanInput = serde_json::from_value(raw)
            .map_err(|error| HostError::format(format!("invalid plan: {error}")))?;
        plan.stages = self.normalized_plan_stages(plan.stages).await?;
        let actor = RunActor::new(RunActorKind::Agent, optional_string(payload, "from"));
        let proposed = self
            .runtime_store
            .propose_run_plan(&run_id, plan, &actor)
            .await
            .map_err(super::orchestration_gate_requests::gate_error)?;
        if let Some(gate_id) = proposed.plan_gate_id.as_deref() {
            if let Ok(Some(gate)) = self.runtime_store.orchestration_gate_by_id(gate_id).await {
                self.queue_gate_push(&gate).await;
            }
        }
        self.after_run_transition(&run_id).await;
        serde_json::to_value(proposed).map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn orchestration_plan_context(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let run_id = require_string(payload, "run")?;
        self.runtime_store
            .run_plan_context(&run_id)
            .await
            .map_err(super::orchestration_gate_requests::gate_error)
    }

    /// Every stage profile and fallback must name a profile in the catalog: a
    /// name that resolves to nothing would only fail much later, at dispatch.
    pub(super) async fn normalized_plan_stages(
        &mut self,
        stages: Vec<RunPlanStageInput>,
    ) -> HostResult<Vec<RunPlanStageInput>> {
        if stages.is_empty() {
            return Ok(stages);
        }
        let known = self.known_profile_names().await?;
        stages
            .into_iter()
            .map(|mut stage| {
                if let Some(profile) = stage.profile.as_deref().map(str::trim) {
                    stage.profile = Some(canonical_profile(&known, profile)?);
                }
                stage.fallbacks = stage
                    .fallbacks
                    .iter()
                    .map(|name| canonical_profile(&known, name.trim()))
                    .collect::<HostResult<_>>()?;
                stage.title = stage.title.map(|title| title.trim().to_string());
                Ok(stage)
            })
            .collect()
    }

    /// Converts a legacy stage policy (`{stages, stallPolicy}`) into plan v2
    /// stages for `orchestration.run --policy-file`.
    pub(super) fn policy_plan(policy: &Value) -> HostResult<RunPlanInput> {
        let object = policy
            .as_object()
            .ok_or_else(|| HostError::format("policy must be an object."))?;
        let mut plan = json!({ "stages": object.get("stages").cloned().unwrap_or(json!([])) });
        if let Some(stall) = object.get("stallPolicy") {
            plan["stallPolicy"] = stall.clone();
        }
        serde_json::from_value(plan)
            .map_err(|error| HostError::format(format!("invalid policy: {error}")))
    }

    /// Binds a task to a stage its run actually declares. A stage id that is not
    /// in the plan is rejected rather than stored, because a task pointing at a
    /// stage nobody declared can never resolve a profile.
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

fn canonical_profile(known: &[String], name: &str) -> HostResult<String> {
    known
        .iter()
        .find(|candidate| candidate.eq_ignore_ascii_case(name))
        .cloned()
        .ok_or_else(|| {
            HostError::format(format!(
                "unknown agent profile: {name}. Declare it in Settings before referencing it in a plan."
            ))
        })
}

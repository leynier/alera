use alera_core::runtime::{
    NewOrchestrationTask, OrchestrationCoordinatorStatus, RoleContractSnapshot, RoleContractV1,
};
use serde_json::{json, Value};

use super::orchestration_validation::{optional_string, require_string, state_error};
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

fn parse_role_contract(
    payload: &Value,
    contracted: bool,
) -> HostResult<Option<RoleContractSnapshot>> {
    if !contracted {
        if payload.get("roleContract").is_some() || payload.get("contractInputs").is_some() {
            return Err(HostError::format(
                "roleContract requires orchestration.taskCreateContracted.",
            ));
        }
        return Ok(None);
    }
    if payload
        .get("resultSchema")
        .is_some_and(|value| !value.is_null())
    {
        return Err(HostError::format(
            "roleContract and resultSchema are mutually exclusive.",
        ));
    }
    let definition = payload
        .get("roleContract")
        .ok_or_else(|| HostError::format("roleContract is required."))?;
    if serde_json::to_vec(definition).map_err(state_error)?.len() > 64 * 1024 {
        return Err(HostError::format("roleContract exceeds the size limit."));
    }
    let contract: RoleContractV1 =
        serde_json::from_value(definition.clone()).map_err(state_error)?;
    let inputs = payload
        .get("contractInputs")
        .ok_or_else(|| HostError::format("contractInputs is required."))?;
    RoleContractSnapshot::freeze(contract, inputs.clone())
        .map(Some)
        .map_err(state_error)
}

fn validate_result_schema_definition(schema_raw: &str) -> HostResult<()> {
    let schema: Value = serde_json::from_str(schema_raw)
        .map_err(|error| HostError::format(format!("result schema is invalid JSON: {error}")))?;
    jsonschema::validator_for(&schema)
        .map(|_| ())
        .map_err(|error| HostError::format(format!("result schema is invalid: {error}")))
}

impl ServerActor {
    pub(super) async fn orchestration_task_create(
        &mut self,
        payload: &Value,
        contracted: bool,
    ) -> HostResult<Value> {
        let contract = parse_role_contract(payload, contracted)?;
        let spec = require_string(payload, "spec")?;
        let result_schema = optional_string(payload, "resultSchema");
        if let Some(schema) = result_schema.as_deref() {
            validate_result_schema_definition(schema)?;
        }
        let created_by = optional_string(payload, "createdBy");
        let requested_coordinator = optional_string(payload, "coordinator");
        let workspace_id =
            optional_string(payload, "workspace").unwrap_or_else(|| "global".to_string());
        let run_id = optional_string(payload, "run");
        let coordinator_handle = if let Some(run_id) = run_id.as_deref() {
            let run = self
                .runtime_store
                .orchestration_coordinator_run_by_id(run_id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| HostError::state(format!("coordinator run not found: {run_id}")))?;
            if run.status != OrchestrationCoordinatorStatus::Running {
                return Err(HostError::state(format!(
                    "coordinator run is not accepting tasks: {run_id}"
                )));
            }
            if workspace_id != run.workspace_id {
                return Err(HostError::state(format!(
                    "task workspace {workspace_id} does not match run workspace {}",
                    run.workspace_id
                )));
            }
            let run_coordinator = run.coordinator_handle.ok_or_else(|| {
                HostError::state(format!("coordinator run has no owner: {run_id}"))
            })?;
            if requested_coordinator
                .as_deref()
                .is_some_and(|coordinator| coordinator != run_coordinator.as_str())
            {
                return Err(HostError::state(format!(
                    "task coordinator does not match run coordinator {run_coordinator}"
                )));
            }
            run_coordinator
        } else {
            requested_coordinator
                .or_else(|| created_by.clone())
                .unwrap_or_else(|| "coord".to_string())
        };
        let deps: Vec<String> = payload
            .get("deps")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_string)
                    .collect()
            })
            .unwrap_or_default();
        let task = self
            .runtime_store
            .create_orchestration_task_with_contract(
                NewOrchestrationTask {
                    spec,
                    task_title: optional_string(payload, "taskTitle"),
                    display_name: None,
                    deps,
                    parent_id: optional_string(payload, "parent"),
                    created_by_terminal_handle: created_by,
                    run_id,
                    workspace_id,
                    coordinator_handle,
                    result_schema,
                },
                contract,
            )
            .await
            .map_err(state_error)?;
        // Binding the stage after creation keeps `create_orchestration_task`
        // free of policy concerns; the stage is validated against the run's
        // approved plan rather than trusted from the payload.
        if let Some(stage) = optional_string(payload, "stage") {
            self.bind_task_to_policy_stage(&task.id, task.run_id.as_deref(), &stage)
                .await?;
            // Re-read rather than returning task_show: taskCreate always answers
            // with a bare task, and the stage must not change that shape.
            let stored = self
                .runtime_store
                .orchestration_task_by_id(&task.id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| {
                    HostError::state(format!("orchestration task not found: {}", task.id))
                })?;
            return Ok(json!(stored));
        }
        Ok(json!(task))
    }
}

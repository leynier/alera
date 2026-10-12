//! Agent gate verbs over `runGates`: create a decision gate on a task and
//! list gates by run, task, kind or status. People and coordinators resolve
//! gates with `runs.resolveGate`.

use alera_core::runtime::{
    GateFilter, OrchestrationCoordinatorStatus, OrchestrationGateStatus, RunGateKind,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::orchestration_validation::{optional_string, require_string};
use super::ServerActor;

/// Store errors carry a `gate_*: message` or `run_*: message` prefix;
/// surface the code so clients can branch on it.
pub(super) fn gate_error(error: anyhow::Error) -> HostError {
    let text = error.to_string();
    match text.split_once(": ") {
        Some((code, message))
            if (code.starts_with("gate_") || code.starts_with("run_"))
                && code
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_') =>
        {
            HostError::conflict(code, message, json!({}))
        }
        _ => HostError::state(text),
    }
}

fn string_list(payload: &Value, key: &str) -> Vec<String> {
    payload
        .get(key)
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

impl ServerActor {
    pub(super) async fn orchestration_gate_create(&mut self, payload: &Value) -> HostResult<Value> {
        let task_id = require_string(payload, "task")?;
        let question = require_string(payload, "question")?;
        let options = string_list(payload, "options");
        let gate = self
            .runtime_store
            .create_orchestration_gate(&task_id, &question, &options)
            .await
            .map_err(gate_error)?;
        self.queue_gate_push(&gate).await;
        self.broadcast_orchestration_board_change().await;
        Ok(json!(gate))
    }

    pub(super) async fn orchestration_gate_list(&mut self, payload: &Value) -> HostResult<Value> {
        let status = match optional_string(payload, "status") {
            None => None,
            Some(raw) => Some(
                OrchestrationGateStatus::parse(&raw)
                    .ok_or_else(|| HostError::format(format!("unknown gate status: {raw}")))?,
            ),
        };
        let kind = match optional_string(payload, "kind") {
            None => None,
            Some(raw) => Some(
                RunGateKind::parse(&raw)
                    .ok_or_else(|| HostError::format(format!("unknown gate kind: {raw}")))?,
            ),
        };
        let filter = GateFilter {
            run_id: optional_string(payload, "run"),
            task_id: optional_string(payload, "task"),
            kind,
            status,
        };
        let gates = self
            .runtime_store
            .list_gates(&filter)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(json!({
            "kind": "gates",
            "items": gates,
            "gates": gates,
            "filters": {
                "run": filter.run_id,
                "task": filter.task_id,
                "kind": kind.map(RunGateKind::as_str),
                "status": status.map(OrchestrationGateStatus::as_str),
            },
        }))
    }

    /// Stops a shared run's coordinator loop once its run is over, such as
    /// after its plan was rejected.
    pub(super) async fn stop_coordinator_if_run_finished(&mut self, run_id: &str) {
        let finished = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
            .ok()
            .flatten()
            .is_some_and(|run| {
                matches!(
                    run.status,
                    OrchestrationCoordinatorStatus::Completed
                        | OrchestrationCoordinatorStatus::Failed
                        | OrchestrationCoordinatorStatus::Cancelled
                )
            });
        if finished {
            if let Some(handle) = self.coordinators.remove(run_id) {
                handle.stop();
            }
            self.schedule_shutdown_if_idle();
        }
    }
}

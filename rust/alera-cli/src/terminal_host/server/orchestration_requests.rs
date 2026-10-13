use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::orchestration_validation::state_error;
use super::ServerActor;

pub(super) fn validate_result_schema(
    result: &serde_json::Map<String, Value>,
    schema_raw: Option<&str>,
) -> HostResult<()> {
    let Some(schema_raw) = schema_raw else {
        return Ok(());
    };
    let schema: Value = serde_json::from_str(schema_raw)
        .map_err(|error| HostError::state(format!("stored result schema is invalid: {error}")))?;
    let validator = jsonschema::validator_for(&schema)
        .map_err(|error| HostError::state(format!("stored result schema is invalid: {error}")))?;
    validator
        .validate(&Value::Object(result.clone()))
        .map_err(|error| HostError::format(format!("result does not match schema: {error}")))
}

impl ServerActor {
    pub(super) fn dispatch_context_path(&self, handle: &str) -> std::path::PathBuf {
        let safe_handle: String = handle
            .chars()
            .map(|value| {
                if value.is_ascii_alphanumeric() || value == '-' || value == '_' {
                    value
                } else {
                    '_'
                }
            })
            .collect();
        self.runtime_dir
            .join("orchestration-contexts")
            .join(format!("{safe_handle}.json"))
    }

    pub(super) fn install_dispatch_context(
        &self,
        handle: &str,
        dispatch_id: &str,
        token: &str,
    ) -> HostResult<()> {
        let path = self.dispatch_context_path(handle);
        let parent = path
            .parent()
            .ok_or_else(|| HostError::state("invalid dispatch context path"))?;
        std::fs::create_dir_all(parent).map_err(|error| HostError::state(error.to_string()))?;
        let bytes = serde_json::to_vec(&json!({ "dispatchId": dispatch_id, "token": token }))
            .map_err(|error| HostError::state(error.to_string()))?;
        #[cfg(unix)]
        {
            use std::io::Write;
            use std::os::unix::fs::OpenOptionsExt;
            let mut file = std::fs::OpenOptions::new()
                .create(true)
                .truncate(true)
                .write(true)
                .mode(0o600)
                .open(path)
                .map_err(|error| HostError::state(error.to_string()))?;
            file.write_all(&bytes)
                .map_err(|error| HostError::state(error.to_string()))?;
        }
        #[cfg(not(unix))]
        std::fs::write(path, bytes).map_err(|error| HostError::state(error.to_string()))?;
        Ok(())
    }

    pub(super) fn remove_dispatch_context(&self, handle: &str) {
        let _ = std::fs::remove_file(self.dispatch_context_path(handle));
    }

    /// Handles requests; wait-capable verbs return `Ok(None)` until a wake or timeout writes the response.
    pub(super) async fn handle_orchestration_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        // This router runs before `handle_request`, so it must apply the
        // mobile allowlist itself; no orchestration verb is on it.
        self.require_authenticated_local_request(client_id, request_type)?;
        super::inbox_guards::reject_inbox_address(request_type, payload)?;
        match request_type {
            "orchestration.agentSpawn" => self.orchestration_agent_spawn(payload).await.map(Some),
            "orchestration.agentSpawnTimeout" => self
                .orchestration_agent_spawn_timeout(payload)
                .await
                .map(Some),
            "orchestration.planPropose" => self.orchestration_plan_propose(payload).await.map(Some),
            "orchestration.planContext" => self.orchestration_plan_context(payload).await.map(Some),
            "orchestration.send" => self.orchestration_send(payload).await.map(Some),
            "orchestration.check" => {
                self.orchestration_check(client_id, request_id, payload)
                    .await
            }
            "orchestration.reply" => self.orchestration_reply(payload).await.map(Some),
            "orchestration.messages" => self.orchestration_messages(payload).await.map(Some),
            "orchestration.ask" => self.orchestration_ask(client_id, request_id, payload).await,
            "orchestration.agentStatus" => self.orchestration_agent_status(payload).await.map(Some),
            "orchestration.terminals" => Ok(Some(self.orchestration_terminals(payload))),
            "orchestration.terminalShow" => {
                self.orchestration_terminal_show(payload).await.map(Some)
            }
            "orchestration.terminalPrune" => {
                self.orchestration_terminal_prune(payload).await.map(Some)
            }
            "orchestration.terminalWait" => {
                self.orchestration_terminal_wait(client_id, request_id, payload)
                    .await
            }
            "orchestration.taskWait" => {
                self.orchestration_task_wait(client_id, request_id, payload)
                    .await
            }
            "orchestration.taskCreate" => self
                .orchestration_task_create(payload, false)
                .await
                .map(Some),
            "orchestration.taskCreateContracted" => self
                .orchestration_task_create(payload, true)
                .await
                .map(Some),
            "orchestration.taskList" => self.orchestration_task_list(payload).await.map(Some),
            "orchestration.taskShow" => self.orchestration_task_show(payload).await.map(Some),
            "orchestration.taskCancel" => self.orchestration_task_cancel(payload).await.map(Some),
            "orchestration.taskRecover" => self.orchestration_task_recover(payload).await.map(Some),
            "orchestration.transferCoordinator" => self
                .orchestration_transfer_coordinator(payload)
                .await
                .map(Some),
            "orchestration.dispatch" => self.orchestration_dispatch(payload).await.map(Some),
            "orchestration.dispatchShow" => {
                self.orchestration_dispatch_show(payload).await.map(Some)
            }
            "orchestration.dispatchInterrupt" => self
                .orchestration_dispatch_interrupt(payload)
                .await
                .map(Some),
            "orchestration.context" => self.orchestration_context(payload).await.map(Some),
            "orchestration.escalate" => self.orchestration_escalate(payload).await.map(Some),
            "orchestration.complete" => {
                self.orchestration_complete(client_id, request_id, payload)
                    .await
            }
            "orchestration.gateCreate" => self.orchestration_gate_create(payload).await.map(Some),
            "orchestration.gateList" => self.orchestration_gate_list(payload).await.map(Some),
            "orchestration.run" => self.orchestration_run(payload).await.map(Some),
            "orchestration.runList" => self.orchestration_run_list(payload).await.map(Some),
            "orchestration.runShow" => self.orchestration_run_show(payload).await.map(Some),
            "orchestration.status" => self.orchestration_status(payload).await.map(Some),
            "orchestration.runStop" => self.orchestration_run_stop(payload).await.map(Some),
            "orchestration.reset" => self.orchestration_reset(payload).await.map(Some),
            other => Err(HostError::state(format!(
                "Unknown orchestration request: {other}"
            ))),
        }
    }

    // --- reset --------------------------------------------------------------

    pub(super) async fn orchestration_reset(&mut self, payload: &Value) -> HostResult<Value> {
        let tasks = payload
            .get("tasks")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let messages = payload
            .get("messages")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        // No explicit scope means reset everything, mirroring Orca's --all
        // default.
        let all =
            (!tasks && !messages) || payload.get("all").and_then(Value::as_bool).unwrap_or(false);
        if all || tasks {
            let live_terminals = self
                .sessions
                .iter()
                .filter(|(_, session)| session.running())
                .map(|(terminal, _)| terminal.clone())
                .collect::<Vec<_>>();
            for terminal in live_terminals {
                if self.is_workflow_terminal(&terminal).await {
                    return Err(HostError::state(
                        "settle active workflow workers before resetting orchestration",
                    ));
                }
            }
            self.runtime_store
                .reset_orchestration_tasks()
                .await
                .map_err(state_error)?;
            for (_, handle) in self.coordinators.drain() {
                handle.stop();
            }
        }
        if all || messages {
            self.runtime_store
                .reset_orchestration_messages()
                .await
                .map_err(state_error)?;
        }
        Ok(json!({
            "tasks": all || tasks,
            "messages": all || messages,
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn result_schema_distinguishes_integer_from_fractional_number() {
        let schema = r#"{"properties":{"count":{"type":"integer"}}}"#;
        for value in [json!(1), json!(1.0)] {
            let result = json!({"count": value}).as_object().unwrap().clone();
            assert!(validate_result_schema(&result, Some(schema)).is_ok());
        }
        let fractional = json!({"count": 1.5}).as_object().unwrap().clone();
        assert!(validate_result_schema(&fractional, Some(schema)).is_err());
    }

    #[test]
    fn result_schema_enforces_nested_enum_items_and_additional_properties() {
        let schema = r#"{
            "type":"object",
            "required":["status","details"],
            "additionalProperties":false,
            "properties":{
                "status":{"enum":["ok"]},
                "details":{
                    "type":"object",
                    "required":["checks"],
                    "properties":{"checks":{"type":"array","items":{"type":"boolean"}}}
                }
            }
        }"#;
        let valid = json!({"status":"ok","details":{"checks":[true, false]}})
            .as_object()
            .unwrap()
            .clone();
        assert!(validate_result_schema(&valid, Some(schema)).is_ok());
        for invalid in [
            json!({"status":"bad","details":{"checks":[true]}}),
            json!({"status":"ok","details":{"checks":["yes"]}}),
            json!({"status":"ok","details":{"checks":[]},"extra":true}),
        ] {
            assert!(validate_result_schema(invalid.as_object().unwrap(), Some(schema)).is_err());
        }
    }
}

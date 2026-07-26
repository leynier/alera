use std::time::{Duration, Instant};

use alera_core::runtime::OrchestrationTaskStatus;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::message_waiters::{MessageWaiter, WaitKind};
use crate::terminal_host::protocol::ok_response;

use super::orchestration_validation::{require_string, state_error, state_wait_timeout_ms};
use super::{ServerActor, ServerCommand};

const STATE_WAIT_POLL_MS: u64 = 100;

impl ServerActor {
    pub(super) async fn orchestration_terminal_wait(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let started_at = Instant::now();
        let handle = require_string(payload, "terminal")?;
        let target = require_string(payload, "target")?;
        validate_terminal_target(&target)?;
        if let Some(response) = self.terminal_wait_result(&handle, &target).await? {
            return Ok(Some(with_waited_ms(response, started_at)));
        }
        let waiter_id = self.orchestration_waiters.register(
            client_id,
            request_id,
            handle,
            WaitKind::TerminalState { target },
        );
        self.spawn_state_wait_poll(waiter_id);
        self.spawn_wait_timeout(waiter_id, state_wait_timeout_ms(payload));
        Ok(None)
    }

    pub(super) async fn orchestration_task_wait(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let started_at = Instant::now();
        let task_id = require_string(payload, "task")?;
        let targets = parse_task_targets(payload)?;
        if let Some(response) = self.task_wait_result(&task_id, &targets).await? {
            return Ok(Some(with_waited_ms(response, started_at)));
        }
        let waiter_id = self.orchestration_waiters.register(
            client_id,
            request_id,
            task_id,
            WaitKind::TaskState { targets },
        );
        self.spawn_state_wait_poll(waiter_id);
        self.spawn_wait_timeout(waiter_id, state_wait_timeout_ms(payload));
        Ok(None)
    }

    pub(super) async fn handle_orchestration_state_wait_poll(&mut self, waiter_id: u64) {
        let Some(waiter) = self.orchestration_waiters.take_by_id(waiter_id) else {
            return;
        };
        match self.state_wait_result(&waiter).await {
            Ok(Some(payload)) => {
                self.client_write(
                    waiter.client_id,
                    ok_response(
                        waiter.request_id,
                        with_waited_ms(payload, waiter.started_at),
                    ),
                );
            }
            Ok(None) => {
                self.orchestration_waiters.repark(waiter);
                self.spawn_state_wait_poll(waiter_id);
            }
            Err(error) => {
                self.client_write(
                    waiter.client_id,
                    crate::terminal_host::protocol::error_response(waiter.request_id, &error),
                );
            }
        }
    }

    pub(super) async fn finish_orchestration_state_wait_timeout(
        &mut self,
        waiter: MessageWaiter,
        effective_timeout_ms: u64,
    ) {
        match self.state_wait_result(&waiter).await {
            Ok(Some(payload)) => {
                self.client_write(
                    waiter.client_id,
                    ok_response(
                        waiter.request_id,
                        with_waited_ms(payload, waiter.started_at),
                    ),
                );
            }
            Ok(None) => {
                self.client_write(
                    waiter.client_id,
                    ok_response(
                        waiter.request_id,
                        // See the sibling finisher: the wait ran its whole
                        // budget, so elapsed and budget coincide here, and both
                        // are reported because they answer different questions.
                        json!({
                            "outcome": "timeout",
                            "timedOut": true,
                            "waitedMs": effective_timeout_ms,
                            "effectiveTimeoutMs": effective_timeout_ms,
                        }),
                    ),
                );
            }
            Err(error) => {
                self.client_write(
                    waiter.client_id,
                    crate::terminal_host::protocol::error_response(waiter.request_id, &error),
                );
            }
        }
    }

    async fn state_wait_result(&mut self, waiter: &MessageWaiter) -> HostResult<Option<Value>> {
        match &waiter.kind {
            WaitKind::TerminalState { target } => {
                self.terminal_wait_result(&waiter.handle, target).await
            }
            WaitKind::TaskState { targets } => self.task_wait_result(&waiter.handle, targets).await,
            WaitKind::Check { .. } | WaitKind::Ask { .. } => Ok(None),
        }
    }

    async fn terminal_wait_result(
        &mut self,
        handle: &str,
        target: &str,
    ) -> HostResult<Option<Value>> {
        let terminal = self
            .orchestration_terminal_show(&json!({ "handle": handle }))
            .await?;
        let state = terminal
            .get("startupState")
            .and_then(Value::as_str)
            .unwrap_or("");
        if state == "failed" {
            return Ok(Some(json!({
                "outcome": "failed",
                "error": terminal.get("startupError"),
                "terminal": terminal,
            })));
        }
        Ok(terminal_target_reached(state, target).then(|| {
            json!({
                "outcome": "reached",
                "state": state,
                "terminal": terminal,
            })
        }))
    }

    async fn task_wait_result(
        &self,
        task_id: &str,
        targets: &[OrchestrationTaskStatus],
    ) -> HostResult<Option<Value>> {
        let task = self
            .runtime_store
            .orchestration_task_by_id(task_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {task_id}")))?;
        Ok(targets.contains(&task.status).then(|| {
            json!({
                "outcome": "reached",
                "state": task.status.as_str(),
                "task": task,
            })
        }))
    }

    fn spawn_state_wait_poll(&self, waiter_id: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(STATE_WAIT_POLL_MS)).await;
            let _ = inbox.send(ServerCommand::OrchestrationStateWaitPoll(waiter_id));
        });
    }
}

fn with_waited_ms(mut payload: Value, started_at: Instant) -> Value {
    if let Some(object) = payload.as_object_mut() {
        object.insert(
            "waitedMs".to_string(),
            json!(u64::try_from(started_at.elapsed().as_millis()).unwrap_or(u64::MAX)),
        );
    }
    payload
}

fn validate_terminal_target(target: &str) -> HostResult<()> {
    if matches!(
        target,
        "process-started" | "agent-detected" | "agent-ready" | "dispatch-accepted"
    ) {
        Ok(())
    } else {
        Err(HostError::format(format!(
            "unsupported terminal wait target: {target}"
        )))
    }
}

fn terminal_target_reached(state: &str, target: &str) -> bool {
    match target {
        "process-started" => !state.is_empty() && state != "failed",
        "agent-detected" => matches!(
            state,
            "agent_detected"
                | "agent_ready"
                | "dispatch_submitted_unconfirmed"
                | "accepted"
                | "completed"
        ),
        "agent-ready" => matches!(
            state,
            "agent_ready" | "dispatch_submitted_unconfirmed" | "accepted" | "completed"
        ),
        "dispatch-accepted" => matches!(state, "accepted" | "completed" | "stalled"),
        _ => false,
    }
}

fn parse_task_targets(payload: &Value) -> HostResult<Vec<OrchestrationTaskStatus>> {
    let raw = payload
        .get("targets")
        .and_then(Value::as_array)
        .ok_or_else(|| HostError::format("targets must be a non-empty status array"))?;
    let targets = raw
        .iter()
        .map(|value| {
            let status = value
                .as_str()
                .ok_or_else(|| HostError::format("task wait statuses must be strings"))?;
            OrchestrationTaskStatus::parse(status)
                .ok_or_else(|| HostError::format(format!("unsupported task status: {status}")))
        })
        .collect::<HostResult<Vec<_>>>()?;
    if targets.is_empty() {
        return Err(HostError::format(
            "targets must contain at least one task status",
        ));
    }
    Ok(targets)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_targets_include_later_states() {
        assert!(terminal_target_reached("accepted", "agent-ready"));
        assert!(terminal_target_reached("completed", "dispatch-accepted"));
        assert!(terminal_target_reached("stalled", "dispatch-accepted"));
        assert!(!terminal_target_reached(
            "dispatch_submitted_unconfirmed",
            "dispatch-accepted"
        ));
    }

    #[test]
    fn parses_task_targets() {
        let targets = parse_task_targets(&json!({ "targets": ["completed", "failed"] })).unwrap();
        assert_eq!(
            targets,
            vec![
                OrchestrationTaskStatus::Completed,
                OrchestrationTaskStatus::Failed
            ]
        );
    }
}

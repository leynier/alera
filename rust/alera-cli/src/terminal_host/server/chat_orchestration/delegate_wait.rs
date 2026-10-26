use std::time::Duration;

use alera_core::runtime::{ChatOrchestrationNotify, ChatOrchestrationTaskStatus};
use serde_json::Value;

use super::service::ChatOrchestrationService;
use super::tasks::task_value;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ChatOrchestrationService {
    pub(super) async fn wait_for_delegate(
        &self,
        task_id: &str,
        wait_seconds: u64,
        notify: ChatOrchestrationNotify,
    ) -> HostResult<Value> {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(wait_seconds);
        loop {
            let task = self
                .store
                .chat_orchestration_task(task_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| HostError::state("The delegated task no longer exists."))?;
            if task.status.is_terminal() {
                let task = self
                    .store
                    .finish_chat_orchestration_wait(task_id, notify)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                self.emit_change(&task).await;
                return Ok(task_value(&task));
            }
            if task.status == ChatOrchestrationTaskStatus::NeedsInput
                || tokio::time::Instant::now() >= deadline
            {
                let timed_out = task.status != ChatOrchestrationTaskStatus::NeedsInput;
                let policy = if timed_out && notify != ChatOrchestrationNotify::Never {
                    ChatOrchestrationNotify::Always
                } else {
                    notify
                };
                let task = self
                    .store
                    .finish_chat_orchestration_wait(task_id, policy)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                self.emit_change(&task).await;
                self.deliver_task_wake(&task).await;
                let mut response = task_value(&task);
                response["timedOut"] = serde_json::json!(timed_out);
                return Ok(response);
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }
}

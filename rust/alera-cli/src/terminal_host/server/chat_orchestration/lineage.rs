use alera_core::runtime::{ChatOrchestrationTaskFilter, ChatOrchestrationTaskStatus};

use super::service::ChatOrchestrationService;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ChatOrchestrationService {
    pub(super) async fn parent_task_id_for_chat(
        &self,
        parent_chat_id: Option<&str>,
    ) -> HostResult<Option<String>> {
        let Some(parent_chat_id) = parent_chat_id else {
            return Ok(None);
        };
        let snapshot = self.runtime.snapshot(parent_chat_id).await?;
        let Some(active_turn) = snapshot["session"]["activeTurnId"].as_str() else {
            return Ok(None);
        };
        let mut cursor = None;
        loop {
            let page = self
                .store
                .list_chat_orchestration_tasks(&ChatOrchestrationTaskFilter {
                    child_chat_id: Some(parent_chat_id.to_owned()),
                    statuses: vec![
                        ChatOrchestrationTaskStatus::Preparing,
                        ChatOrchestrationTaskStatus::Running,
                        ChatOrchestrationTaskStatus::NeedsInput,
                        ChatOrchestrationTaskStatus::CancelRequested,
                    ],
                    before_sequence: cursor,
                    ..Default::default()
                })
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            for task in page.tasks {
                let turn = self
                    .runtime
                    .turn_for_client_message(
                        parent_chat_id,
                        &format!("chat-orchestration-task:{}", task.task_id),
                    )
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                if turn.as_ref().and_then(|turn| turn["turnId"].as_str()) == Some(active_turn) {
                    return Ok(Some(task.task_id));
                }
            }
            let Some(next) = page.next_before_sequence else {
                return Ok(None);
            };
            cursor = Some(next);
        }
    }
}

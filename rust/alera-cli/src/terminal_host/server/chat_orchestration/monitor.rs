use std::time::Duration;

use crate::terminal_host::host_error::HostError;
use alera_core::runtime::ChatOrchestrationTaskStatus;
use serde_json::json;

use super::service::ChatOrchestrationService;
use super::tasks::{final_assistant_text, matching_turn, parse_turn_status, transition_status};
use super::wakes::deliver_next_wake;

const TASK_POLL: Duration = Duration::from_millis(100);

impl ChatOrchestrationService {
    pub(crate) fn resume_task_monitors(
        &self,
        tasks: &[alera_core::runtime::ChatOrchestrationTask],
    ) {
        for task in tasks.iter().filter(|task| !task.status.is_terminal()) {
            if let Some(child) = &task.child_chat_id {
                self.spawn_task_monitor(
                    task.task_id.clone(),
                    child.clone(),
                    format!("chat-orchestration-task:{}", task.task_id),
                );
            }
        }
    }

    pub(super) async fn fail_task(
        &self,
        task_id: &str,
        child_chat_id: Option<String>,
        error_code: &str,
        error: String,
    ) {
        let Ok(Some(task)) = self.store.chat_orchestration_task(task_id).await else {
            return;
        };
        if task.status.is_terminal() {
            return;
        }
        let (from, to, code) = if task.status == ChatOrchestrationTaskStatus::CancelRequested {
            (task.status, ChatOrchestrationTaskStatus::Cancelled, None)
        } else {
            (
                task.status,
                ChatOrchestrationTaskStatus::Failed,
                Some(error_code.to_owned()),
            )
        };
        let transition = transition_status(
            from,
            to,
            child_chat_id.or(task.child_chat_id),
            task.child_turn_id,
            None,
            code,
            Some(error),
        );
        if let Ok(alera_core::runtime::ChatOrchestrationTransitionOutcome::Applied {
            task, ..
        }) = self
            .store
            .transition_chat_orchestration_task(task_id, &transition)
            .await
        {
            self.emit_change(&task).await;
            self.deliver_task_wake(&task).await;
        }
    }

    pub(super) fn spawn_task_monitor(
        &self,
        task_id: String,
        child_chat_id: String,
        client_message_id: String,
    ) {
        let service = self.clone();
        tokio::spawn(async move {
            service
                .monitor_task(task_id, child_chat_id, client_message_id)
                .await;
        });
    }

    async fn monitor_task(
        &self,
        task_id: String,
        child_chat_id: String,
        client_message_id: String,
    ) {
        loop {
            let mut task = match self.store.chat_orchestration_task(&task_id).await {
                Ok(Some(task)) => task,
                _ => return,
            };
            if task.status.is_terminal() {
                return;
            }
            if task.status == ChatOrchestrationTaskStatus::CancelRequested {
                match self.stop_task_input(&task).await {
                    Ok(false) => {
                        if self.settle_task_cancelled(&task).await.is_ok() {
                            return;
                        }
                        tokio::time::sleep(Duration::from_secs(1)).await;
                        continue;
                    }
                    Ok(true) => {}
                    Err(error) => {
                        let missing = matches!(&error, HostError::Conflict {code, ..} if code == "chat_not_found" || code == "chatNotFound");
                        if missing {
                            self.fail_task(
                                &task_id,
                                Some(child_chat_id.clone()),
                                "childUnavailable",
                                error.wire_message(),
                            )
                            .await;
                            return;
                        }
                        tokio::time::sleep(Duration::from_secs(1)).await;
                        continue;
                    }
                }
            }
            let snapshot = match self.runtime.snapshot(&child_chat_id).await {
                Ok(snapshot) => snapshot,
                Err(error) => {
                    let remote = task.host_id.as_deref().is_some_and(|host| host != "local");
                    let missing = matches!(&error, HostError::Conflict {code, ..} if code == "chat_not_found" || code == "chatNotFound");
                    if remote && !missing {
                        tokio::time::sleep(Duration::from_secs(1)).await;
                        continue;
                    }
                    self.fail_task(
                        &task_id,
                        Some(child_chat_id.clone()),
                        "childUnavailable",
                        error.wire_message(),
                    )
                    .await;
                    return;
                }
            };
            let owned_turn = self
                .runtime
                .turn_for_client_message(&child_chat_id, &client_message_id)
                .await
                .ok()
                .flatten();
            let turn_id = owned_turn
                .as_ref()
                .and_then(|turn| turn["turnId"].as_str())
                .map(ToOwned::to_owned)
                .or_else(|| matching_turn(&snapshot, &client_message_id).map(|(_, turn)| turn));
            let Some(turn_id) = turn_id else {
                tokio::time::sleep(TASK_POLL).await;
                continue;
            };
            if task.child_turn_id.as_deref() != Some(turn_id.as_str()) {
                task = match self
                    .store
                    .record_chat_orchestration_task_turn(&task_id, &child_chat_id, &turn_id)
                    .await
                {
                    Ok(task) => task,
                    Err(error) => {
                        self.fail_task(
                            &task_id,
                            Some(child_chat_id.clone()),
                            "turn_link_conflict",
                            error.to_string(),
                        )
                        .await;
                        return;
                    }
                };
                self.emit_change(&task).await;
                if task.status.is_terminal() {
                    return;
                }
            }
            let pending = snapshot["pendingRequests"]
                .as_array()
                .map(|requests| {
                    requests
                        .iter()
                        .filter(|request| request["turnId"] == turn_id)
                        .count()
                })
                .unwrap_or(0);
            let durable_turn = self
                .runtime
                .child_turn(&child_chat_id, &turn_id)
                .await
                .ok()
                .flatten();
            let status = durable_turn
                .as_ref()
                .and_then(|turn| turn.turn_status.clone())
                .or_else(|| parse_turn_status(&snapshot, &turn_id));
            if pending > 0
                && status.as_deref() == Some("running")
                && task.status == ChatOrchestrationTaskStatus::Running
            {
                let transition = transition_status(
                    ChatOrchestrationTaskStatus::Running,
                    ChatOrchestrationTaskStatus::NeedsInput,
                    Some(child_chat_id.clone()),
                    Some(turn_id.clone()),
                    None,
                    None,
                    None,
                );
                if let Ok(alera_core::runtime::ChatOrchestrationTransitionOutcome::Applied {
                    task,
                    ..
                }) = self
                    .store
                    .transition_chat_orchestration_task(&task_id, &transition)
                    .await
                {
                    self.emit_change(&task).await;
                }
                tokio::time::sleep(TASK_POLL).await;
                continue;
            }
            if pending == 0
                && task.status == ChatOrchestrationTaskStatus::NeedsInput
                && status.as_deref() == Some("running")
            {
                let transition = transition_status(
                    ChatOrchestrationTaskStatus::NeedsInput,
                    ChatOrchestrationTaskStatus::Running,
                    Some(child_chat_id.clone()),
                    Some(turn_id.clone()),
                    None,
                    None,
                    None,
                );
                if let Ok(alera_core::runtime::ChatOrchestrationTransitionOutcome::Applied {
                    task,
                    ..
                }) = self
                    .store
                    .transition_chat_orchestration_task(&task_id, &transition)
                    .await
                {
                    self.emit_change(&task).await;
                }
            }
            let Some(status) = status else {
                tokio::time::sleep(TASK_POLL).await;
                continue;
            };
            let Some(mut next) = (match status.as_str() {
                "completed" => Some(ChatOrchestrationTaskStatus::Completed),
                "failed" => Some(ChatOrchestrationTaskStatus::Failed),
                "interrupted" => Some(ChatOrchestrationTaskStatus::Interrupted),
                "cancelled" => Some(ChatOrchestrationTaskStatus::Cancelled),
                _ => None,
            }) else {
                tokio::time::sleep(TASK_POLL).await;
                continue;
            };
            if task.status == ChatOrchestrationTaskStatus::CancelRequested
                && next == ChatOrchestrationTaskStatus::Interrupted
            {
                next = ChatOrchestrationTaskStatus::Cancelled;
            }
            let result_text = durable_turn
                .as_ref()
                .and_then(|turn| turn.final_assistant_text.clone())
                .or_else(|| final_assistant_text(&snapshot, &turn_id));
            let error_message = snapshot["turns"]
                .as_array()
                .and_then(|turns| turns.iter().find(|turn| turn["turnId"] == turn_id))
                .and_then(|turn| turn["errorMessage"].as_str())
                .map(ToOwned::to_owned);
            let transition = transition_status(
                task.status,
                next,
                Some(child_chat_id.clone()),
                Some(turn_id.clone()),
                result_text,
                (next == ChatOrchestrationTaskStatus::Failed).then_some("turnFailed".into()),
                error_message,
            );
            match self
                .store
                .transition_chat_orchestration_task(&task_id, &transition)
                .await
            {
                Ok(alera_core::runtime::ChatOrchestrationTransitionOutcome::Applied {
                    task,
                    ..
                }) => {
                    self.emit_change(&task).await;
                    self.deliver_task_wake(&task).await;
                    return;
                }
                Ok(alera_core::runtime::ChatOrchestrationTransitionOutcome::Rejected {
                    current,
                }) if current.status.is_terminal() => return,
                _ => {}
            }
            tokio::time::sleep(TASK_POLL).await;
        }
    }

    pub(super) async fn deliver_task_wake(
        &self,
        task: &alera_core::runtime::ChatOrchestrationTask,
    ) {
        if let Some(parent) = &task.parent_chat_id {
            let _ =
                deliver_next_wake(&self.store, self.runtime.as_ref(), parent, &self.events).await;
        }
    }

    pub(super) async fn emit_change(&self, task: &alera_core::runtime::ChatOrchestrationTask) {
        self.events
            .changed(json!({
                "taskId": task.task_id,
                "parentChatId": task.parent_chat_id,
                "childChatId": task.child_chat_id,
                "workspaceId": task.workspace_id,
            }))
            .await;
    }
}

//! A question a delegated child asks (`tool_user_input`) reaches its agent
//! parent as one queued message per request, so the parent can answer it
//! with `chat_respond` or ask the user. Approvals and every other request
//! kind stay with the person, as do questions in tasks a person owns.
//!
//! A message never interrupts or steers the parent, and it is withdrawn
//! from the parent's queue once its question no longer waits.

use std::collections::{HashMap, HashSet};
use std::time::Duration;

use alera_core::runtime::{
    ChatOrchestrationNotify, ChatOrchestrationTask, ChatOrchestrationTaskStatus,
    INPUT_OWNER_PARENT, INPUT_OWNER_PERSON,
};
use serde_json::{json, Value};
use tokio::time::Instant;

use super::service::ChatOrchestrationService;
use crate::terminal_host::host_error::HostError;
use crate::terminal_host::server::agent_chat_runtime::commands::{CallerCtx, ChatOp, SendInput};

const QUESTION_KIND: &str = "tool_user_input";
const RESEND_BACKOFF: Duration = Duration::from_secs(5);

/// Where each routed question stands for one monitor.
#[derive(Default)]
pub(super) struct Questions {
    state: HashMap<String, QuestionState>,
    swept: bool,
}

enum QuestionState {
    Sent,
    Backoff(Instant),
    Done,
}

fn message_id_prefix(parent: &str, child: &str) -> String {
    format!("chat-orchestration-question:{parent}:{child}:")
}

/// The agent parent a task's questions go to, if any.
fn agent_parent(task: &ChatOrchestrationTask) -> Option<&str> {
    let parent = task.parent_chat_id.as_deref()?;
    let stopped = task
        .launch_options
        .as_ref()
        .and_then(|options| options.get("parentStopped"))
        == Some(&Value::Bool(true));
    (task.caller_scope == format!("chat:{parent}")
        && task.notify != ChatOrchestrationNotify::Never
        && !stopped)
        .then_some(parent)
}

fn is_question(request: &Value) -> bool {
    request["kind"] == QUESTION_KIND
}

/// Who answers the open requests: the agent parent only when every one is a
/// question routed to it.
pub(super) fn input_owner(task: &ChatOrchestrationTask, requests: &[&Value]) -> &'static str {
    if agent_parent(task).is_some()
        && !requests.is_empty()
        && requests.iter().all(|r| is_question(r))
    {
        INPUT_OWNER_PARENT
    } else {
        INPUT_OWNER_PERSON
    }
}

/// The message a parent receives for one question. Deterministic, so a
/// resend replays the first send.
pub(super) fn question_text(task: &ChatOrchestrationTask, child: &str, request: &Value) -> String {
    let request_id = request["requestId"].as_str().unwrap_or_default();
    let title = task
        .title
        .as_deref()
        .map(|title| {
            format!(
                " ({})",
                title.split_whitespace().collect::<Vec<_>>().join(" ")
            )
        })
        .unwrap_or_default();
    let mut text = format!(
        "Delegated task {}{title} asked a question in chat {child} (request {request_id}).",
        task.task_id
    );
    let questions = request["questions"]
        .as_array()
        .filter(|questions| !questions.is_empty());
    match questions {
        Some(questions) => {
            for question in questions {
                let id = question["id"].as_str().unwrap_or_default();
                let prompt = question["question"]
                    .as_str()
                    .or_else(|| question["header"].as_str())
                    .unwrap_or_default();
                text.push_str(&format!("\n\nQuestion {id}: {prompt}"));
                let options: Vec<&str> = question["options"]
                    .as_array()
                    .map(|options| {
                        options
                            .iter()
                            .filter_map(|option| option["label"].as_str())
                            .collect()
                    })
                    .unwrap_or_default();
                if !options.is_empty() {
                    text.push_str(&format!("\nOptions: {}", options.join(" | ")));
                }
            }
        }
        None => {
            let prompt = request["title"]
                .as_str()
                .or_else(|| request["detail"].as_str())
                .unwrap_or("The child asked for input.");
            text.push_str(&format!("\n\n{prompt}"));
        }
    }
    text.push_str(&format!(
        "\n\nRead it with chat_requests and chatId {child}. When the answer follows from the task or the user's instructions, answer it with chat_respond, chatId {child}, runtimeRequestId {request_id} and response {{\"type\":\"userInput\",\"answers\":{{\"<questionId>\": <answer>}}}}. Otherwise ask the user first."
    ));
    text
}

fn done_error(error: &HostError) -> bool {
    matches!(error, HostError::Conflict { code, .. }
        if matches!(code.as_str(), "chatArchived" | "chat_archived" | "request_conflict" | "request_resolved"))
}

impl ChatOrchestrationService {
    /// Sends each open question the task's agent parent has not received,
    /// and withdraws the messages of questions that no longer wait.
    pub(super) async fn route_questions(
        &self,
        task: &ChatOrchestrationTask,
        child: &str,
        requests: &[&Value],
        questions: &mut Questions,
    ) {
        let Some(parent) = task.parent_chat_id.as_deref() else {
            return;
        };
        let open: HashSet<String> = requests
            .iter()
            .filter(|request| is_question(request))
            .filter_map(|request| request["requestId"].as_str().map(ToOwned::to_owned))
            .collect();
        let withdrawn = questions
            .state
            .iter()
            .any(|(id, state)| matches!(state, QuestionState::Sent) && !open.contains(id));
        if !questions.swept || withdrawn {
            self.withdraw_questions(parent, child, &open).await;
            questions.swept = true;
            questions.state.retain(|id, _| open.contains(id));
        }
        if agent_parent(task).is_none()
            || task.status != ChatOrchestrationTaskStatus::NeedsInput
            || self.wake_pump.wait_is_live(&task.task_id)
        {
            return;
        }
        for request in requests.iter().filter(|request| is_question(request)) {
            let Some(request_id) = request["requestId"].as_str() else {
                continue;
            };
            match questions.state.get(request_id) {
                Some(QuestionState::Sent | QuestionState::Done) => continue,
                Some(QuestionState::Backoff(until)) if Instant::now() < *until => continue,
                _ => {}
            }
            let state = match self.send_question(task, parent, child, request).await {
                Ok(()) => QuestionState::Sent,
                Err(error) if done_error(&error) => QuestionState::Done,
                Err(_) => QuestionState::Backoff(Instant::now() + RESEND_BACKOFF),
            };
            questions.state.insert(request_id.to_owned(), state);
        }
    }

    async fn send_question(
        &self,
        task: &ChatOrchestrationTask,
        parent: &str,
        child: &str,
        request: &Value,
    ) -> Result<(), HostError> {
        let request_id = request["requestId"].as_str().unwrap_or_default();
        self.runtime
            .send(
                parent,
                SendInput {
                    client_message_id: format!("{}{request_id}", message_id_prefix(parent, child)),
                    text: question_text(task, child, request),
                    attachments: Vec::new(),
                    delivery: "queue".into(),
                    model: None,
                    reasoning_effort: None,
                    interaction_mode: None,
                    runtime_mode_ceiling: None,
                    origin: Some(json!({
                        "kind": "orchestrationWake",
                        "taskIds": [task.task_id],
                        "requestIds": [request_id],
                    })),
                },
                CallerCtx {
                    scope: format!("chat:{parent}"),
                    actor: format!("agent:{parent}"),
                    mobile: false,
                },
            )
            .await
            .map(|_| ())
    }

    /// Cancels the queued question messages from `child` in `parent` whose
    /// request is not in `keep`.
    pub(super) async fn withdraw_questions(
        &self,
        parent: &str,
        child: &str,
        keep: &HashSet<String>,
    ) {
        let Ok(snapshot) = self.runtime.snapshot(parent).await else {
            return;
        };
        let prefix = message_id_prefix(parent, child);
        let stale: Vec<String> = snapshot["queue"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|entry| {
                let request = entry["clientMessageId"].as_str()?.strip_prefix(&prefix)?;
                (!keep.contains(request))
                    .then(|| entry["queueId"].as_str().map(ToOwned::to_owned))?
            })
            .collect();
        for queue_id in stale {
            let _ = self
                .runtime
                .command(
                    parent,
                    ChatOp::QueueCancel { queue_id },
                    CallerCtx::runtime(),
                    None,
                )
                .await;
        }
    }

    /// Withdraws every question message of a task whose monitor ended.
    pub(super) async fn withdraw_task_questions(&self, task_id: &str) {
        let Ok(Some(task)) = self.store.chat_orchestration_task(task_id).await else {
            return;
        };
        if let (Some(parent), Some(child)) = (&task.parent_chat_id, &task.child_chat_id) {
            self.withdraw_questions(parent, child, &HashSet::new())
                .await;
        }
    }

    /// Records who answers the task's open input when it changed.
    pub(super) async fn set_input_owner(&self, task: &ChatOrchestrationTask, requests: &[&Value]) {
        let owner = input_owner(task, requests);
        let current = task
            .launch_options
            .as_ref()
            .and_then(|options| options.get("inputOwner"))
            .and_then(Value::as_str);
        if current == Some(owner) {
            return;
        }
        if self
            .store
            .set_chat_orchestration_input_owner(&task.task_id, owner)
            .await
            .is_ok()
        {
            if let Ok(Some(task)) = self.store.chat_orchestration_task(&task.task_id).await {
                self.emit_change(&task).await;
            }
        }
    }
}

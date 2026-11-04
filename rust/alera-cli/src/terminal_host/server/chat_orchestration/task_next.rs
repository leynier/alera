//! The `next` hint beside a running task: a bound agent whose chat the task
//! will wake ends its turn instead of waiting on the task or polling it.

use alera_core::runtime::{
    ChatOrchestrationNotify, ChatOrchestrationResultDelivery, ChatOrchestrationTask,
    ChatOrchestrationTaskStatus,
};
use serde_json::{json, Value};

use super::authorization::OrchestrationCaller;

pub(super) const RUNNING_TASK_NEXT: &str =
    "Completion wakes this chat, so end your turn. Do not wait on it or poll it.";

/// Whether `task`'s completion will wake the chat `caller` is bound to.
pub(super) fn wakes_caller(task: &ChatOrchestrationTask, caller: &OrchestrationCaller) -> bool {
    let Some(bound) = &caller.bound else {
        return false;
    };
    task.parent_chat_id.as_deref() == Some(bound.chat_id.as_str())
        && matches!(
            task.status,
            ChatOrchestrationTaskStatus::Preparing | ChatOrchestrationTaskStatus::Running
        )
        && task.notify != ChatOrchestrationNotify::Never
        && task.result_delivery != ChatOrchestrationResultDelivery::Acknowledged
        && !parent_stopped(task)
}

fn parent_stopped(task: &ChatOrchestrationTask) -> bool {
    task.launch_options
        .as_ref()
        .and_then(|options| options.get("parentStopped"))
        .is_some_and(|stopped| stopped == &Value::Bool(true))
}

/// Adds `next` to a response that holds `task` when its completion wakes the
/// caller.
pub(super) fn add_next(
    response: &mut Value,
    task: &ChatOrchestrationTask,
    caller: &OrchestrationCaller,
) {
    if wakes_caller(task, caller) {
        response["next"] = json!(RUNNING_TASK_NEXT);
    }
}

/// Adds `next` to a timed-out `wait` when every open task wakes the caller.
pub(super) fn add_wait_next(
    response: &mut Value,
    tasks: &[ChatOrchestrationTask],
    caller: &OrchestrationCaller,
) {
    if response["timedOut"] != Value::Bool(true) {
        return;
    }
    let mut open = tasks
        .iter()
        .filter(|task| !task.status.is_terminal())
        .peekable();
    if open.peek().is_some() && open.all(|task| wakes_caller(task, caller)) {
        response["next"] = json!(RUNNING_TASK_NEXT);
    }
}

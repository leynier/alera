//! Which child turns continue a delegated task's work, and whether a child
//! still has work left after its turn ended. Pure reads of snapshots and
//! recorded turns.

use alera_core::runtime::{
    ChatOrchestrationChildTurn, ChatOrchestrationTask, CHAIN_START_TURN_KEY,
};
use alera_provider_protocol::BACKGROUND_CONTINUATION_ORIGIN;
use serde_json::Value;

/// A turn the agent started on its own to keep working toward its goal
/// (`agent_chat_runtime::session_goal`).
pub(super) const GOAL_CONTINUATION_ORIGIN: &str = "goalContinuation";
const SUBAGENT_WAKE: &str = "subagentWake";
const ORCHESTRATION_WAKE: &str = "orchestrationWake";
/// A user message that answers a question by message
/// (`agent_chat_runtime::session_question_answers`).
const QUESTION_ANSWER: &str = "questionAnswer";

fn message_kind(turn: &ChatOrchestrationChildTurn) -> Option<&str> {
    turn.message_origin
        .as_ref()
        .and_then(|origin| origin.get("kind"))
        .and_then(Value::as_str)
}

/// Whether a turn continues the work of the turn before it: a background
/// or goal continuation, or a wake from a native sub-agent or a delegated
/// task.
pub(super) fn is_continuation(turn: &ChatOrchestrationChildTurn) -> bool {
    matches!(
        turn.turn_origin.as_deref(),
        Some(BACKGROUND_CONTINUATION_ORIGIN | GOAL_CONTINUATION_ORIGIN)
    ) || matches!(
        message_kind(turn),
        Some(SUBAGENT_WAKE | ORCHESTRATION_WAKE | QUESTION_ANSWER)
    )
}

/// Whether `turn` was started by the answer to a question `head` asked.
pub(super) fn answers_question_of(turn: &ChatOrchestrationChildTurn, head: &str) -> bool {
    message_kind(turn) == Some(QUESTION_ANSWER)
        && turn
            .message_origin
            .as_ref()
            .and_then(|origin| origin.get("answeredTurnId"))
            .and_then(Value::as_str)
            == Some(head)
}

/// What a turn after a settled task is, when it opens a follow-up for the
/// parent: a continuation, a person's message, or the parent's own message
/// that no task tracks. `None` for anything else.
pub(super) fn followup_origin(
    turn: &ChatOrchestrationChildTurn,
    parent_chat_id: &str,
) -> Option<&'static str> {
    match turn.turn_origin.as_deref() {
        Some(BACKGROUND_CONTINUATION_ORIGIN) => return Some("a background continuation"),
        Some(GOAL_CONTINUATION_ORIGIN) => return Some("a goal continuation"),
        _ => {}
    }
    let origin = turn.message_origin.as_ref()?;
    match message_kind(turn)? {
        SUBAGENT_WAKE => Some("a sub-agent finished"),
        ORCHESTRATION_WAKE => Some("its delegated tasks reported"),
        QUESTION_ANSWER => Some("its question was answered"),
        "user" => Some("a person's message"),
        "chatMessage"
            if origin.get("senderChatId").and_then(Value::as_str) == Some(parent_chat_id)
                && origin
                    .get("taskIds")
                    .and_then(Value::as_array)
                    .is_none_or(Vec::is_empty) =>
        {
            Some("a message from its parent")
        }
        _ => None,
    }
}

/// Whether the child still works after its turn ended: background work
/// holds the session, a request or queued message waits, or a native
/// sub-agent runs.
pub(super) fn child_leftover_work(snapshot: &Value) -> bool {
    let session = &snapshot["session"];
    if session
        .get("activeTurnId")
        .is_some_and(|turn| !turn.is_null())
    {
        return false;
    }
    let non_empty = |key: &str| {
        snapshot
            .get(key)
            .and_then(Value::as_array)
            .is_some_and(|values| !values.is_empty())
    };
    matches!(session["status"].as_str(), Some("running" | "waiting"))
        || non_empty("pendingRequests")
        || non_empty("queue")
        || snapshot["backgroundSubagentsRunning"] == Value::Bool(true)
}

/// The turn the child started after `turn_id`, from the snapshot's recent
/// turns, or its active turn when the list does not show it yet.
pub(super) fn next_turn_after(snapshot: &Value, turn_id: &str) -> Option<String> {
    let turns = snapshot.get("turns").and_then(Value::as_array);
    if let Some(turns) = turns {
        if let Some(position) = turns.iter().position(|turn| turn["turnId"] == turn_id) {
            if let Some(next) = turns.get(position + 1) {
                return next["turnId"].as_str().map(ToOwned::to_owned);
            }
        }
    }
    snapshot["session"]["activeTurnId"]
        .as_str()
        .filter(|active| *active != turn_id)
        .map(ToOwned::to_owned)
}

/// Where the task's chain of turns starts, once it moved past its first.
pub(super) fn chain_start(task: &ChatOrchestrationTask) -> Option<&str> {
    task.launch_options
        .as_ref()
        .and_then(|options| options.get(CHAIN_START_TURN_KEY))
        .and_then(Value::as_str)
}

/// The turn a task follows that is no longer the one its brief started: a
/// follow-up's, or a held task's after it moved along a continuation.
pub(super) fn moved_head(task: &ChatOrchestrationTask) -> Option<&str> {
    let moved = task.kind == alera_core::runtime::ChatOrchestrationTaskKind::Followup
        || chain_start(task).is_some();
    moved.then_some(task.child_turn_id.as_deref()).flatten()
}

/// The ids of the snapshot's turns from `start` (or `head` alone) to `head`.
pub(super) fn chain_turns(snapshot: &Value, start: Option<&str>, head: &str) -> Vec<String> {
    let Some(turns) = snapshot.get("turns").and_then(Value::as_array) else {
        return vec![head.to_owned()];
    };
    let ids: Vec<&str> = turns
        .iter()
        .filter_map(|turn| turn["turnId"].as_str())
        .collect();
    let end = ids.iter().position(|id| *id == head);
    let begin = start.and_then(|start| ids.iter().position(|id| *id == start));
    match (begin, end) {
        (Some(begin), Some(end)) if begin <= end => {
            ids[begin..=end].iter().map(|id| (*id).to_owned()).collect()
        }
        _ => vec![head.to_owned()],
    }
}

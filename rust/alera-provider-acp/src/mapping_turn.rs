//! Payloads of the frames that end an ACP turn: x.ai `prompt_complete`, the
//! idle `state_update` and x.ai `turn_completed`.

use crate::mapping::{event, MappedIncoming, MappingContext};
use crate::mapping_values::{prompt_matches, terminal_state};
use alera_provider_protocol::{EventKind, TurnStatus};
use serde_json::{json, Value};

/// Grok's background command wakes use prompt ids of their own.
const TASK_COMPLETED_PROMPT: &str = "task-completed-";

/// x.ai `session/prompt_complete`, which ends the turn of the prompt it names.
pub(crate) fn prompt_complete(
    method: &str,
    params: Value,
    raw: Value,
    context: &MappingContext<'_>,
) -> MappedIncoming {
    let native_prompt_id = params
        .get("promptId")
        .or_else(|| params.get("prompt_id"))
        .and_then(Value::as_str);
    let (kind, payload) =
        if native_prompt_id.is_some_and(|id| id.starts_with(TASK_COMPLETED_PROMPT)) {
            (EventKind::TaskCompleted, params)
        } else if native_prompt_id.is_some_and(|native| {
            !prompt_matches(native, context.prompt_id, context.prompt_meta_id)
        }) {
            (EventKind::Unknown(format!("acp.{method}")), params)
        } else {
            let stop_reason = params
                .get("stopReason")
                .or_else(|| params.get("stop_reason"));
            let payload = json!({
                "state": terminal_state(stop_reason),
                "stopReason": stop_reason,
                "usage": params.get("usage"),
                "result": params.get("agentResult").or_else(|| params.get("agent_result")),
                "errorMessage": params
                    .get("errorMessage")
                    .or_else(|| params.get("error"))
                    .and_then(Value::as_str),
            });
            (EventKind::TurnCompleted, payload)
        };
    MappedIncoming {
        event: event(context, method, kind, payload, raw, None),
        pending: None,
    }
}

/// A `state_update`: an idle state ends the running turn, any other only
/// changes the thread's state.
pub(crate) fn state_update(update: &Value, context: &MappingContext<'_>) -> (EventKind, Value) {
    if update.get("state").and_then(Value::as_str) != Some("idle")
        || context.turn_id.is_none()
        || !context.idle_ends_turn
    {
        return (EventKind::ThreadStateChanged, update.clone());
    }
    let state = match update.get("stopReason").and_then(Value::as_str) {
        Some("cancelled") | Some("interrupted") => TurnStatus::Interrupted,
        Some("error") | Some("failed") => TurnStatus::Failed,
        _ => TurnStatus::Completed,
    };
    let payload = json!({
        "state": state,
        "stopReason": update.get("stopReason"),
        "usage": update.get("usage"),
        "errorMessage": update
            .get("errorMessage")
            .or_else(|| update.get("error"))
            .and_then(Value::as_str),
    });
    (EventKind::TurnCompleted, payload)
}

/// x.ai `turn_completed`. One without a prompt id ends the turn while no RPC
/// prompt is tracked, or when the prompt carries a Grok prompt id.
pub(crate) fn turn_completed(update: &Value, context: &MappingContext<'_>) -> (EventKind, Value) {
    let native_prompt_id = update
        .get("prompt_id")
        .or_else(|| update.get("promptId"))
        .and_then(Value::as_str);
    if native_prompt_id.is_some_and(|id| id.starts_with(TASK_COMPLETED_PROMPT)) {
        return (EventKind::TaskCompleted, update.clone());
    }
    let matches_prompt = native_prompt_id
        .map(|native| prompt_matches(native, context.prompt_id, context.prompt_meta_id))
        .unwrap_or(context.prompt_id.is_none() || context.prompt_meta_id.is_some());
    if !matches_prompt {
        return (
            EventKind::Unknown("acp.session-update.turn_completed".into()),
            update.clone(),
        );
    }
    let stop_reason = update
        .get("stop_reason")
        .or_else(|| update.get("stopReason"));
    let payload = json!({
        "state": terminal_state(stop_reason),
        "stopReason": stop_reason,
        "usage": update.get("usage"),
        "result": update.get("agent_result").or_else(|| update.get("agentResult")),
        "errorMessage": update
            .get("errorMessage")
            .or_else(|| update.get("error"))
            .and_then(Value::as_str),
    });
    (EventKind::TurnCompleted, payload)
}

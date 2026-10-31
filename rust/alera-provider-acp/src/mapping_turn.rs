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
            let result = params
                .get("agentResult")
                .or_else(|| params.get("agent_result"));
            let payload = completion_payload(&params, stop_reason, result);
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
    let mut payload = json!({
        "state": state,
        "stopReason": update.get("stopReason"),
        "usage": update.get("usage"),
    });
    insert_turn_error(&mut payload, update);
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
    let result = update
        .get("agent_result")
        .or_else(|| update.get("agentResult"));
    (
        EventKind::TurnCompleted,
        completion_payload(update, stop_reason, result),
    )
}

/// An x.ai completion. Grok's completion can beat the failed prompt's RPC
/// error, so a failed one without error text carries its `agentResult`.
fn completion_payload(
    source: &Value,
    stop_reason: Option<&Value>,
    result: Option<&Value>,
) -> Value {
    let state = terminal_state(stop_reason);
    let mut payload = json!({
        "state": state,
        "stopReason": stop_reason,
        "usage": source.get("usage"),
        "result": result,
    });
    insert_turn_error(&mut payload, source);
    if state == TurnStatus::Failed && payload["errorMessage"].is_null() {
        if let Some(text) = result.and_then(non_blank) {
            payload["errorMessage"] = Value::from(text);
        }
    }
    payload
}

/// Copies the error a turn ended with: the text of the first non-blank
/// `errorMessage`, string `error` or `error.message`, and a structured
/// `error`'s `code` and `data` in the shape of a failed prompt RPC.
fn insert_turn_error(payload: &mut Value, source: &Value) {
    let error = source.get("error");
    let message = [
        source.get("errorMessage"),
        error,
        error.and_then(|error| error.get("message")),
    ]
    .into_iter()
    .flatten()
    .find_map(non_blank);
    payload["errorMessage"] = message.map_or(Value::Null, Value::from);
    if let Some(error) = error.filter(|error| error.is_object()) {
        payload["error"] = json!({"code": error.get("code"), "data": error.get("data")});
    }
}

fn non_blank(value: &Value) -> Option<&str> {
    value
        .as_str()
        .map(str::trim)
        .filter(|text| !text.is_empty())
}

#[cfg(test)]
mod turn_error_tests {
    use super::insert_turn_error;
    use serde_json::{json, Value};

    fn turn_error(source: Value) -> Value {
        let mut payload = json!({});
        insert_turn_error(&mut payload, &source);
        payload
    }

    #[test]
    fn turn_error_reads_flat_string_and_structured_error() {
        assert_eq!(
            turn_error(json!({"errorMessage":"flat","error":{"message":"nested"}}))["errorMessage"],
            "flat"
        );
        assert_eq!(
            turn_error(json!({"error":"string"})),
            json!({"errorMessage":"string"})
        );
        assert_eq!(
            turn_error(
                json!({"errorMessage":" ","error":{"code":-32000,"message":"nested","data":{"retry":false}}})
            ),
            json!({"errorMessage":"nested","error":{"code":-32000,"data":{"retry":false}}})
        );
        assert_eq!(
            turn_error(json!({"error":{"message":"  "}})),
            json!({"errorMessage":null,"error":{"code":null,"data":null}})
        );
        assert_eq!(turn_error(json!({})), json!({"errorMessage":null}));
    }
}

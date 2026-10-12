use alera_core::runtime::{is_external_inbox, OrchestrationMessage, EXTERNAL_INBOX_PREFIX};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

/// Fields that name a terminal acting in orchestration. An inbox address is
/// never one: it has no terminal to dispatch to, coordinate from, or speak as,
/// and its questions go through `inbox.ask` so expiry and the pending limit
/// always apply.
fn terminal_fields(request_type: &str) -> &'static [&'static str] {
    match request_type {
        "orchestration.send" => &["from"],
        "orchestration.ask" => &["from", "to"],
        "orchestration.dispatch" => &["to", "from"],
        "orchestration.transferCoordinator" => &["to", "actor"],
        "orchestration.taskCreate" | "orchestration.taskCreateContracted" => {
            &["coordinator", "createdBy"]
        }
        "orchestration.run" | "orchestration.agentSpawn" => &["from", "coordinator", "terminal"],
        _ => &[],
    }
}

pub(super) fn reject_inbox_address(request_type: &str, payload: &Value) -> HostResult<()> {
    for field in terminal_fields(request_type) {
        let value = payload.get(*field).and_then(Value::as_str).map(str::trim);
        if value.is_some_and(is_external_inbox) {
            return Err(HostError::conflict(
                "inbox_address_not_allowed",
                format!(
                    "{field} cannot be an inbox address ({EXTERNAL_INBOX_PREFIX}...). Ask an agent from an inbox with inbox.ask."
                ),
                json!({ "field": field }),
            ));
        }
    }
    Ok(())
}

/// Replying to a message an inbox received would send a message from that
/// inbox; follow-ups are asked with `inbox.ask` instead.
pub(super) fn reject_reply_as_inbox(original: &OrchestrationMessage) -> HostResult<()> {
    if is_external_inbox(&original.to_handle) {
        return Err(HostError::conflict(
            "inbox_address_not_allowed",
            "This message was sent to an inbox; follow up with inbox.ask instead of reply.",
            json!({ "field": "id" }),
        ));
    }
    Ok(())
}

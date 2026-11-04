use serde_json::{json, Value};

use super::models::AgentChatNativeOperation;

/// Safe projection for public summaries and atomically saved reconcile wrappers.
pub fn agent_chat_native_operation_public_summary(operation: &AgentChatNativeOperation) -> Value {
    let state = match operation.state.as_str() {
        known @ ("prepared" | "executing" | "acknowledged" | "uncertain" | "completed"
        | "cancelled" | "reconciled") => known,
        _ => "unknown",
    };
    let kind = match operation.kind.as_str() {
        known @ ("rewind" | "rewindFiles") => known,
        _ => "unknown",
    };
    let known_kind = kind != "unknown";
    let active = !matches!(state, "completed" | "cancelled" | "reconciled");
    let message = match state {
        "prepared" => {
            "The history operation has not called the provider. Cancel it before continuing."
        }
        "executing" => "The history operation is being sent to the provider.",
        "acknowledged" => {
            "The provider acknowledged the operation. Finish reconciling without calling it again."
        }
        "uncertain" => {
            "The provider outcome is unknown. Choose an explicit fallback before continuing."
        }
        "completed" => "The history operation completed.",
        "cancelled" => "The unstarted history operation was cancelled.",
        "reconciled" => "The history operation was reconciled with an explicit fallback.",
        _ => "The stored history operation needs attention before this chat can continue.",
    };
    json!({"operationId":operation.operation_id,"state":state,"kind":kind,"recovery":{
        "needsReconciliation":active,"canCancelUnstarted":known_kind&&state=="prepared",
        "canFinishAcknowledged":known_kind&&state=="acknowledged"&&operation.ack.is_some(),
        "canRestartFromTranscript":state=="uncertain"&&kind=="rewind",
        "canContinueFromCurrentFiles":state=="uncertain"&&kind=="rewindFiles","message":message,
    }})
}
